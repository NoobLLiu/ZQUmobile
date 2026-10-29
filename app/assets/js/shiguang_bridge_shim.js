// 桥接适配层：把拾光课表的 window.shiguangBridge / shiguangBridgePromise
// 映射到本 App 的 window.zsyBridge 单向通道。
//
// 目的：让 shiguang_warehouse 上游的 ZQU 适配脚本可以「原文照用」，
// 不修改其任何业务逻辑（取数、解析、合并去重都用官方实现）。
// 本文件只负责把官方脚本需要的交互能力，换成无弹窗的自动通过：
//   showAlert / showPrompt / showSingleSelection  → 直接采用默认值（无 UI 阻塞）
//   saveImportedCourses / saveCourseConfig / savePresetTimeSlots → 转成消息发给 Flutter
//   notifyTaskCompletion → 通知 Flutter 可以落库了
//
// 这样课程、学期配置、作息时间会像拾光一样分三次到达，
// Flutter 侧累积齐了再一次性存，避免任何一步丢失。

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

  // 同步接口：仅提示
  window.shiguangBridge = {
    showToast: function (msg) {
      progress(msg);
    },
    notifyTaskCompletion: function () {
      post({ type: 'done' });
    }
  };

  // 异步接口：全部自动通过，不弹窗
  window.shiguangBridgePromise = {
    // 导入前的确认 → 直接同意，文案作为进度展示
    showAlert: function (title, content) {
      progress(content || title || '');
      return Promise.resolve(true);
    },
    // 开学日期确认 → 采用自动取到的默认值。
    // 取不到时返回空串（而不是 null）：官方脚本收到 null 会中止整个导入、
    // 把已经取到的课程丢弃；返回空串则流程继续，只是不写开学日期字段，
    // 由 Flutter 侧兜底推算，避免白抓一次数据。
    showPrompt: function (title, tip, defaultText) {
      progress(tip || '');
      return Promise.resolve(defaultText ? String(defaultText) : '');
    },
    // 学期选择 → 采用官方脚本给的默认索引（即教务系统的当前学期）
    showSingleSelection: function (title, itemsJson, defaultIndex) {
      return Promise.resolve(defaultIndex);
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
