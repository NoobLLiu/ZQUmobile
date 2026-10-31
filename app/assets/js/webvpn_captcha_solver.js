// WebVPN 滑块验证码自动求解器（页面内 fetch 模式）。
//
// 网瑞达（VRD/Wengine）WebVPN 登录失败后会弹出拖动滑块验证码
// （#drag-captcha-layer）。本脚本在登录页上下文里自动完成验证：
//   1. fetch GET /login/image 拉取验证码 {p: 背景, s: 碎片, h: y坐标}；
//   2. canvas 解码后用 Sobel 梯度幅值 + 归一化互相关（NCC）定位缺口：
//      缺口是照片上叠加的半透明色罩，色偏属低频，梯度域匹配对色罩
//      不敏感（对真实验证码实测零误差）；
//   3. fetch POST /login/verify 提交 w（与页面 drag.js 同构的参数）；
//   4. 成功后重新点击登录按钮走正常登录；失败则换一张图重试
//      （每张图仅可验证一次），最多 MAX_RETRY 次，超过后交还用户手动拖动。
//
// 为什么不走 DOM 合成拖动：页面的 drag.js 每次 mousedown 都会在
// document 上注册新的 mousemove/mouseup 监听器且从不清除，多次拖动
// 时旧监听器互相污染拖动状态。fetch 模式与 drag.js 的提交行为完全
// 同构（同源、同 cookie、同参数格式），但不依赖其 DOM 状态。
//
// 坐标标定（真实页面反复验证）：verify 的 w = 碎片渲染原点x - 10，
// 即 w = 缺口bbox左缘 - 碎片bbox左缘x0 - 10；碎片渲染 y = h。
//
// 全程通过 zsyBridge 以 {type:'captcha', state, message} 回传进度。
(function () {
  'use strict';

  if (window.__zsyCaptchaWatcher) return; // 幂等：页面跳转回来会重复注入
  window.__zsyCaptchaWatcher = true;

  var MAX_RETRY = 4; // 少量重试即止：连续高频请求会触发服务端 IP 风控
  var busy = false;
  var solved = false;
  var failed = false; // 本轮会话已放弃自动（交还用户），弹窗关闭才复位
  var retries = 0;

  function post(state, message) {
    var text = JSON.stringify({ type: 'captcha', state: state, message: message || '' });
    try {
      if (window.zsyBridge && window.zsyBridge.postMessage) {
        window.zsyBridge.postMessage(text);
        return;
      }
    } catch (e) { /* 桥不可用时落到控制台 */ }
    console.log('[zsy-captcha] ' + text);
  }

  // ------------------------------------------------------------ 像素与检测

  function loadPixels(src) {
    return new Promise(function (resolve, reject) {
      var img = new Image();
      img.onload = function () {
        var cv = document.createElement('canvas');
        cv.width = img.naturalWidth;
        cv.height = img.naturalHeight;
        var ctx = cv.getContext('2d');
        ctx.drawImage(img, 0, 0);
        resolve(ctx.getImageData(0, 0, cv.width, cv.height));
      };
      img.onerror = function () { reject(new Error('image load failed')); };
      img.src = src;
    });
  }

  function toGray(px) {
    var n = px.width * px.height;
    var g = new Float32Array(n);
    for (var i = 0; i < n; i++) {
      g[i] = 0.299 * px.data[i * 4] + 0.587 * px.data[i * 4 + 1] + 0.114 * px.data[i * 4 + 2];
    }
    return g;
  }

  function sobelMag(g, w, h) {
    var out = new Float32Array(w * h);
    for (var y = 1; y < h - 1; y++) {
      for (var x = 1; x < w - 1; x++) {
        var i = y * w + x;
        var gx = -g[i - w - 1] + g[i - w + 1] - 2 * g[i - 1] + 2 * g[i + 1] - g[i + w - 1] + g[i + w + 1];
        var gy = -g[i - w - 1] - 2 * g[i - w] - g[i - w + 1] + g[i + w - 1] + 2 * g[i + w] + g[i + w + 1];
        out[i] = Math.sqrt(gx * gx + gy * gy);
      }
    }
    return out;
  }

  /** 在背景梯度图上滑窗匹配模板梯度（ZNCC），y 限制在 [yMin, yMax]。 */
  function nccMatch(bgMag, bgW, tplMag, tw, th, yMin, yMax) {
    var n = tw * th;
    var tSum = 0, tSq = 0;
    for (var i = 0; i < n; i++) { tSum += tplMag[i]; tSq += tplMag[i] * tplMag[i]; }
    var tVar = tSq - tSum * tSum / n;
    if (tVar <= 0) return { x: 0, y: yMin, score: 0 };

    var best = -2, bx = 0, by = yMin;
    for (var y = yMin; y <= yMax; y++) {
      for (var x = 0; x <= bgW - tw; x++) {
        var s = 0, sq = 0, dot = 0, k = 0;
        for (var ty = 0; ty < th; ty++) {
          var row = (y + ty) * bgW + x;
          for (var tx = 0; tx < tw; tx++) {
            var v = bgMag[row + tx];
            s += v; sq += v * v; dot += v * tplMag[k++];
          }
        }
        var wVar = sq - s * s / n;
        if (wVar <= 0) continue;
        var score = (dot - s * tSum / n) / Math.sqrt(wVar * tVar);
        if (score > best) { best = score; bx = x; by = y; }
      }
    }
    return { x: bx, y: by, score: best };
  }

  /**
   * 对一对验证码图检测缺口，返回可直接提交的 w。
   * piecePx: 40x40 碎片 RGBA；bgPx: 280x200 背景；h: 碎片渲染 y。
   */
  function solveWidth(bgPx, piecePx, h) {
    // 碎片：alpha>=128 的 bbox（本系统固定 38x37、起点 (2,1)，此处动态求）
    var pw = piecePx.width, ph = piecePx.height;
    var x0 = pw, y0 = ph, x1 = -1, y1 = -1;
    for (var yy = 0; yy < ph; yy++) {
      for (var xx = 0; xx < pw; xx++) {
        if (piecePx.data[(yy * pw + xx) * 4 + 3] >= 128) {
          if (xx < x0) x0 = xx;
          if (xx > x1) x1 = xx;
          if (yy < y0) y0 = yy;
          if (yy > y1) y1 = yy;
        }
      }
    }
    var tw = x1 - x0 + 1, th = y1 - y0 + 1;
    if (tw <= 0 || th <= 0) throw new Error('piece alpha empty');

    var tplG = new Float32Array(tw * th);
    for (var ty = 0; ty < th; ty++) {
      for (var tx = 0; tx < tw; tx++) {
        var si = ((ty + y0) * pw + (tx + x0)) * 4;
        tplG[ty * tw + tx] =
          0.299 * piecePx.data[si] + 0.587 * piecePx.data[si + 1] + 0.114 * piecePx.data[si + 2];
      }
    }
    var tplMag = sobelMag(tplG, tw, th);
    var bgMag = sobelMag(toGray(bgPx), bgPx.width, bgPx.height);

    // 碎片渲染 top = h，缺口 bbox 顶部 = h + y0，搜索窗口 ±6px
    var yMin = Math.max(0, h + y0 - 6);
    var yMax = Math.min(bgPx.height - th, h + y0 + 6);
    var m = nccMatch(bgMag, bgPx.width, tplMag, tw, th, yMin, yMax);

    if (m.score < 0.25) return { w: -1, score: m.score };
    // w = 碎片渲染原点x - 10；匹配点 x 是模板左上角 → 原点 = m.x - x0
    var w = m.x - x0 - 10;
    if (w < 5 || w > bgPx.width - tw) return { w: -1, score: m.score };
    return { w: w, score: m.score };
  }

  // ------------------------------------------------------------ 协议交互

  function fetchCaptcha() {
    return fetch('/login/image?_=' + Date.now(), {
      credentials: 'same-origin',
      headers: { 'X-Requested-With': 'XMLHttpRequest' }
    }).then(function (r) { return r.json(); });
  }

  /** 提交 verify。ox/oy 为滑块手柄中心的页面坐标（模拟 drag.js 的轨迹点）。 */
  function verify(w, ox, oy) {
    var body = 'w=' + encodeURIComponent(w) +
      '&t=0' +
      '&locations%5B0%5D%5Bx%5D=' + ox +
      '&locations%5B0%5D%5By%5D=' + oy +
      '&locations%5B1%5D%5Bx%5D=' + (ox + w) +
      '&locations%5B1%5D%5By%5D=' + oy;
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

  /** 滑块手柄中心的页面坐标（drag.js 记录的就是 pageX/pageY）。 */
  function sliderOrigin() {
    var btn = document.getElementById('drap-captcha-slidetrigger');
    if (!btn) return { x: 604, y: 410 };
    var r = btn.getBoundingClientRect();
    var sx = r.left + r.width / 2 + (window.scrollX || 0);
    var sy = r.top + r.height / 2 + (window.scrollY || 0);
    return { x: Math.round(sx), y: Math.round(sy) };
  }

  /** verify 成功后重新触发登录（表单值仍在，页面自己会再次校验滑块状态）。 */
  function resubmitLogin() {
    var btns = document.querySelectorAll('button, input[type="submit"], .login-btn, a');
    for (var i = 0; i < btns.length; i++) {
      var t = btns[i].textContent || btns[i].value || '';
      if (/^\s*登\s*录\s*$/.test(t)) { btns[i].click(); return true; }
    }
    return false;
  }

  // ------------------------------------------------------------ 主流程

  function attempt() {
    return fetchCaptcha()
      .then(function (d) {
        return Promise.all([
          loadPixels(d.p), loadPixels(d.s)
        ]).then(function (px) {
          var r = solveWidth(px[0], px[1], d.h || 0);
          if (r.w < 0) {
            post('progress', '识别置信度不足(' + r.score.toFixed(3) + ')，自动换一张');
            return false;
          }
          post('progress', '识别到滑块缺口(得分' + r.score.toFixed(3) + ')，正在验证 ...');
          var o = sliderOrigin();
          return verify(r.w, o.x, o.y).then(function (res) {
            if (res && res.success === true) {
              post('solved', '滑块验证已自动完成');
              resubmitLogin();
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
        // 放缓节奏：连续快速取图会触发服务端频率限制（/login/image 403）
        setTimeout(loop, 1500 + Math.floor(Math.random() * 800));
      })
      .catch(function () {
        if (retries >= MAX_RETRY - 1) {
          failed = true;
          post('failed', '自动验证出错，请手动拖动滑块');
          busy = false;
          return;
        }
        retries++;
        setTimeout(loop, 1500 + Math.floor(Math.random() * 800));
      });
  }

  // 轮询：滑块弹窗出现即触发。弹窗关闭后重置会话，下次登录可再次自动求解。
  function layerVisible() {
    var layer = document.getElementById('drag-captcha-layer');
    if (!layer) return false;
    var st = getComputedStyle(layer);
    return st.display !== 'none' && st.visibility !== 'hidden';
  }

  setInterval(function () {
    if (!layerVisible()) {
      if (!busy) { solved = false; failed = false; retries = 0; }
      return;
    }
    if (busy || solved || failed) return;
    busy = true;
    post('progress', '检测到滑块验证，正在自动识别 ...');
    loop();
  }, 800);
})();
