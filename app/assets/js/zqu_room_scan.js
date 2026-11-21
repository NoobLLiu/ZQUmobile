// ============================================================================
// 班级课表扫描脚本（空教室功能的数据采集端）v3。
//
// 核心逻辑来自实测可用的全校课表导出脚本（NoobLLiu，MIT）：
//   全校班级列表：POST xsbjkbcx!getFind.action
//       body: guid=zydm&xnxqdm=<学期>&xqdm=&rxnf=&xsyxdm=&zydm=
//       院系/专业/入学年份全部留空时，一次返回全校全部班级（约 3500+ 条），
//       响应为文本 "zydm^getFind:[{dm:班级代码, mc:班级名称}, ...]"。
//   班级课表数据：GET xsbjkbcx!getKbRq.action?xnxqdm=<学期>&zc=&xsdm=&bjdm=<班级>
//       返回 JSON 与个人课表接口同构：data[0] 为排课记录，data[1] 为日期数组。
//       zc 传空即不限周次（整学期），每条记录自带 zc 字段标明上课周次。
//
// 适用范围：校外经 WebVPN 访问、或校内直连，由页面 URL 自动识别（siteBase）。
// 使用前提：已在当前页面登录教务系统，停留在教务系统任意页面即可。
//
// 回传协议（经 window.zsyBridge 发给 Flutter）：
//   {type:'roomscan_progress', message}                       进度
//   {type:'roomscan_batch', classes:[...], lessons:[...]}     每 50 个班一批
//   {type:'roomscan_done', ok:true, term, ..., diag:{...}}    完成（带诊断）
//   {type:'roomscan_done', ok:false, error}                   失败
//
// 由 App 注入（见 jwgl_login_page.dart），防重入、可由 __zsyRoomScan.stop() 停止。
// ============================================================================

(function () {
    'use strict';

    // 防止重复注入跑两轮
    if (window.__zsyRoomScan && window.__zsyRoomScan.running) {
        window.zsyBridge.postMessage(JSON.stringify({
            type: 'roomscan_progress',
            message: '扫描已在进行中，请勿重复点击'
        }));
        return;
    }

    // ---------------------------------------------------------------- 配置

    var CLASS_FIND = 'xsbjkbcx!getFind.action';
    var CLASS_MAIN_PAGE = 'xsbjkbcx!xsbjkbMain.action';
    var CLASS_KB_DATA = 'xsbjkbcx!getKbRq.action';
    var KB_LIST_PAGE = 'xsgrkbcx!getXsgrbkList.action';

    // 年级遍历范围：当前年份-5 至当前年份（取后两位，如 2026 -> 21..26 级）
    var GRADE_OFFSET = 5;

    // 并发数：同时进行的班级课表请求数（队列上限）。
    // 教务是 HTTP/1.1：浏览器对同域只开约 6 条并发连接，超出的请求自动排队，
    // 实际同时请求约 6 个；实测全校 3500+ 班约 20 秒抓完。
    var CONCURRENCY = 100;

    // 单个请求超时（毫秒），超时视为失败并重试一次
    var REQUEST_TIMEOUT_MS = 20000;
    // 每个请求失败后的重试次数（网络抖动兜底）
    var MAX_RETRY = 1;

    // 每 50 个班回传一批 + 打一次进度
    var BATCH_SIZE = 50;

    // 教室字段为空时的占位文本（与拾光适配脚本一致）
    var UNKNOWN_POSITION = '未获取到教室';

    // ---------------------------------------------------------------- 工具

    function post(payload) {
        var text = JSON.stringify(payload);
        try {
            if (window.zsyBridge && window.zsyBridge.postMessage) {
                window.zsyBridge.postMessage(text);
                return;
            }
        } catch (e) { /* 落到控制台 */ }
        console.log('[zsy] ' + text);
    }

    function progress(message) {
        post({ type: 'roomscan_progress', message: String(message) });
    }

    function sleep(ms) {
        return new Promise(function (r) { setTimeout(r, ms); });
    }

    /** 推算教务系统站点根（WebVPN 场景会带上加密串那层）。 */
    function siteBase() {
        try {
            var u = new URL(window.location.href);
            var path = u.pathname;
            var markers = ['xsgrkbcx!', 'xsbjkbcx!'];
            for (var k = 0; k < markers.length; k++) {
                var i = path.indexOf(markers[k]);
                if (i > 0) return u.origin + path.slice(0, i);
            }
            var j = path.lastIndexOf('/');
            return u.origin + (j > 0 ? path.slice(0, j + 1) : '/');
        } catch (e) {
            var href = window.location.href.split(/[?#]/)[0];
            var m = href.lastIndexOf('/');
            return m > 0 ? href.slice(0, m + 1) : href;
        }
    }

    function readSelectOptions(doc, id) {
        var sel;
        try { sel = doc.querySelector('#' + id); } catch (e) { return null; }
        if (!sel || !sel.options) return null;
        var opts = [];
        for (var i = 0; i < sel.options.length; i++) {
            var v = String(sel.options[i].value).trim();
            if (v === '') continue;
            opts.push({
                value: v,
                text: String(sel.options[i].textContent || '').trim()
            });
        }
        if (opts.length === 0) return null;
        return { cur: String(sel.value).trim(), opts: opts };
    }

    /** 解析 getFind.action 的响应文本："xxx^getFind:[{dm, mc}, ...]"。 */
    function parseGetFind(text) {
        var marker = '^getFind:';
        var i = String(text).indexOf(marker);
        if (i < 0) return [];
        var data;
        try {
            data = JSON.parse(String(text).slice(i + marker.length));
        } catch (e) {
            return [];
        }
        var rows = Array.isArray(data) ? data
            : (data && Array.isArray(data.rows) ? data.rows : []);
        var out = [];
        for (var r = 0; r < rows.length; r++) {
            var row = rows[r];
            if (!row || typeof row !== 'object') continue;
            var value = String(row.dm || row.bjdm || '').trim();
            var text2 = String(row.mc || row.bjmc || '').trim();
            if (value) out.push({ value: value, text: text2 || value });
        }
        return out;
    }

    /** 解析压缩周次串：连续周合并为区间（"1-8,10-17"）。 */
    function packWeeks(weeks) {
        var uniq = Array.from(new Set(weeks)).filter(function (w) {
            return w > 0;
        }).sort(function (a, b) { return a - b; });
        var parts = [];
        var start = -1, prev = -1;
        for (var i = 0; i < uniq.length; i++) {
            if (start < 0) { start = prev = uniq[i]; continue; }
            if (uniq[i] === prev + 1) { prev = uniq[i]; continue; }
            parts.push(start === prev ? String(start) : start + '-' + prev);
            start = prev = uniq[i];
        }
        if (start > 0) parts.push(start === prev ? String(start) : start + '-' + prev);
        return parts.join(',');
    }

    /** 解析节次字段：jcdm2 形如 "01,02,03"；jcdm 形如 "0102"。 */
    function parseSections(jcdm2, jcdm) {
        var txt = String(jcdm2 || jcdm || '').trim();
        var nums = [];
        var push = function (n) { if (n > 0 && nums.indexOf(n) === -1) nums.push(n); };
        var raws = txt.split(/[,\s]+/);
        for (var i = 0; i < raws.length; i++) {
            var part = raws[i].trim();
            if (!part || !/^\d+$/.test(part)) continue;
            if (part.length <= 2) {
                push(parseInt(part, 10));
            } else {
                for (var k = 0; k < part.length; k += 2) {
                    push(parseInt(part.slice(k, k + 2), 10));
                }
            }
        }
        return nums.sort(function (a, b) { return a - b; });
    }

    /** 解析周次字段，兼容区间 / 逗号列表 / 位串 / 单双周后缀。 */
    function parseWeekText(zc) {
        var txt = String(zc === null || zc === undefined ? '' : zc).trim();
        if (!txt) return [];

        if (/^[01]{4,}$/.test(txt)) {
            var bits = [];
            for (var b = 0; b < txt.length; b++) {
                if (txt[b] === '1') bits.push(b + 1);
            }
            return bits;
        }

        var cleaned = txt
            .replace(/周|星期/g, '')
            .replace(/[（(][^）)]*[）)]/g, '')
            .replace(/[单双]/g, '');
        var out = [];
        var tokens = cleaned.split(/[,，\s]+/);
        for (var t = 0; t < tokens.length; t++) {
            var part = tokens[t].trim();
            if (!part) continue;
            var range = /^(\d+)\s*-\s*(\d+)$/.exec(part);
            if (range) {
                var a = parseInt(range[1], 10);
                var b2 = parseInt(range[2], 10);
                if (a > 0 && b2 >= a) {
                    for (var w = a; w <= b2; w++) out.push(w);
                }
                continue;
            }
            if (/^\d+$/.test(part)) {
                var n = parseInt(part, 10);
                if (n > 0) out.push(n);
            }
        }
        return Array.from(new Set(out)).sort(function (x, y) { return x - y; });
    }

    /** 节次与周次合并去重（与拾光适配脚本 mergeAndDistinctCourses 同构）。 */
    function mergeAndDistinctCourses(courses) {
        if (!Array.isArray(courses) || courses.length <= 1) return courses;

        var list = courses.map(function (c) {
            return {
                name: c.name || '',
                position: c.position || '',
                day: c.day || 0,
                startSection: c.startSection || 0,
                endSection: c.endSection || 0,
                weeks: Array.isArray(c.weeks) ? c.weeks.slice().sort(function (a, b) { return a - b; }) : []
            };
        });

        list.sort(function (a, b) {
            return a.name.localeCompare(b.name) ||
                   a.position.localeCompare(b.position) ||
                   (a.day || 0) - (b.day || 0) ||
                   a.weeks.join(',').localeCompare(b.weeks.join(',')) ||
                   (a.startSection || 0) - (b.startSection || 0);
        });

        var step1Merged = [];
        var current = list[0];

        for (var i = 1; i < list.length; i++) {
            var next = list[i];
            var isSameCourseAndWeeks =
                current.name === next.name &&
                current.position === next.position &&
                current.day === next.day &&
                current.weeks.join(',') === next.weeks.join(',');
            var isContinuous = current.endSection + 1 === next.startSection;
            var isDuplicate = current.startSection === next.startSection &&
                current.endSection === next.endSection;

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
                   a.position.localeCompare(b.position) ||
                   (a.day || 0) - (b.day || 0) ||
                   (a.startSection || 0) - (b.startSection || 0) ||
                   (a.endSection || 0) - (b.endSection || 0);
        });

        var step2Merged = [];
        var cur = step1Merged[0];

        for (var u = 1; u < step1Merged.length; u++) {
            var nxt = step1Merged[u];
            var isSameCourseAndSection =
                cur.name === nxt.name &&
                cur.position === nxt.position &&
                cur.day === nxt.day &&
                cur.startSection === nxt.startSection &&
                cur.endSection === nxt.endSection;

            if (isSameCourseAndSection) {
                var merged = cur.weeks.concat(nxt.weeks);
                cur.weeks = Array.from(new Set(merged)).sort(function (a, b) { return a - b; });
            } else {
                step2Merged.push(cur);
                cur = nxt;
            }
        }
        step2Merged.push(cur);

        return step2Merged;
    }

    /**
     * 解析单个班级的整学期排课记录（与拾光 collectCourses 同构）。
     * position 按教务系统原文读出（「第一教学楼」在系统里登记为「1号教学楼」）。
     */
    function collectClassCourses(records) {
        var courses = [];

        for (var i = 0; i < records.length; i++) {
            var c = records[i];
            if (!c || typeof c !== 'object') continue;

            var day = parseInt(c.xq, 10);
            if (!Number.isInteger(day) || day < 1 || day > 7) continue;

            var name = String(c.kcmc || '').trim();
            if (!name) continue;

            var sections = parseSections(c.jcdm2, c.jcdm);
            if (sections.length === 0) continue;

            var weeks = parseWeekText(c.zc);
            if (weeks.length === 0) continue;

            var position = String(c.jxcdmc || '').trim();
            // 没有教室信息的排课对空教室判定无用，跳过（减小回传体积）
            if (!position || position === UNKNOWN_POSITION) continue;

            var startSection = sections[0];
            var endSection = sections[sections.length - 1];

            var exist = null;
            for (var e = 0; e < courses.length; e++) {
                var x = courses[e];
                if (x.name === name && x.position === position &&
                    x.day === day && x.startSection === startSection &&
                    x.endSection === endSection) {
                    exist = x;
                    break;
                }
            }
            if (exist) {
                var union = exist.weeks.concat(weeks);
                exist.weeks = Array.from(new Set(union)).sort(function (a, b) { return a - b; });
            } else {
                courses.push({
                    name: name,
                    position: position,
                    day: day,
                    startSection: startSection,
                    endSection: endSection,
                    weeks: weeks
                });
            }
        }

        var totalWeeks = courses.reduce(function (max, c2) {
            return c2.weeks.reduce(function (m, w) { return w > m ? w : m; }, max);
        }, 0);

        return { courses: mergeAndDistinctCourses(courses), totalWeeks: totalWeeks };
    }

    /**
     * 从班级名称/代码推断入学年级（后两位，如 "21"）。
     * ZQU 班级名实测形如 "2026级法学1班"、"22级碳中和理科班"，两种写法均已覆盖。
     */
    function gradeOf(text, code, gradeSet) {
        var t = String(text || '');
        var m = /20(\d{2})\s*级/.exec(t);
        if (m && gradeSet[m[1]]) return m[1];
        m = /(\d{2})\s*级/.exec(t);
        if (m && gradeSet[m[1]]) return m[1];
        m = /20(\d{2})/.exec(String(code || ''));
        if (m && gradeSet[m[1]]) return m[1];
        return null;
    }

    /** 简单字符串哈希（djb2），识别「不同班级返回了同一份课表」的异常。 */
    function strHash(s) {
        var h = 5381;
        for (var i = 0; i < s.length; i++) h = ((h << 5) + h + s.charCodeAt(i)) >>> 0;
        return h.toString(16);
    }

    /** 带超时的 fetch（AbortController），超时抛错由上层重试。 */
    function fetchWithTimeout(url, options) {
        var ctrl = new AbortController();
        var timer = setTimeout(function () { ctrl.abort(); }, REQUEST_TIMEOUT_MS);
        return fetch(url, Object.assign({}, options, { signal: ctrl.signal }))
            .finally(function () { clearTimeout(timer); });
    }

    // ---------------------------------------------------------------- 数据获取

    /** 读取学期下拉框（与拾光适配脚本相同）。 */
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
     * 一次性获取全校班级列表。
     * guid=zydm 且院系/专业/入学年份全部留空时返回全校全部班级；
     * 失败时退回「按院系级联枚举」。
     */
    async function fetchAllClasses(base, termCode) {
        var body = 'guid=zydm&xnxqdm=' + encodeURIComponent(termCode) +
            '&xqdm=&rxnf=&xsyxdm=&zydm=';

        try {
            var resp = await fetch(base + CLASS_FIND, {
                method: 'POST',
                credentials: 'include',
                headers: {
                    'Content-Type': 'application/x-www-form-urlencoded',
                    'X-Requested-With': 'XMLHttpRequest'
                },
                body: body
            });
            if (resp.ok) {
                var classes = parseGetFind(await resp.text());
                if (classes.length > 0) {
                    return { classes: classes, source: '全校一次获取' };
                }
            }
        } catch (e) { /* 落到兜底 */ }

        progress('一次获取失败，退回按院系级联枚举 ...');
        return await fetchAllClassesByCascade(base, termCode);
    }

    /** 兜底：抓班级课表主页的院系下拉框，按「院系 -> 专业 -> 班级」逐级 getFind 枚举。 */
    async function fetchAllClassesByCascade(base, termCode) {
        var resp = await fetch(base + CLASS_MAIN_PAGE, { method: 'GET', credentials: 'include' });
        if (!resp.ok) throw new Error('班级课表主页请求失败（HTTP ' + resp.status + '）');

        var doc = new DOMParser().parseFromString(await resp.text(), 'text/html');
        var yxSel = readSelectOptions(doc, 'xsyxdm');
        if (!yxSel || yxSel.opts.length === 0) {
            throw new Error('兜底级联失败：主页未找到院系下拉框 #xsyxdm');
        }

        async function find(params) {
            var body = 'guid=' + params.guid +
                '&xnxqdm=' + encodeURIComponent(termCode) +
                '&xqdm=&rxnf=' + (params.rxnf || '') +
                '&xsyxdm=' + (params.xsyxdm || '') +
                '&zydm=' + (params.zydm || '');
            var r = await fetch(base + CLASS_FIND, {
                method: 'POST',
                credentials: 'include',
                headers: {
                    'Content-Type': 'application/x-www-form-urlencoded',
                    'X-Requested-With': 'XMLHttpRequest'
                },
                body: body
            });
            return parseGetFind(await r.text());
        }

        var seen = {};
        var out = [];
        for (var i = 0; i < yxSel.opts.length; i++) {
            if (stopped()) break;
            var yx = yxSel.opts[i];
            var zyList = await find({ guid: 'xsyxdm', xsyxdm: yx.value });
            await sleep(150);
            for (var z = 0; z < zyList.length; z++) {
                var bjList = await find({
                    guid: 'zydm', xsyxdm: yx.value, zydm: zyList[z].value
                });
                await sleep(80);
                for (var b = 0; b < bjList.length; b++) {
                    var bj = bjList[b];
                    if (seen[bj.value]) continue;
                    seen[bj.value] = true;
                    out.push(bj);
                }
            }
            progress('级联进度：' + yx.text + ' -> 累计 ' + out.length + ' 个班级');
        }
        if (out.length === 0) {
            throw new Error('兜底级联未取得任何班级（若尚未登录教务系统，请先登录后重试）');
        }
        return { classes: out, source: '按院系级联枚举' };
    }

    /** 请求某个班级整学期的课表原始数据（一次请求，zc 空=整学期）。 */
    async function fetchClassKbRaw(base, termCode, bjdm) {
        var url = base + CLASS_KB_DATA +
            '?xnxqdm=' + encodeURIComponent(termCode) +
            '&zc=' +
            '&xsdm=' +
            '&bjdm=' + encodeURIComponent(bjdm);

        var resp = await fetchWithTimeout(url, {
            method: 'GET',
            credentials: 'include',
            headers: { 'X-Requested-With': 'XMLHttpRequest' }
        });
        if (!resp.ok) return { records: null, raw: '' };

        var text = await resp.text();
        var data;
        try {
            data = JSON.parse(text);
        } catch (e) {
            return { records: null, raw: text };
        }
        if (!Array.isArray(data) || data.length < 2) return { records: null, raw: text };
        return { records: Array.isArray(data[0]) ? data[0] : [], raw: text };
    }

    /** 请求第 1 周的课表，取周一日期作为学期开始日期。 */
    async function fetchFirstWeekStart(base, termCode, bjdm) {
        var url = base + CLASS_KB_DATA +
            '?xnxqdm=' + encodeURIComponent(termCode) +
            '&zc=1&xsdm=' +
            '&bjdm=' + encodeURIComponent(bjdm);

        try {
            var resp = await fetch(url, {
                method: 'GET',
                credentials: 'include',
                headers: { 'X-Requested-With': 'XMLHttpRequest' }
            });
            if (!resp.ok) return null;

            var data = JSON.parse(await resp.text());
            if (!Array.isArray(data) || data.length < 2) return null;

            var dates = data[1] || [];
            for (var i = 0; i < dates.length; i++) {
                var d = dates[i];
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

    // ---------------------------------------------------------------- 主流程

    var state = { running: true, stopRequested: false };
    window.__zsyRoomScan = {
        running: true,
        stop: function () { state.stopRequested = true; }
    };

    function stopped() { return state.stopRequested; }

    function finish() {
        state.running = false;
        if (window.__zsyRoomScan) window.__zsyRoomScan.running = false;
    }

    async function run() {
        var t0 = Date.now();
        var base = siteBase();

        // 1. 学期列表（取当前学期）
        progress('正在读取学期列表 ...');
        var termCode, termName;
        try {
            var terms = await fetchTermOptions(base);
            termCode = terms.cur;
            termName = '';
            for (var ti = 0; ti < terms.opts.length; ti++) {
                if (terms.opts[ti].value === termCode) termName = terms.opts[ti].text;
            }
            if (!termCode) {
                var withValue = terms.opts.filter(function (o) { return o.value; });
                if (withValue.length === 0) throw new Error('学期下拉框为空');
                termCode = withValue[withValue.length - 1].value;
                termName = withValue[withValue.length - 1].text;
            }
        } catch (e) {
            finish();
            post({ type: 'roomscan_done', ok: false, error: '读取学期失败：' + e.message });
            return;
        }

        // 2. 全校班级列表（一次请求；失败退回级联枚举）
        progress('正在获取全校班级列表 ...');
        var classInfo;
        try {
            classInfo = await fetchAllClasses(base, termCode);
        } catch (e) {
            finish();
            post({ type: 'roomscan_done', ok: false, error: '班级列表获取失败：' + e.message });
            return;
        }

        // 3. 年级过滤：当前年份-5 至当前年份
        var nowYear = new Date().getFullYear();
        var gradeFromYear = nowYear - GRADE_OFFSET;
        var gradeToYear = nowYear;
        var grades = [];
        var gradeSet = {};
        for (var y = gradeFromYear; y <= gradeToYear; y++) {
            var g2 = String(y % 100).padStart(2, '0');
            grades.push(g2);
            gradeSet[g2] = true;
        }

        var picked = [];
        for (var c = 0; c < classInfo.classes.length; c++) {
            var item = classInfo.classes[c];
            var g = gradeOf(item.text, item.value, gradeSet);
            if (g) picked.push({ value: item.value, text: item.text, grade: g });
        }
        progress('共 ' + classInfo.classes.length + ' 个班级（' + classInfo.source +
            '），目标年级 ' + grades.join('/') + ' 级过滤后剩 ' + picked.length +
            ' 个，开始抓取课表 ...');

        if (picked.length === 0) {
            finish();
            post({
                type: 'roomscan_done', ok: false,
                error: '过滤后没有班级可扫描（年级 ' + grades.join('/') + ' 级）。'
            });
            return;
        }

        // 4. 学期开始日期（用第一个班级取第 1 周周一）
        var semesterStartDate = await fetchFirstWeekStart(base, termCode, picked[0].value);

        // 5. 并发抓取（worker 池共享任务队列；浏览器 HTTP/1.1 同域约 6 条并发）
        var total = picked.length;
        var results = new Array(total).fill(null);
        var failed = [];
        var hashCount = {};
        var doneCount = 0;
        var nextIdx = 0;

        // 分批回传的累积区
        var batchClasses = [];
        var batchLessons = [];

        function flushBatch(force) {
            if (batchClasses.length === 0) return;
            if (!force && batchClasses.length < BATCH_SIZE) return;
            post({
                type: 'roomscan_batch',
                classes: batchClasses,
                lessons: batchLessons
            });
            batchClasses = [];
            batchLessons = [];
        }

        async function worker() {
            while (!stopped()) {
                var idx = nextIdx++;
                if (idx >= total) return;
                var cls = picked[idx];
                var label = cls.text || cls.value;

                var records = null;
                var raw = '';
                var lastErr = null;
                for (var attempt = 0; attempt <= MAX_RETRY; attempt++) {
                    try {
                        var r = await fetchClassKbRaw(base, termCode, cls.value);
                        records = r.records;
                        raw = r.raw;
                        lastErr = null;
                        break;
                    } catch (e) {
                        lastErr = e;
                        await sleep(500);
                    }
                }

                var classIdx = batchClasses.length;
                var entry = {
                    dm: cls.value,
                    mc: label,
                    nf: 2000 + parseInt(cls.grade, 10)
                };

                if (lastErr) {
                    failed.push({ bjdm: cls.value, name: label, reason: '请求异常: ' + lastErr.message });
                } else if (records === null) {
                    failed.push({ bjdm: cls.value, name: label, reason: '接口未返回有效数据' });
                } else {
                    try {
                        var parsed = collectClassCourses(records);
                        entry.lessons = parsed.courses.length;
                        results[idx] = entry;

                        for (var li = 0; li < parsed.courses.length; li++) {
                            var L = parsed.courses[li];
                            batchLessons.push({
                                c: classIdx,
                                d: L.day,
                                s: L.startSection,
                                e: L.endSection,
                                w: packWeeks(L.weeks),
                                p: L.position,
                                n: L.name
                            });
                        }
                        batchClasses.push(entry);

                        // 异常检测：不同班级返回同一份课表（bjdm 参数未生效）。
                        // 只统计课程数 >= 3 的班级，避免无课班级/新生班误报。
                        if (records.length >= 3) {
                            var h = strHash(raw);
                            hashCount[h] = (hashCount[h] || 0) + 1;
                        }
                    } catch (parseErr) {
                        failed.push({
                            bjdm: cls.value,
                            name: label,
                            reason: '解析异常: ' + (parseErr && parseErr.message || parseErr)
                        });
                    }
                }

                doneCount++;
                if (doneCount % BATCH_SIZE === 0 || doneCount === total) {
                    flushBatch(false);
                    progress('进度 ' + doneCount + '/' + total + '（失败 ' + failed.length + '）');
                }
            }
        }

        var workerCount = Math.min(CONCURRENCY, total);
        var workers = [];
        for (var w = 0; w < workerCount; w++) workers.push(worker());
        await Promise.all(workers);
        flushBatch(true); // 收尾：把不足一批的余量发出去

        if (stopped()) {
            finish();
            post({ type: 'roomscan_done', ok: false, error: '已取消扫描' });
            return;
        }

        // 6. 汇总
        var dupHash = null;
        for (var key in hashCount) {
            if (hashCount[key] >= 3) { dupHash = key; break; }
        }
        var lessonTotal = 0;
        var withCourses = 0;
        for (var ri = 0; ri < results.length; ri++) {
            if (results[ri] && results[ri].lessons > 0) {
                lessonTotal += results[ri].lessons;
                withCourses++;
            }
        }

        finish();
        post({
            type: 'roomscan_done',
            ok: true,
            term: termCode,
            termName: termName,
            semesterStartDate: semesterStartDate || '',
            gradeFrom: gradeFromYear,
            gradeTo: gradeToYear,
            classCount: doneCount,
            lessonCount: lessonTotal,
            elapsedSec: Math.round((Date.now() - t0) / 1000),
            diag: {
                source: classInfo.source,
                discovered: classInfo.classes.length,
                withCourses: withCourses,
                emptyClasses: doneCount - withCourses,
                failedCount: failed.length,
                failedSample: failed.slice(0, 10),
                duplicateWarning: dupHash
                    ? '存在 ' + hashCount[dupHash] + ' 个班级返回完全相同的课表数据，请人工核对。'
                    : ''
            }
        });
    }

    run().catch(function (e) {
        finish();
        post({
            type: 'roomscan_done',
            ok: false,
            error: '扫描脚本异常：' + ((e && e.message) || e || '未知错误')
        });
    });
})();
