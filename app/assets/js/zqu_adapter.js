// 肇庆学院教务课表取数脚本（注入 WebView 执行）。
//
// 逻辑移植自拾光课表官方适配脚本
//   shiguang_warehouse/resources/ZQU/zqu_01.js  (Apache-2.0)
//
// 与拾光的差异：拾光通过 window.shiguangBridge 回调原生提示框，
// 本 App 用更简单的单向通道 —— 把进度/结果 POST 给 window.zsyBridge，
// 由 Flutter 侧统一展示（名称必须与 Dart 的 addJavaScriptChannel('zsyBridge') 一致）。
//
// 前置条件：用户已在 WebView 中登录教务系统，停留在教务系统任意页面即可。
// 校外 WebVPN 与校内直连两种渠道都支持 —— 站点根由当前 URL 自动推导。

(function () {
  'use strict';

  // 「我的课表」内容页，学期下拉框 #xnxqdm 由服务端随页面下发
  var KB_LIST_PAGE = 'xsgrkbcx!getXsgrbkList.action';
  // 课表数据接口（返回 JSON）
  var KB_DATA = 'xsgrkbcx!getKbRq.action';

  // ---------------------------------------------------------------- 通道

  /**
   * 向 Flutter 回传消息。
   * 通道不可用时把内容打到控制台，便于排查（不再静默吞掉）。
   */
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

  /** 进度提示。 */
  function progress(message) {
    post({ type: 'progress', message: String(message) });
  }

  /** 失败上报。 */
  function fail(message) {
    post({ type: 'result', ok: false, error: String(message) });
  }

  // ---------------------------------------------------------------- 工具

  /**
   * 推算教务系统的站点根路径。
   *
   * 校内直连：https://jwgl.zqu.edu.cn/xsgrkbcx!getXsgrbkList.action
   * 校外 WebVPN：https://webvpn.zqu.edu.cn/https/<加密串>/xsgrkbcx!getXsgrbkList.action
   *
   * 二者只是站点根不同，因此不判断渠道，只按「xsgrkbcx!」之前的一段截断，
   * WebVPN 场景会自然带上 <加密串>/ 这一层。
   */
  function siteBase() {
    try {
      var u = new URL(window.location.href);
      var path = u.pathname;
      var i = path.indexOf('xsgrkbcx!');
      if (i > 0) return u.origin + path.slice(0, i);
      var j = path.lastIndexOf('/');
      return u.origin + (j > 0 ? path.slice(0, j + 1) : '/');
    } catch (e) {
      var href = window.location.href.split(/[?#]/)[0];
      var i = href.lastIndexOf('/');
      return i > 0 ? href.slice(0, i + 1) : href;
    }
  }

  /** 读取某个 document 里的下拉框选项（跳过空值项）。 */
  function readSelectOptions(doc, id) {
    var sel;
    try {
      sel = doc.querySelector('#' + id);
    } catch (e) {
      return null;
    }
    if (!sel || !sel.options) return null;

    var opts = [];
    for (var i = 0; i < sel.options.length; i++) {
      var v = String(sel.options[i].value).trim();
      if (v === '') continue;
      opts.push({ value: v, text: (sel.options[i].textContent || '').trim() });
    }
    if (opts.length === 0) return null;
    return { cur: String(sel.value).trim(), opts: opts };
  }

  /**
   * 解析节次字段，返回节号数组。
   * jcdm2 形如 "01,02,03"；jcdm 形如 "0102"（连写）。
   */
  function parseSections(jcdm2, jcdm) {
    var txt = String(jcdm2 || jcdm || '').trim();
    var nums = [];
    function push(n) {
      if (n > 0 && nums.indexOf(n) === -1) nums.push(n);
    }
    for (var raw of txt.split(/[,\s]+/)) {
      var part = raw.trim();
      if (!part || !/^\d+$/.test(part)) continue;
      if (part.length <= 2) {
        push(parseInt(part, 10));
      } else {
        for (var i = 0; i < part.length; i += 2) {
          push(parseInt(part.slice(i, i + 2), 10));
        }
      }
    }
    return nums.sort(function (a, b) { return a - b; });
  }

  /**
   * 解析周次字段，兼容区间 / 列表 / 位串 / 单双周后缀。
   */
  function parseWeekText(zc) {
    var txt = String(zc === null || zc === undefined ? '' : zc).trim();
    if (!txt) return [];

    // 位串：只由 0/1 组成且长度 >= 4
    if (/^[01]{4,}$/.test(txt)) {
      var bitOut = [];
      for (var i = 0; i < txt.length; i++) {
        if (txt[i] === '1') bitOut.push(i + 1);
      }
      return bitOut;
    }

    var cleaned = txt
      .replace(/周|星期/g, '')
      .replace(/[（(][^）)]*[）)]/g, '')
      .replace(/[单双]/g, '');

    var out = [];
    for (var raw of cleaned.split(/[,，\s]+/)) {
      var part = raw.trim();
      if (!part) continue;
      var range = /^(\d+)\s*-\s*(\d+)$/.exec(part);
      if (range) {
        var a = parseInt(range[1], 10);
        var b = parseInt(range[2], 10);
        if (a > 0 && b >= a) {
          for (var w = a; w <= b; w++) out.push(w);
        }
        continue;
      }
      if (/^\d+$/.test(part)) {
        var n = parseInt(part, 10);
        if (n > 0) out.push(n);
      }
    }
    return Array.from(new Set(out)).sort(function (a, b) { return a - b; });
  }

  /** 节次与周次合并去重（摘自拾光课程表官方 wiki 的参考实现）。 */
  function mergeAndDistinctCourses(courses) {
    if (!Array.isArray(courses) || courses.length <= 1) return courses;

    var list = courses.map(function (c) {
      return {
        name: c.name || '',
        teacher: c.teacher || '',
        position: c.position || '',
        weeks: Array.isArray(c.weeks) ? c.weeks.slice().sort(function (a, b) { return a - b; }) : []
      };
    });

    function cmp(a, b) {
      return a.name.localeCompare(b.name) ||
        a.teacher.localeCompare(b.teacher) ||
        a.position.localeCompare(b.position) ||
        (a.day || 0) - (b.day || 0) ||
        a.weeks.join(',').localeCompare(b.weeks.join(',')) ||
        (a.startSection || 0) - (b.startSection || 0);
    }
    list.sort(cmp);

    var step1Merged = [];
    var current = list[0];

    for (var i = 1; i < list.length; i++) {
      var next = list[i];

      var isSameCourseAndWeeks =
        current.name === next.name &&
        current.teacher === next.teacher &&
        current.position === next.position &&
        current.day === next.day &&
        current.weeks.join(',') === next.weeks.join(',');

      var isContinuous = current.endSection + 1 === next.startSection;
      var isDuplicate = current.startSection === next.startSection && current.endSection === next.endSection;

      if (isSameCourseAndWeeks && isContinuous) {
        current.endSection = next.endSection;
      } else if (isSameCourseAndWeeks && isDuplicate) {
        continue;
      } else {
        step1Merged.push(current);
        current = next;
      }
    }
    step1Merged.push(current);

    step1Merged.sort(function (a, b) {
      return a.name.localeCompare(b.name) ||
        a.teacher.localeCompare(b.teacher) ||
        a.position.localeCompare(b.position) ||
        (a.day || 0) - (b.day || 0) ||
        (a.startSection || 0) - (b.startSection || 0) ||
        (a.endSection || 0) - (b.endSection || 0);
    });

    var step2Merged = [];
    var cur = step1Merged[0];

    for (var i = 1; i < step1Merged.length; i++) {
      var nxt = step1Merged[i];

      var isSameCourseAndSection =
        cur.name === nxt.name &&
        cur.teacher === nxt.teacher &&
        cur.position === nxt.position &&
        cur.day === nxt.day &&
        cur.startSection === nxt.startSection &&
        cur.endSection === nxt.endSection;

      if (isSameCourseAndSection) {
        cur.weeks = Array.from(new Set(cur.weeks.concat(nxt.weeks))).sort(function (a, b) { return a - b; });
      } else {
        step2Merged.push(cur);
        cur = nxt;
      }
    }
    step2Merged.push(cur);

    return step2Merged;
  }

  // ---------------------------------------------------------------- 数据获取

  /** 读取学期下拉框（请求一次内容页并解析返回的 HTML）。 */
  async function fetchTermOptions(base) {
    var resp = await fetch(base + KB_LIST_PAGE, { method: 'GET', credentials: 'include' });
    if (!resp.ok) throw new Error('学期列表请求失败（HTTP ' + resp.status + '）');

    var html = await resp.text();
    var doc = new DOMParser().parseFromString(html, 'text/html');
    var terms = readSelectOptions(doc, 'xnxqdm');
    if (!terms) throw new Error('未找到学期列表，请确认已登录并进入教务系统');
    return terms;
  }

  /**
   * 请求整个学期的课表原始数据（一次请求）。
   * zc 传空表示不限周次，服务端返回整学期数据，每条自带 zc 标明上课周次。
   */
  async function fetchTermData(base, termCode) {
    var url = base + KB_DATA +
      '?xnxqdm=' + encodeURIComponent(termCode) +
      '&zc=&xsdm=';

    var resp = await fetch(url, {
      method: 'GET',
      credentials: 'include',
      headers: { 'X-Requested-With': 'XMLHttpRequest' }
    });
    if (!resp.ok) return null;

    var text = await resp.text();
    var data;
    try {
      data = JSON.parse(text);
    } catch (e) {
      // 未登录/被拦截时会返回 HTML
      return null;
    }
    if (!Array.isArray(data) || data.length < 2) return null;
    return data[0] || [];
  }

  /**
   * 请求第 1 周的课表，取其中的周一日期作为学期开始日期。
   * 不限周次的那次请求不返回日期数组，故单独取一次第 1 周。
   */
  async function fetchFirstWeekStart(base, termCode) {
    var url = base + KB_DATA +
      '?xnxqdm=' + encodeURIComponent(termCode) +
      '&zc=1&xsdm=';

    try {
      var resp = await fetch(url, {
        method: 'GET',
        credentials: 'include',
        headers: { 'X-Requested-With': 'XMLHttpRequest' }
      });
      if (!resp.ok) return null;

      var data = JSON.parse(await resp.text());
      if (!Array.isArray(data) || data.length < 2) return null;

      for (var d of (data[1] || [])) {
        if (!d) continue;
        if (parseInt(d.xqmc, 10) !== 1) continue;
        var rq = String(d.rq || '').trim();
        if (/^\d{4}-\d{2}-\d{2}$/.test(rq)) return rq;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /** 解析整学期数据，聚合成课程数组。 */
  function collectCourses(records) {
    var courses = [];

    for (var c of records) {
      if (!c || typeof c !== 'object') continue;

      var day = parseInt(c.xq, 10);
      if (!Number.isInteger(day) || day < 1 || day > 7) continue;

      var name = String(c.kcmc || '').trim();
      if (!name) continue;

      var sections = parseSections(c.jcdm2, c.jcdm);
      if (sections.length === 0) continue;

      var weeks = parseWeekText(c.zc);
      if (weeks.length === 0) continue;

      var teacher = String(c.teaxms || '').trim();
      var position = String(c.jxcdmc || '').trim() || '未获取到教室';
      var startSection = sections[0];
      var endSection = sections[sections.length - 1];

      var exist = courses.find(function (x) {
        return x.name === name && x.teacher === teacher && x.position === position &&
          x.day === day && x.startSection === startSection && x.endSection === endSection;
      });
      if (exist) {
        exist.weeks = Array.from(new Set(exist.weeks.concat(weeks))).sort(function (a, b) { return a - b; });
      } else {
        courses.push({
          name: name,
          teacher: teacher,
          position: position,
          day: day,
          startSection: startSection,
          endSection: endSection,
          weeks: weeks
        });
      }
    }

    var totalWeeks = courses.reduce(function (max, c) {
      return c.weeks.reduce(function (m, w) { return w > m ? w : m; }, max);
    }, 0);

    return {
      courses: mergeAndDistinctCourses(courses),
      totalWeeks: totalWeeks
    };
  }

  // ---------------------------------------------------------------- 主流程

  async function runImportFlow() {
    progress('正在读取学期列表 ...');

    var base = siteBase();

    var terms;
    try {
      terms = await fetchTermOptions(base);
    } catch (error) {
      fail('读取学期失败：' + error.message +
        '\n请确认已登录教务系统，且当前停留在教务系统内的页面。');
      return;
    }

    // 取学期下拉框当前值（教务默认当前学期）
    var term = null;
    for (var i = 0; i < terms.opts.length; i++) {
      if (terms.opts[i].value === terms.cur) { term = terms.opts[i]; break; }
    }
    if (!term) term = terms.opts[0];
    if (!term) { fail('未找到可用学期'); return; }

    progress('正在读取「' + term.text + '」课表 ...');

    var records = await fetchTermData(base, term.value);
    if (!records) {
      fail('课表接口未返回数据。\n可能原因：登录已失效，或当前页面不在教务系统内。');
      return;
    }

    var result = collectCourses(records);
    if (result.courses.length === 0) {
      fail('未获取到课表数据，请确认该学期已选课。');
      return;
    }

    progress('正在确认开学日期 ...');
    var startDate = await fetchFirstWeekStart(base, term.value);

    post({
      type: 'result',
      ok: true,
      term: term.value,
      termName: term.text,
      semesterStartDate: startDate || '',
      totalWeeks: result.totalWeeks,
      courses: result.courses,
      timeSlots: []
    });
  }

  // 兜住任何未预期的异常，避免「点了没反应」
  runImportFlow().catch(function (e) {
    fail('导入过程出错：' + (e && e.message ? e.message : e));
  });
})();
