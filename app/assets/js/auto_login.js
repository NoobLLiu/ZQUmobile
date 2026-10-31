// 自动登录编排：在登录页上下文里代填账号密码、点登录、等滑块/验证码、
// 一路推进到教务系统主页。
//
// 设计原则：**只做「人本来会做的动作」**——往 DOM 输入框里填值、点按钮，
// 提交逻辑（WebVPN 的 AES 加密、教务的 Base64 密码 + ajax）全部交给页面
// 自己的脚本执行。这样不会因为加密方式或接口参数变更而失效。
//
// 覆盖三个页面形态（每次页面加载由 Flutter 重新注入本脚本）：
//   1. WebVPN 登录页（#user_name + input[name=password] + #login）
//      → 填账号密码 + 点登录；滑块由 webvpn_captcha_solver.js 自动完成；
//   2. 教务系统登录页（#account + #password + #submit_btn + 可选 #j_captcha）
//      → 填账号密码；需要验证码时把图转成 dataURL 交给 Flutter 显示，
//        用户输入后调 submitCaptcha() 回填并点登录；
//   3. 其他页面（WebVPN 首页 / 教务主页）
//      → WebVPN 首页自动找「教务系统」入口点进去；教务主页即视为登录完成。
//
// 登录结果不读页面弹窗（教务用的是 layer 1.x，DOM 类名各版本不一致），
// 而是钩住 XMLHttpRequest 直接读 doLogin / do-login 的 JSON 回包。
//
// 全程通过 zsyBridge 以 {type:'autologin', state, message} 回传进度。
(function () {
  'use strict';

  if (window.__zsyAutoLogin) return; // 同一页面只初始化一次

  var cfg = null;
  var stopped = false;
  var timer = null;

  // 每个页面实例的动作只做一次，避免轮询里重复点击
  var did = {
    vpnFill: false,
    vpnClick: false,
    jwglFill: false,
    jwglClick: false,
    captchaPosted: false,
    captchaRetry: false,
    otherClicked: false,
    needHelp: false,
    done: false
  };

  // ------------------------------------------------------------ 回传

  function post(state, message, extra) {
    var o = { type: 'autologin', state: state, message: message || '' };
    if (extra) {
      for (var k in extra) {
        if (Object.prototype.hasOwnProperty.call(extra, k)) o[k] = extra[k];
      }
    }
    var text = JSON.stringify(o);
    try {
      if (window.zsyBridge && window.zsyBridge.postMessage) {
        window.zsyBridge.postMessage(text);
        return;
      }
    } catch (e) { /* 桥不可用时落到控制台 */ }
    console.log('[zsy-auto] ' + text);
  }

  // ------------------------------------------------------------ 网络回包

  // 钩住 XHR：把 doLogin / do-login 的 JSON 回包记在 window.__zsyLastLogin。
  // 页面自己的 ajax 用的是 XHR（jQuery），所以能抓到；不改动任何请求。
  function installAjaxHook() {
    if (window.__zsyAjaxHooked) return;
    window.__zsyAjaxHooked = true;
    var origOpen = XMLHttpRequest.prototype.open;
    var origSend = XMLHttpRequest.prototype.send;

    XMLHttpRequest.prototype.open = function (m, u) {
      this.__zsyUrl = String(u || '');
      return origOpen.apply(this, arguments);
    };
    XMLHttpRequest.prototype.send = function () {
      var xhr = this;
      var url = xhr.__zsyUrl || '';
      if (/doLogin|do-login/.test(url)) {
        xhr.addEventListener('loadend', function () {
          var text = '';
          try { text = xhr.responseText || ''; } catch (e) { return; }
          var data = null;
          try { data = JSON.parse(text); } catch (e) { data = null; }
          window.__zsyLastLogin = { url: url, text: text.slice(0, 400), data: data };
        });
      }
      return origSend.apply(this, arguments);
    };
  }

  /** 取出并消费上一次登录接口的回包（只认匹配的 url）。 */
  function takeLoginResult(pattern) {
    var r = window.__zsyLastLogin;
    if (!r || !r.data || !pattern.test(r.url || '')) return null;
    window.__zsyLastLogin = null;
    return r.data;
  }

  // ------------------------------------------------------------ DOM 小工具

  function byId(id) {
    return document.getElementById(id);
  }

  function isVisible(el) {
    if (!el) return false;
    var st = window.getComputedStyle(el);
    if (st.display === 'none' || st.visibility === 'hidden') return false;
    return el.getBoundingClientRect().width > 0;
  }

  /** 填值并派发事件：让 jQuery 的 val()/change 监听都能感知。 */
  function setValue(el, v) {
    if (!el) return false;
    try { el.focus(); } catch (e) { /* ignore */ }
    el.value = v;
    ['input', 'change', 'keyup'].forEach(function (t) {
      try { el.dispatchEvent(new Event(t, { bubbles: true })); } catch (e) { /* ignore */ }
    });
    try { el.blur(); } catch (e) { /* ignore */ }
    return true;
  }

  /** 当前页面属于哪种登录形态。 */
  function pageKind() {
    if (byId('user_name') && byId('login') &&
        document.querySelector('input[name="password"]')) {
      return 'webvpn-login';
    }
    if (byId('account') && byId('submit_btn') && byId('password')) {
      return 'jwgl-login';
    }
    return 'other';
  }

  function sliderVisible() {
    return isVisible(byId('drag-captcha-layer'));
  }

  function whenReady(img, cb) {
    if (img.complete && img.naturalWidth) { cb(); return; }
    var n = 0;
    var t = setInterval(function () {
      n++;
      if (img.complete && img.naturalWidth) {
        clearInterval(t);
        cb();
      } else if (n > 40) {
        clearInterval(t);
      }
    }, 100);
  }

  // ------------------------------------------------------------ WebVPN

  function webvpnPasswordInput() {
    var form = byId('form');
    var el = form ? form.querySelector('input[name="password"]') : null;
    return el || document.querySelector('input[name="password"]');
  }

  function stepWebvpn() {
    if (!did.vpnFill) {
      did.vpnFill = true;
      setValue(byId('user_name'), cfg.sid);
      setValue(webvpnPasswordInput(), cfg.webvpnPwd);
      post('progress', '已填写 WebVPN 账号与密码');
      return;
    }

    var res = takeLoginResult(/do-login/);
    if (res) {
      if (res.success) {
        post('progress', 'WebVPN 登录成功，正在进入 ...');
        return; // 页面自己会跳转
      }
      var msg = String(res.message || res.error || '');
      if (res.error === 'TOO_MANY_ATTEMPTS') msg = '尝试次数过多，请稍后再试';
      if (res.error === 'INVALID_ACCOUNT') msg = '账号或密码不正确';
      post('failed', 'WebVPN 登录失败：' + (msg || '未知原因'));
      stopped = true;
      return;
    }

    // 滑块弹出来了：交给求解器，别抢着点登录（会打断它的流程）
    if (sliderVisible()) {
      post('slider', '正在自动完成滑块验证 ...');
      return;
    }

    if (did.vpnClick) return;
    var pwd = webvpnPasswordInput();
    if (!pwd || !pwd.value) return;

    did.vpnClick = true;
    post('submitting', '正在登录 WebVPN ...');
    var btn = byId('login');
    if (btn) btn.click();
  }

  // ------------------------------------------------------------ 教务系统

  function captchaBoxVisible() {
    return isVisible(byId('verifyDiv'));
  }

  function captchaImg() {
    var img = byId('captcha_img');
    if (!img) return null;
    var src = img.getAttribute('src') || '';
    if (src.indexOf('yzm') < 0) {
      img.setAttribute('src', '/yzm?d=' + Date.now());
    }
    return img;
  }

  /**
   * 把验证码图转成 dataURL 交给 Flutter（同源，canvas 不会被污染）。
   * 图片宽度决定位数：实测 200px→4 位、280px→5 位、350px→6 位。
   */
  function postCaptcha(img) {
    if (!img || !img.complete || !img.naturalWidth) return false;
    var w = img.naturalWidth;
    var extra = {
      width: w,
      height: img.naturalHeight,
      expected: Math.max(3, Math.round(w / 55))
    };
    try {
      var cv = document.createElement('canvas');
      cv.width = img.naturalWidth;
      cv.height = img.naturalHeight;
      cv.getContext('2d').drawImage(img, 0, 0);
      extra.image = cv.toDataURL('image/jpeg', 0.85);
    } catch (e) {
      /* 取不到图就让用户自己看网页 */
    }
    post('captcha', '请输入图中验证码，其余步骤自动完成', extra);
    return !!extra.image;
  }

  function askCaptcha() {
    var img = captchaImg();
    if (img && !did.captchaPosted) {
      did.captchaPosted = true;
      whenReady(img, function () {
        if (!postCaptcha(img)) {
          // 图取不到（跨域/画布被污染）时至少让用户看网页自己输
          post('captcha', '请输入图中验证码，其余步骤自动完成');
        }
      });
    }
  }

  /** 换一张验证码图并重新交给 Flutter。 */
  function refreshCaptchaAndAsk() {
    var img = captchaImg();
    var inp = byId('j_captcha');
    if (inp) setValue(inp, '');
    did.captchaPosted = false;
    if (!img) {
      post('captcha', '请输入图中验证码，其余步骤自动完成');
      return;
    }
    img.setAttribute('src', '/yzm?d=' + Date.now());
    whenReady(img, function () {
      did.captchaPosted = true;
      if (!postCaptcha(img)) {
        post('captcha', '请输入图中验证码，其余步骤自动完成');
      }
    });
  }

  function stepJwgl() {
    if (!did.jwglFill) {
      did.jwglFill = true;
      setValue(byId('account'), cfg.sid);
      setValue(byId('password'), cfg.jwglPwd);
      post('progress', '已填写教务系统账号与密码');
      return;
    }

    // 看服务端回包：验证码错就换图重来，账号密码错就收手
    var res = takeLoginResult(/doLogin/);
    if (res) {
      if (res.status === 'y') {
        post('jwgl-ok', '教务系统登录成功，正在进入主页 ...');
        return; // 页面自己会跳转到 result.msg
      }
      var msg = String(res.msg || '');
      if (/验证码/.test(msg)) {
        did.jwglClick = false;
        post('progress', msg + '，正在换一张 ...');
        setTimeout(refreshCaptchaAndAsk, 600);
        return;
      }
      post('failed', '教务系统登录失败：' + (msg || '未知原因'));
      stopped = true;
      return;
    }

    if (captchaBoxVisible()) {
      askCaptcha();
      // 验证码由 Flutter 收上去 → submitCaptcha() 回填并提交，这里不再点
      return;
    }

    if (did.jwglClick) return;
    var pwd = byId('password');
    if (!pwd || !pwd.value) return;

    did.jwglClick = true;
    post('submitted', '正在登录教务系统 ...');
    var btn = byId('submit_btn');
    if (btn) btn.click();
  }

  // ------------------------------------------------------------ 其他页面

  /** 在 WebVPN 首页里找「教务系统」入口。 */
  function findJwglLink() {
    var els = document.querySelectorAll('a[href], [data-url], [data-href], [onclick]');
    for (var i = 0; i < els.length; i++) {
      var el = els[i];
      var text = (el.textContent || '') + ' ' +
        (el.getAttribute('title') || '') + ' ' +
        (el.getAttribute('data-title') || '') + ' ' +
        (el.getAttribute('data-name') || '');
      var href = el.getAttribute('href') || el.getAttribute('data-url') ||
        el.getAttribute('data-href') || '';
      if (/教务|教学管理|教学系统/.test(text) || /jwgl\.zqu\.edu\.cn/i.test(href)) {
        return el;
      }
    }
    return null;
  }

  /**
   * 是否已经站在教务主页上。
   *
   * 需要这个判断是因为「会话还在」的情况：WebView 的 cookie 会跨启动保留，
   * 重开 App 时校外用户会被网关直接送进教务主页（不再是登录页），
   * 这时既没有提交记录、expect 也还是 webvpn，光靠 else 分支会一直找「教务入口」。
   *
   * 判据取「教务站本身」或「WebVPN 代理路径 /http/<token>/」+ 标题含教学管理/教务，
   * 避免把网关的中转页误判成主页。
   */
  function looksLikeJwglHome() {
    if (pageKind() !== 'other') return false;
    var host = location.hostname || '';
    var proxied = /^\/http\//.test(location.pathname || '');
    if (!/jwgl\.zqu\.edu\.cn/i.test(host) && !proxied) return false;
    return /教学管理|教务/.test(document.title || '');
  }

  function stepOther() {
    // 已经登录并停在教务主页（包括重开 App 后会话仍有效的情况）
    if (looksLikeJwglHome()) {
      finish('已登录教务系统');
      return;
    }
    // 教务提交后跳到了新页面 → 登录成功
    if (cfg.submitted) {
      finish('已登录教务系统');
      return;
    }
    // 校内直连且没有登录表单 → 说明会话还在，已经在教务里了
    if (cfg.expect === 'jwgl') {
      finish('已进入教务系统');
      return;
    }

    if (did.otherClicked) return;
    var link = findJwglLink();
    if (!link) {
      if (!did.needHelp) {
        did.needHelp = true;
        post('need-help',
          '请在页面中点击「教务系统」入口，点开后会继续自动登录');
      }
      return;
    }
    did.otherClicked = true;
    post('entering-jwgl', '正在进入教务系统 ...');
    link.click();
  }

  function finish(message) {
    if (did.done) return;
    did.done = true;
    post('done', message || '登录完成');
    stopped = true;
  }

  // ------------------------------------------------------------ 主循环

  function tick() {
    if (stopped || !cfg) return;
    try {
      var k = pageKind();
      if (k === 'webvpn-login') stepWebvpn();
      else if (k === 'jwgl-login') stepJwgl();
      else stepOther();
    } catch (e) {
      /* 页面结构变了也不要打断，继续下一轮 */
    }
  }

  function startTimer() {
    if (timer) return;
    timer = setInterval(tick, 600);
    setTimeout(tick, 200);
  }

  installAjaxHook();

  window.__zsyAutoLogin = {
    start: function (config) {
      cfg = config || null;
      stopped = false;
      if (cfg) startTimer();
    },
    stop: function () {
      stopped = true;
      if (timer) {
        clearInterval(timer);
        timer = null;
      }
    },
    /** Flutter 收到用户输入的验证码后回填并提交。 */
    submitCaptcha: function (text) {
      var inp = byId('j_captcha');
      if (!inp) return false;
      setValue(inp, String(text || ''));
      post('submitted', '验证码已填写，正在登录教务系统 ...');
      setTimeout(function () {
        var btn = byId('submit_btn');
        if (btn) btn.click();
      }, 120);
      return true;
    },
    /** 换一张验证码图并重新回传给 Flutter。 */
    refreshCaptcha: function () {
      refreshCaptchaAndAsk();
      return true;
    }
  };
})();
