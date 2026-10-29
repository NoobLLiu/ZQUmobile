// 桥接适配层：把拾光课表的 window.shiguangBridge / shiguangBridgePromise
// 映射到本 App 的 window.zsyBridge。
//
// 目的：让 shiguang_warehouse 上游的 ZQU 适配脚本可以「原文照用」，
// 不修改其任何业务逻辑（取数、解析、合并去重都用官方实现）。
//
// 两个方向：
//   JS → Flutter：进度、课程、学期配置、作息时间、完成通过 post() 单向发送；
//   Flutter → JS：学期选择、开学日期确认这类需要用户输入的操作，
//                 用 request() 发一个带 id 的请求，等 Flutter 调用
//                 window.__zsyResolve(id, value) 回填结果后 Promise 才 resolve。
//                 这样官方脚本的 await 会真正挂起，和拾光弹窗体验一致。

(function () {
  'use strict';

  function post(payload) {
    var text = JSON.stringify(payload);
    try {
      if (window.zsyBridge && window.zsyBridge.postMessage) {
        window.zsyBridge.postMessage(text);
        return;
      }
    } catch (e) {
      /* 落到下面的控制台输出 */
    }
    console.log('[zsy] ' + text);
  }

  function progress(message) {
    post({ type: 'progress', message: String(message) });
  }

  function fail(message) {
    post({ type: 'result', ok: false, error: String(message) });
  }

  // ------------------------------------------------------------ 双向请求

  var pending = {};
  var seq = 0;

  /**
   * 发一个请求给 Flutter，等它回填结果。
   * @param {string} requestType 请求类型（term / startDate）
   * @param {object} payload     附带的参数
   * @returns {Promise<any>} 用户选择的结果
   */
  function request(requestType, payload) {
    return new Promise(function (resolve) {
      var id = 'r' + (++seq);
      pending[id] = resolve;
      post({
        type: 'request',
        requestId: id,
        requestType: requestType,
        payload: payload || {}
      });
    });
  }

  /** 由 Flutter 调用，回填某个请求的结果。 */
  window.__zsyResolve = function (id, value) {
    var cb = pending[id];
    if (!cb) return false;
    delete pending[id];
    cb(value);
    return true;
  };

  // ------------------------------------------------------------ 同步接口

  window.shiguangBridge = {
    showToast: function (msg) {
      progress(msg);
    },
    notifyTaskCompletion: function () {
      post({ type: 'done' });
    }
  };

  // ------------------------------------------------------------ 异步接口

  window.shiguangBridgePromise = {
    // 导入前的说明 → 直接同意（文案作为进度展示，不打断用户）
    showAlert: function (title, content) {
      progress(content || title || '');
      return Promise.resolve(true);
    },

    // 开学日期确认 → 弹日期选择框，默认值用自动取到的日期。
    // 用户取消返回 null（官方脚本会中止），避免写入错误的开学日期。
    showPrompt: function (title, tip, defaultText) {
      return request('startDate', {
        title: String(title || '确认开学日期'),
        tip: String(tip || ''),
        defaultText: String(defaultText || '')
      });
    },

    // 学期选择 → 弹学期列表让用户选，默认选中当前学年学期。
    showSingleSelection: function (title, itemsJson, defaultIndex) {
      var items = [];
      try {
        items = JSON.parse(itemsJson) || [];
      } catch (e) {
        items = [];
      }

      // 官方给的 defaultIndex 在「下拉框当前值取不到」时会退回 0（最老的学期），
      // 所以这里按当前日期重算一个更合理的默认值。
      var fallback = defaultIndex;
      try {
        var now = new Date();
        var year = now.getFullYear();
        var month = now.getMonth() + 1;
        var acadStart = month >= 9 ? year : year - 1;
        var acad = acadStart + '-' + (acadStart + 1);
        var termNo = (month >= 9 || month === 1) ? '1' : '2';

        var exact = -1;
        var sameYear = -1;
        for (var i = 0; i < items.length; i++) {
          var text = String(items[i] || '');
          if (text.indexOf(acad) === -1) continue;
          if (sameYear === -1) sameYear = i;
          if (text.indexOf(termNo) !== -1) exact = i;
        }
        if (exact >= 0) fallback = exact;
        else if (sameYear >= 0) fallback = sameYear;
        else if (items.length > 0) fallback = items.length - 1;
      } catch (e) {
        /* 保持官方给的默认值 */
      }

      return request('term', {
        title: String(title || '选择学期'),
        items: items,
        defaultIndex: fallback
      });
    },

    saveImportedCourses: function (json) {
      post({ type: 'courses', courses: JSON.parse(json) });
      return Promise.resolve(true);
    },
    saveCourseConfig: function (json) {
      post({ type: 'config', config: JSON.parse(json) });
      return Promise.resolve(true);
    },
    savePresetTimeSlots: function (json) {
      post({ type: 'slots', slots: JSON.parse(json) });
      return Promise.resolve(true);
    }
  };

  // 兜住未捕获异常，避免「点了没反应」
  window.addEventListener('error', function (e) {
    fail('页面脚本异常：' + (e && e.message ? e.message : e));
  });
  window.addEventListener('unhandledrejection', function (e) {
    var r = e && e.reason;
    fail('页面脚本异常：' + ((r && r.message) || r || '未知错误'));
  });
})();
