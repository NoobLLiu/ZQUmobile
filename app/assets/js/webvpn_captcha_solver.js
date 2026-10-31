/**
 * WebVPN 滑块验证码自动求解。
 *
 * 算法参考 D:\AICode\ZQU\GetTimeTable\zqu-timetable-scraper（已验证可用）：
 *   1. 背景图里的缺口是**蓝色拼图块**（HSV H≈150-210°），用颜色分割定位；
 *   2. 位移公式：w = cx * scale - 30 + 10（cx=缺口中心，scale=背景CSS宽/280，
 *      30=初始left(10)+半宽(20)，+10=实测服务端偏左需右移）；
 *   3. verify 提交：t=0（与页面 drag.js 一致——startTime/endTime 从未赋值），
 *      locations 用 clientX 轨迹；
 *   4. verify 成功后：layer.close + 点 #login（等价于 drag.js 的 verifySuccess）。
 */
(function () {
  'use strict';

  if (window.__zsyCaptchaWatcher) return;
  window.__zsyCaptchaWatcher = true;

  var MAX_RETRY = 6;
  var retries = 0;
  var busy = false;
  var failed = false;

  function post(state, message) {
    var text = JSON.stringify({ type: 'captcha', state: state, message: message || '' });
    try {
      if (window.zsyBridge && window.zsyBridge.postMessage) {
        window.zsyBridge.postMessage(text);
        return;
      }
    } catch (e) {}
    console.log('[zsy-captcha] ' + text);
  }

  // ------------------------------------------------------------ 图像

  function loadPixels(src) {
    return new Promise(function (resolve, reject) {
      var img = new Image();
      img.onload = function () {
        var cv = document.createElement('canvas');
        cv.width = img.naturalWidth;
        cv.height = img.naturalHeight;
        cv.getContext('2d').drawImage(img, 0, 0);
        resolve(cv.getContext('2d').getImageData(0, 0, cv.width, cv.height));
      };
      img.onerror = function () { reject(new Error('image load failed')); };
      img.src = src;
    });
  }

  function rgbToHsv(r, g, b) {
    var mx = Math.max(r, g, b), mn = Math.min(r, g, b);
    var v = mx;
    var s = mx === 0 ? 0 : (mx - mn) / mx * 255;
    var h = 0;
    if (mx !== mn) {
      var d = mx - mn;
      if (mx === r) h = (g - b) / d + (g < b ? 6 : 0);
      else if (mx === g) h = (b - r) / d + 2;
      else h = (r - g) / d + 4;
      h *= 60;
    }
    return [h, s, v];
  }

  /**
   * 在背景图里找蓝色缺口色块，返回 {cx, cy, w, h} 或 null。
   * 蓝色范围（HSV）：H=150-210°（青到蓝），S>50，V>100。
   * 实测 webvpn.zqu.edu.cn 的缺口 H≈171-186°，S≈62-86，V≈135-178。
   */
  function findGap(bgPx) {
    var w = bgPx.width, h = bgPx.height;
    var minX = w, maxX = -1, minY = h, maxY = -1, cnt = 0;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var si = (y * w + x) * 4;
        var hsv = rgbToHsv(bgPx.data[si], bgPx.data[si + 1], bgPx.data[si + 2]);
        if (hsv[0] >= 150 && hsv[0] <= 210 && hsv[1] > 50 && hsv[2] > 100) {
          cnt++;
          if (x < minX) minX = x; if (x > maxX) maxX = x;
          if (y < minY) minY = y; if (y > maxY) maxY = y;
        }
      }
    }
    if (cnt < 50) return null;
    var gw = maxX - minX + 1, gh = maxY - minY + 1;
    // 缺口尺寸应接近碎片（25~55px），太小是噪点
    if (gw < 25 || gw > 55 || gh < 25 || gh > 55) return null;
    return {
      cx: Math.round(minX + gw / 2),
      cy: Math.round(minY + gh / 2),
      w: gw, h: gh, count: cnt
    };
  }

  // ------------------------------------------------------------ 协议交互

  function fetchCaptcha() {
    return fetch('/login/image?_=' + Date.now(), {
      credentials: 'same-origin',
      headers: { 'X-Requested-With': 'XMLHttpRequest' }
    }).then(function (r) { return r.json(); });
  }

  function getMetrics() {
    var footer = document.querySelector('.drag-captcha-footer');
    var btnEl = document.getElementById('drap-captcha-slidetrigger');
    var bgEl = document.querySelector('.drag-captcha-bg img');
    if (!footer || !btnEl || !bgEl) return null;
    var fb = footer.getBoundingClientRect();
    var bb = btnEl.getBoundingClientRect();
    var bgb = bgEl.getBoundingClientRect();
    return {
      trackW: fb.width,
      btnW: bb.width,
      btnX: bb.x + bb.width / 2,
      btnY: bb.y + bb.height / 2,
      bgScale: bgb.width / 280
    };
  }

  /** 提交 verify（t=0 与页面 drag.js 一致）。 */
  function verify(w, ox, oy) {
    var pts = [];
    var n = 5;
    for (var i = 0; i <= n; i++) {
      var f = i / n;
      var eased = 1 - Math.pow(1 - f, 2);
      pts.push({
        x: Math.round(ox + w * eased),
        y: Math.round(oy)
      });
    }
    var body = 'w=' + encodeURIComponent(w) + '&t=0';
    for (var k = 0; k < pts.length; k++) {
      body += '&locations%5B' + k + '%5D%5Bx%5D=' + pts[k].x +
        '&locations%5B' + k + '%5D%5By%5D=' + pts[k].y;
    }
    return fetch('/login/verify', {
      method: 'POST',
      credentials: 'same-origin',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
        'X-Requested-With': 'XMLHttpRequest'
      },
      body: body
    }).then(function (r) { return r.json(); });
  }

  /** verify 成功后：关滑块层 + 点登录（等价于 drag.js 的 verifySuccess）。 */
  function afterVerifySuccess() {
    try { if (typeof layer !== 'undefined') layer.close(layer.index); } catch (e) {}
    setTimeout(function () {
      var btn = document.getElementById('login');
      if (btn) btn.click();
    }, 500);
  }

  // ------------------------------------------------------------ 主流程

  function attempt() {
    return fetchCaptcha()
      .then(function (d) {
        return loadPixels(d.p).then(function (bgPx) {
          var gap = findGap(bgPx);
          if (!gap) {
            post('progress', '未找到蓝色缺口，自动换一张');
            return false;
          }
          var m = getMetrics();
          if (!m) {
            post('progress', '滑块几何信息不可用，自动换一张');
            return false;
          }
          var scale = m.bgScale || 1.0;
          // 参考公式：位移 = 缺口中心 * 缩放 - 30 + 10(实测微调)
          var dx = Math.round(gap.cx * scale - 30 + 10);
          if (dx < 5 || dx > m.trackW - m.btnW) {
            post('progress', '位移越界(dx=' + dx + ')，自动换一张');
            return false;
          }
          post('progress', '识别到缺口(cx=' + gap.cx + ',dx=' + dx + ')，正在验证 ...');
          return verify(dx, m.btnX, m.btnY).then(function (res) {
            if (res && res.success === true) {
              post('solved', '滑块验证已自动完成');
              afterVerifySuccess();
              return true;
            }
            post('progress', '第' + (retries + 1) + '次验证未通过，自动换一张重试');
            return false;
          });
        });
      });
  }

  function loop() {
    attempt()
      .then(function (ok) {
        if (ok || retries >= MAX_RETRY - 1) {
          if (!ok) { failed = true; post('failed', '自动验证多次未通过，请手动拖动滑块'); }
          busy = false;
          return;
        }
        retries++;
        setTimeout(loop, 1500 + Math.floor(Math.random() * 800));
      })
      .catch(function (e) {
        post('progress', '求解异常(' + String(e).slice(0, 80) + ')，重试 ...');
        if (retries < MAX_RETRY - 1) {
          retries++;
          setTimeout(loop, 1500);
        } else {
          failed = true;
          post('failed', '自动验证异常，请手动拖动滑块');
          busy = false;
        }
      });
  }

  // 轮询：滑块层出现就开始求解
  setInterval(function () {
    if (busy || failed) return;
    var layer = document.getElementById('drag-captcha-layer');
    if (!layer) return;
    var st = window.getComputedStyle(layer);
    if (st.display === 'none' || layer.getBoundingClientRect().width === 0) return;
    // 滑块可见 → 开始
    busy = true;
    retries = 0;
    post('progress', '检测到滑块验证，正在自动识别 ...');
    loop();
  }, 800);
})();
