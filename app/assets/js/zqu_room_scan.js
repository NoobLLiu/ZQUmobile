// ============================================================================
// 班级课表扫描脚本（空教室功能的数据采集端）v2。
//
// 数据来源（教务系统「班级课表」模块，需已登录）：
//   页面    GET  xsbjkbcx!xsbjkbMain.action            筛选表单 + 课表 iframe
//   级联    POST xsbjkbcx!getFind.action               院系→专业→班级
//   课表    GET  xsbjkbcx!xskbList.action?xnxqdm&bjdm&zc  班级课表 HTML
//
// 取课表的两条路（自动择优）：
//   A 直连模式：从班级课表页面上下文直接 GET xskbList（与手动查询的
//     Referer/会话一致），解析响应 HTML。速度最快，每班一个请求。
//   B 页面模式：直连探测失败时退化为模拟操作 —— 在班级课表页上依次
//     设置 院系/专业/年级/班级 下拉并触发查询，等课表 iframe 刷出后
//     直接读 iframe 里的 DOM。同院系+专业+年级只切一次级联，逐班只
//     换班级下拉 + 点查询。
//
// 遍历规则：年级取 [当前年份-5, 当前年份]（如 2026 → 2021..2026）；
// 学院无专业、专业无班级属正常现象，getFind 返回 [] 直接跳过。
//
// 回传协议（经 window.zsyBridge 发给 Flutter）：
//   {type:'roomscan_progress', message}                       进度
//   {type:'roomscan_batch', classes:[...], lessons:[...]}     每个学院一批
//   {type:'roomscan_done', ok:true, term, ..., diag:{...}}    完成（带诊断）
//   {type:'roomscan_done', ok:false, error}                   失败
//
// 由 App 在页面加载完成后注入（见 jwgl_login_page.dart），可重复注入。
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

    // ---------------------------------------------------------------- 常量

    var MAIN_PAGE = 'xsbjkbcx!xsbjkbMain.action';
    var FIND_API = 'xsbjkbcx!getFind.action';
    var KB_API = 'xsbjkbcx!xskbList.action';

    // 请求间的小间隔，避免给教务服务器造成压力
    var GAP_MS = 30;
    // 连续解析失败的级联请求上限（超过视为会话失效）
    var MAX_CASCADE_MISS = 3;
    // 跳转进班级课表页的最大尝试次数（sessionStorage 计数，防死循环）
    var MAX_NAV_ATTEMPTS = 3;
    // 直连探测的班级数：前几个班都取不到课表才切页面模式
    var PROBE_COUNT = 3;

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

    /** 轮询等待条件成立；超时返回 null。 */
    async function waitFor(fn, timeoutMs, stepMs) {
        var t0 = Date.now();
        while (Date.now() - t0 < timeoutMs) {
            if (stopped()) return null;
            var ok = false;
            try { ok = fn(); } catch (e) { ok = false; }
            if (ok) return true;
            await sleep(stepMs || 200);
        }
        return null;
    }

    /**
     * 推算教务系统站点根。
     * 校内：https://jwgl.zqu.edu.cn/xsbjkbcx!... → origin + '/'
     * WebVPN：https://webvpn.zqu.edu.cn/https/<加密串>/xsbjkbcx!... → 带加密串的根
     */
    function siteBase() {
        var href = String(window.location.href);
        try {
            var u = new URL(href);
            var path = u.pathname;
            var markers = ['xsbjkbcx!', 'xsgrkbcx!'];
            for (var k = 0; k < markers.length; k++) {
                var i = path.indexOf(markers[k]);
                if (i > 0) return u.origin + path.slice(0, i);
            }
            var j = path.lastIndexOf('/');
            return u.origin + (j > 0 ? path.slice(0, j + 1) : '/');
        } catch (e) {
            var plain = href.split(/[?#]/)[0];
            var m = plain.lastIndexOf('/');
            return m > 0 ? plain.slice(0, m + 1) : plain;
        }
    }

    function readSelectOptions(doc, id) {
        var sel;
        try { sel = doc.querySelector('#' + id); } catch (e) { return null; }
        if (!sel || !sel.options) return null;
        var opts = [];
        for (var i = 0; i < sel.options.length; i++) {
            var v = String(sel.options[i].value).trim();
            opts.push({
                value: v,
                text: String(sel.options[i].textContent || '').trim()
            });
        }
        return { cur: String(sel.value).trim(), opts: opts };
    }

    /** 解析压缩周次串：连续周合并为区间。 */
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

    /**
     * 解析周次文本，兼容 "1-8,10-17周" / "第1-16周" / "1,3,5周" /
     * "1111111100000000" 位串 / "1-16(单)" 等写法。
     */
    function parseWeekText(zc) {
        var txt = String(zc === null || zc === undefined ? '' : zc).trim();
        if (!txt) return [];
        if (/^[01]{4,}$/.test(txt)) {
            var bits = [];
            for (var i = 0; i < txt.length; i++) {
                if (txt[i] === '1') bits.push(i + 1);
            }
            return bits;
        }
        var cleaned = txt
            .replace(/第|周|星期/g, '')
            .replace(/[（(][^）)]*[）)]/g, '')
            .replace(/[单双]/g, '');
        var out = [];
        var tokens = cleaned.split(/[,，\s]+/);
        for (var t = 0; t < tokens.length; t++) {
            var part = tokens[t].trim();
            if (!part) continue;
            var range = /^(\d+)\s*[-~～]\s*(\d+)$/.exec(part);
            if (range) {
                var a = parseInt(range[1], 10), b = parseInt(range[2], 10);
                if (a > 0 && b >= a) for (var w = a; w <= b; w++) out.push(w);
                continue;
            }
            if (/^\d+$/.test(part)) {
                var n = parseInt(part, 10);
                if (n > 0) out.push(n);
            }
        }
        return Array.from(new Set(out)).sort(function (x, y) { return x - y; });
    }

    /** 解析节次文本："01,02" / "0102" / "1-2节" / "第3节" 等。 */
    function parseSectionsText(txt) {
        var raw = String(txt || '').trim();
        if (!raw) return [];
        var cleaned = raw.replace(/第/g, '').replace(/节/g, ' ');
        var nums = [];
        var push = function (n) {
            if (n > 0 && n <= 30 && nums.indexOf(n) === -1) nums.push(n);
        };
        var tokens = cleaned.split(/[,，、\s/]+/);
        for (var i = 0; i < tokens.length; i++) {
            var part = tokens[i].trim();
            if (!part) continue;
            var range = /^(\d{1,2})\s*[-~～]\s*(\d{1,2})$/.exec(part);
            if (range) {
                var a = parseInt(range[1], 10), b = parseInt(range[2], 10);
                if (a > 0 && b >= a) for (var s = a; s <= b; s++) push(s);
                continue;
            }
            if (/^\d+$/.test(part)) {
                if (part.length > 2) {
                    // "0102" 连写：按两位一组拆开
                    for (var k = 0; k < part.length; k += 2) {
                        push(parseInt(part.slice(k, k + 2), 10));
                    }
                } else {
                    push(parseInt(part, 10));
                }
            }
        }
        return nums.sort(function (x, y) { return x - y; });
    }

    /** 解析星期文本："星期一" / "周一" / "一" / "1"。 */
    function parseDayText(txt) {
        var s = String(txt || '').trim();
        if (!s) return [];
        var map = { '一': 1, '二': 2, '三': 3, '四': 4, '五': 5, '六': 6, '日': 7, '天': 7 };
        var out = [];
        var re = /[星期周]*\s*([一二三四五六日天])/g;
        var m;
        while ((m = re.exec(s)) !== null) {
            var d = map[m[1]];
            if (d && out.indexOf(d) === -1) out.push(d);
        }
        if (out.length === 0) {
            var nums = s.match(/[1-7]/g) || [];
            for (var i = 0; i < nums.length; i++) {
                var n = parseInt(nums[i], 10);
                if (out.indexOf(n) === -1) out.push(n);
            }
        }
        return out.sort(function (x, y) { return x - y; });
    }

    // ---------------------------------------------------------------- 解析

    /**
     * 从课表文档（HTML 字符串解析结果或 iframe contentDocument）中
     * 解析「上课信息」列表。
     *
     * 列头按文本匹配列含义；缺星期/节次列时退化为「整天占用」
     * （d=0、s=1..e=14），由 App 端按保守策略处理。
     *
     * @returns {{lessons: Array, coarse: number, rows: number,
     *            headers: Array, reason: string}}
     */
    function parseTimetableDoc(doc, requestedWeek) {
        var tables = doc.querySelectorAll('table');
        var best = null;
        var bestScore = 0;
        var firstHeaders = [];

        for (var t = 0; t < tables.length; t++) {
            var tb = tables[t];
            var headCells = tb.querySelectorAll('thead th');
            if (headCells.length === 0) {
                var firstRow = tb.querySelector('tr');
                if (firstRow) headCells = firstRow.querySelectorAll('th,td');
            }
            if (headCells.length < 3) continue;

            var heads = [];
            for (var h = 0; h < headCells.length; h++) {
                heads.push(String(headCells[h].textContent || '').trim());
            }
            if (firstHeaders.length === 0) firstHeaders = heads.slice(0, 12);

            var score = 0;
            var cols = {};
            for (var i = 0; i < heads.length; i++) {
                var txt = heads[i];
                if (!txt) continue;
                if (txt.indexOf('星期') !== -1) { cols.day = i; score += 2; }
                else if (txt.indexOf('周次') !== -1) { cols.weeks = i; score += 2; }
                else if (txt.indexOf('节次') !== -1 ||
                         (txt.indexOf('节') !== -1 && txt.indexOf('周') === -1)) {
                    cols.sections = i; score += 2;
                }
                else if (txt.indexOf('地点') !== -1 || txt.indexOf('场所') !== -1 ||
                         (txt.indexOf('教室') !== -1 && txt.indexOf('名称') === -1)) {
                    cols.position = i; score += 2;
                }
                else if (txt.indexOf('教师') !== -1) { cols.teacher = i; score += 1; }
                else if (txt.indexOf('课程') !== -1) { cols.name = i; score += 1; }
            }
            // 认定是上课列表的最低标准：有地点列 + 至少还有一个其他关键列
            if (cols.position === undefined || score < 4) continue;
            if (score > bestScore) { bestScore = score; best = { cols: cols, table: tb }; }
        }

        if (!best) {
            return {
                lessons: [], coarse: 0, rows: tables.length,
                headers: firstHeaders, reason: 'no-table'
            };
        }

        var cols = best.cols;
        var rows = best.table.querySelectorAll('tr');
        var lessons = [];
        var coarse = 0;

        for (var r = 1; r < rows.length; r++) {
            var cells = rows[r].querySelectorAll('td,th');
            if (cells.length < 3) continue;
            var get = function (idx) {
                return idx !== undefined && idx < cells.length
                    ? String(cells[idx].textContent || '').trim() : '';
            };

            var position = get(cols.position);
            if (!position) continue;
            var name = get(cols.name);
            var weeks = parseWeekText(get(cols.weeks));

            var days = parseDayText(get(cols.day));
            var sections = parseSectionsText(get(cols.sections));

            var coarseRow = false;
            if (days.length === 0 || sections.length === 0) {
                // 列表缺星期/节次列：退化为整天占用（保守策略）
                coarseRow = true;
                coarse++;
                if (days.length === 0) days = [0]; // 0 = 任意星期
                if (sections.length === 0) sections = [1, 14];
            }
            if (weeks.length === 0) {
                if (!coarseRow) continue; // 有周次列但解析不出 → 丢弃
                // 无周次列：按整学期占用（保守策略）
                weeks = [];
                for (var fw = 1; fw <= 25; fw++) weeks.push(fw);
            }

            for (var d = 0; d < days.length; d++) {
                lessons.push({
                    d: days[d],
                    s: sections[0],
                    e: sections[sections.length - 1],
                    w: packWeeks(weeks),
                    p: position,
                    n: name,
                    coarse: coarseRow
                });
            }
        }

        // 同键去重（同课同段同地点多行）
        var seen = {};
        var uniq = [];
        for (var u = 0; u < lessons.length; u++) {
            var L = lessons[u];
            var key = L.d + '|' + L.s + '|' + L.e + '|' + L.w + '|' + L.p + '|' + L.n;
            if (seen[key]) continue;
            seen[key] = true;
            uniq.push(L);
        }
        return {
            lessons: uniq, coarse: coarse, rows: rows.length - 1,
            headers: firstHeaders, reason: uniq.length > 0 ? 'ok' : 'no-rows'
        };
    }

    function parseClassTimetable(html, requestedWeek) {
        var doc = new DOMParser().parseFromString(html, 'text/html');
        return parseTimetableDoc(doc, requestedWeek);
    }

    // ---------------------------------------------------------------- 直连模式

    /**
     * 级联查询接口。返回 [{dm, mc}, ...]，空组合返回 []。
     * 响应体形如 "<guid>^getFind:[...]"，未登录时返回 HTML。
     */
    async function getFind(base, termCode, guid, xsyxdm, zydm, rxnf) {
        var body = new URLSearchParams({
            guid: guid,
            xnxqdm: termCode,
            xqdm: '',
            rxnf: rxnf || '',
            xsyxdm: xsyxdm || '',
            zydm: zydm || ''
        }).toString();
        var resp = await fetch(base + FIND_API, {
            method: 'POST',
            credentials: 'include',
            headers: {
                'Content-Type': 'application/x-www-form-urlencoded',
                'X-Requested-With': 'XMLHttpRequest'
            },
            body: body
        });
        if (!resp.ok) throw new Error('级联查询 HTTP ' + resp.status);
        var text = await resp.text();
        var i = text.indexOf('^getFind:');
        if (i < 0) return null; // 不是级联响应（多为登录页 HTML）
        var arr = JSON.parse(text.slice(i + 9));
        if (!Array.isArray(arr)) return [];
        return arr.filter(function (x) {
            return x && x.dm !== undefined && String(x.dm).trim() !== '';
        });
    }

    /** 直连请求某班的课表 HTML 并解析。 */
    async function fetchClassTimetable(base, termCode, classCode) {
        var url = base + KB_API +
            '?xnxqdm=' + encodeURIComponent(termCode) +
            '&bjdm=' + encodeURIComponent(classCode) +
            '&zc=1';
        var resp = await fetch(url, { method: 'GET', credentials: 'include' });
        if (!resp.ok) throw new Error('课表请求 HTTP ' + resp.status);
        var html = await resp.text();
        var parsed = parseClassTimetable(html, 1);
        parsed.htmlLen = html.length;
        return parsed;
    }

    // ---------------------------------------------------------------- 页面模式

    function el(id) {
        return document.querySelector('#' + id);
    }

    function setSelect(sel, value) {
        if (!sel || !sel.options) return false;
        for (var i = 0; i < sel.options.length; i++) {
            if (String(sel.options[i].value) === String(value)) {
                sel.value = String(value);
                return true;
            }
        }
        return false;
    }

    function fireChange(sel) {
        if (!sel) return;
        try {
            sel.dispatchEvent(new Event('change', { bubbles: true }));
        } catch (e) { /* 忽略 */ }
    }

    function findQueryButton() {
        var nodes = document.querySelectorAll(
            'input[type=button],input[type=submit],button,a.btn,a');
        for (var i = 0; i < nodes.length; i++) {
            var t = String(nodes[i].value || nodes[i].textContent || '').trim();
            if (t.indexOf('查询') !== -1 || t.indexOf('查 询') !== -1) {
                return nodes[i];
            }
        }
        return null;
    }

    function findTimetableFrame() {
        var frames = document.querySelectorAll('iframe');
        for (var i = 0; i < frames.length; i++) {
            var src = String(frames[i].getAttribute('src') || '');
            if (src.indexOf('xskb') !== -1) return frames[i];
        }
        return frames.length > 0 ? frames[0] : null;
    }

    function frameSignature(frame) {
        try {
            var doc = frame.contentDocument;
            if (!doc || !doc.body) return '';
            return String(frame.src || '') + '#' + doc.body.innerText.length;
        } catch (e) {
            return '';
        }
    }

    /**
     * 页面模式取某班的课表：设置班级下拉 → 触发查询 → 等课表刷新 → 读 iframe。
     * 调用前需先用 prepareGroup 把 院系/专业/年级 级联到位。
     */
    async function queryClassViaPage(classCode) {
        var bj = el('bjdm');
        if (!bj) return { lessons: [], reason: 'no-bjdm-select', headers: [] };
        if (!setSelect(bj, classCode)) {
            return { lessons: [], reason: 'bjdm-option-missing', headers: [] };
        }

        var frame = findTimetableFrame();
        var sigBefore = frame ? frameSignature(frame) : '';

        fireChange(bj);
        var btn = findQueryButton();
        if (btn) {
            try { btn.click(); } catch (e) { /* 忽略 */ }
        }

        // 等课表刷新：签名变化，或（首次查询）出现非空内容
        await waitFor(function () {
            var f = findTimetableFrame();
            if (!f) return false;
            var sig = frameSignature(f);
            if (!sig) return false;
            return sig !== sigBefore || sigBefore === '';
        }, 15000, 300);

        await sleep(300); // 等 DOM 稳定
        var f2 = findTimetableFrame();
        if (!f2 || !f2.contentDocument || !f2.contentDocument.body) {
            return { lessons: [], reason: 'no-frame-doc', headers: [] };
        }
        var parsed = parseTimetableDoc(f2.contentDocument, 1);
        parsed.reason = parsed.lessons.length > 0 ? 'ok' : parsed.reason;
        return parsed;
    }

    /**
     * 把 院系/专业/年级 级联切到位（同一组合只切一次）。
     * 依赖页面自身的 change 处理填充下级下拉。
     */
    async function prepareGroup(xsyxdm, zydm, nf) {
        var yx = el('xsyxdm');
        if (!yx) return false;

        if (String(yx.value) !== String(xsyxdm)) {
            if (!setSelect(yx, xsyxdm)) return false;
            fireChange(yx);
            var filled = await waitFor(function () {
                var zy = el('zydm');
                return zy && Array.from(zy.options).some(function (o) {
                    return String(o.value) === String(zydm);
                });
            }, 10000, 250);
            if (!filled) return false;
        }

        var zy = el('zydm');
        if (!zy || !setSelect(zy, zydm)) return false;
        fireChange(zy);

        var nfSel = el('rxnf');
        if (nfSel) {
            if (!setSelect(nfSel, nf)) return false;
            fireChange(nfSel);
        }

        // 等班级下拉填充（页面按 yx+zy+nf 调 getFind）
        var ok = await waitFor(function () {
            var bj = el('bjdm');
            return bj && bj.options.length > 1;
        }, 8000, 250);
        return ok != null;
    }

    // ---------------------------------------------------------------- 主流程

    var state = { running: true, stopRequested: false };
    window.__zsyRoomScan = {
        running: true,
        stop: function () { state.stopRequested = true; }
    };

    function stopped() { return state.stopRequested; }

    /** 结束本轮扫描并放开重新扫描的口子。 */
    function finish() {
        state.running = false;
        if (window.__zsyRoomScan) window.__zsyRoomScan.running = false;
    }

    async function run() {
        var t0 = Date.now();
        var base = siteBase();

        // 0. 必须停在班级课表页：不在就跳过去，页面加载完成后 App 会重新注入
        if (String(window.location.href).indexOf('xsbjkbcx!') === -1) {
            var navKey = 'zsyRoomScanNav';
            var navCount = parseInt(sessionStorage.getItem(navKey) || '0', 10) + 1;
            sessionStorage.setItem(navKey, String(navCount));
            if (navCount > MAX_NAV_ATTEMPTS) {
                sessionStorage.removeItem(navKey);
                finish();
                post({
                    type: 'roomscan_done', ok: false,
                    error: '多次尝试进入班级课表页失败。请先在教务系统里打开'
                         + '「信息查询 → 班级课表」，再点扫描。'
                });
                return;
            }
            progress('正在进入班级课表页面（' + navCount + '/' + MAX_NAV_ATTEMPTS + '）...');
            window.location.href = base + MAIN_PAGE;
            return; // 跳转后脚本随页面重载，由 App 重新注入
        }
        sessionStorage.removeItem('zsyRoomScanNav');

        // 1. 从页面下拉框取学期与院系（live DOM）
        var termSel = readSelectOptions(document, 'xnxqdm');
        if (!termSel) {
            finish();
            post({ type: 'roomscan_done', ok: false, error: '未找到学期下拉框，请确认已登录教务系统' });
            return;
        }
        var termCode = termSel.cur;
        var termName = '';
        for (var ti = 0; ti < termSel.opts.length; ti++) {
            if (termSel.opts[ti].value === termCode) termName = termSel.opts[ti].text;
        }
        if (!termCode) {
            var withValue = termSel.opts.filter(function (o) { return o.value; });
            if (withValue.length === 0) {
                finish();
                post({ type: 'roomscan_done', ok: false, error: '学期下拉框为空，请确认已登录教务系统' });
                return;
            }
            termCode = withValue[withValue.length - 1].value;
            termName = withValue[withValue.length - 1].text;
        }

        var collegeSel = readSelectOptions(document, 'xsyxdm');
        if (!collegeSel) {
            finish();
            post({ type: 'roomscan_done', ok: false, error: '未找到院系下拉框，请确认页面为班级课表' });
            return;
        }
        var colleges = collegeSel.opts.filter(function (o) { return o.value !== ''; });
        if (colleges.length === 0) {
            finish();
            post({ type: 'roomscan_done', ok: false, error: '院系下拉框没有可选学院' });
            return;
        }

        // 2. 年级窗口：[当前年份-5, 当前年份]
        var nowYear = new Date().getFullYear();
        var gradeFrom = nowYear - 5;
        var gradeTo = nowYear;

        progress('学期 ' + termName + '（' + termCode + '），共 ' + colleges.length +
            ' 个学院，年级 ' + gradeFrom + '-' + gradeTo);

        // 3. 探测：用第一个班的课表决定走直连还是页面模式
        var mode = 'direct'; // direct | page
        var diag = {
            mode: '',
            probe: null,
            directOk: 0, directFail: 0,
            pageOk: 0, pageFail: 0,
            failures: []
        };

        var firstClasses = null;
        try {
            var c0 = colleges[0];
            var majors0 = await getFind(base, termCode, 'xsyxdm', c0.value, '', '');
            await sleep(GAP_MS);
            if (majors0 && majors0.length > 0) {
                for (var g0 = gradeFrom; g0 <= gradeTo && !firstClasses; g0++) {
                    var cls0 = await getFind(base, termCode, 'rxnf',
                        c0.value, String(majors0[0].dm), String(g0));
                    await sleep(GAP_MS);
                    if (cls0 && cls0.length > 0) {
                        firstClasses = { college: c0, major: majors0[0], grade: g0, list: cls0 };
                    }
                }
            }
        } catch (e) { /* 探测失败不阻塞，后面正常走 */ }

        if (firstClasses) {
            progress('正在探测课表获取方式 ...');
            try {
                var probe = await fetchClassTimetable(base, termCode,
                    String(firstClasses.list[0].dm).trim());
                diag.probe = {
                    status: 'fetched',
                    htmlLen: probe.htmlLen,
                    tables: probe.rows,
                    headers: probe.headers,
                    lessons: probe.lessons.length,
                    reason: probe.reason
                };
                mode = probe.lessons.length > 0 ? 'direct' : 'page';
            } catch (e) {
                diag.probe = { status: 'error', error: String(e && e.message || e) };
                mode = 'page';
            }
        } else {
            diag.probe = { status: 'no-class' };
        }
        diag.mode = mode;
        progress(mode === 'direct'
            ? '直连接口可用，开始全量扫描 ...'
            : '直连接口取不到课表，改用页面模式（模拟切换班级查询，速度较慢）...');

        // 4. 遍历：院系 → 专业 → 年级 → 班级 → 课表
        var totalClasses = 0;
        var totalLessons = 0;
        var totalCoarse = 0;
        var missStreak = 0;
        var uiGroup = ''; // 页面模式下当前级联位置，避免重复切换

        for (var ci = 0; ci < colleges.length; ci++) {
            if (stopped()) break;
            var college = colleges[ci];
            var collegeName = college.text || college.value;

            var majors = [];
            try {
                majors = await getFind(base, termCode, 'xsyxdm', college.value, '', '');
                missStreak = 0;
            } catch (e) {
                progress('院系 ' + collegeName + ' 查询失败：' + e.message);
                majors = [];
            }
            if (majors === null) {
                missStreak++;
                if (missStreak >= MAX_CASCADE_MISS) {
                    finish();
                    post({
                        type: 'roomscan_done', ok: false,
                        error: '级联查询连续无响应，登录会话可能已失效，请重新登录后再试'
                    });
                    return;
                }
                majors = [];
            }
            await sleep(GAP_MS);

            var batchClasses = [];
            var batchLessons = [];

            for (var mi = 0; mi < majors.length; mi++) {
                if (stopped()) break;
                var major = majors[mi];
                var majorName = String(major.mc || major.dm).trim();

                for (var grade = gradeFrom; grade <= gradeTo; grade++) {
                    if (stopped()) break;
                    var classes = [];
                    try {
                        classes = await getFind(base, termCode, 'rxnf',
                            college.value, String(major.dm), String(grade));
                        missStreak = 0;
                    } catch (e) {
                        classes = [];
                    }
                    if (classes === null) {
                        missStreak++;
                        if (missStreak >= MAX_CASCADE_MISS) {
                            finish();
                            post({
                                type: 'roomscan_done', ok: false,
                                error: '级联查询连续无响应，登录会话可能已失效，请重新登录后再试'
                            });
                            return;
                        }
                        classes = [];
                    }
                    await sleep(GAP_MS);

                    // 页面模式：同一 院系+专业+年级 只切一次级联
                    if (mode === 'page' && classes.length > 0) {
                        var groupKey = college.value + '|' + major.dm + '|' + grade;
                        if (uiGroup !== groupKey) {
                            var prepared = await prepareGroup(
                                college.value, String(major.dm), String(grade));
                            if (!prepared) {
                                diag.pageFail += classes.length;
                                for (var pf = 0; pf < classes.length; pf++) {
                                    diag.failures.push({
                                        cls: String(classes[pf].mc || classes[pf].dm),
                                        reason: 'group-not-prepared'
                                    });
                                }
                                totalClasses += classes.length;
                                continue;
                            }
                            uiGroup = groupKey;
                        }
                    }

                    for (var ki = 0; ki < classes.length; ki++) {
                        if (stopped()) break;
                        var cls = classes[ki];
                        var classCode = String(cls.dm).trim();
                        var classIdx = batchClasses.length;
                        batchClasses.push({
                            dm: classCode,
                            mc: String(cls.mc || '').trim(),
                            zy: String(major.dm).trim(),
                            zymc: majorName,
                            nf: grade
                        });

                        try {
                            var parsed = mode === 'direct'
                                ? await fetchClassTimetable(base, termCode, classCode)
                                : await queryClassViaPage(classCode);
                            if (parsed.lessons.length > 0) {
                                if (mode === 'direct') diag.directOk++;
                                else diag.pageOk++;
                                for (var li = 0; li < parsed.lessons.length; li++) {
                                    var L = parsed.lessons[li];
                                    L.c = classIdx;
                                    batchLessons.push(L);
                                }
                                totalCoarse += parsed.coarse;
                            } else {
                                if (mode === 'direct') diag.directFail++;
                                else diag.pageFail++;
                                if (diag.failures.length < 5) {
                                    diag.failures.push({
                                        cls: String(cls.mc || classCode),
                                        reason: parsed.reason,
                                        headers: parsed.headers
                                    });
                                }
                            }
                        } catch (e) {
                            if (mode === 'direct') diag.directFail++;
                            else diag.pageFail++;
                            if (diag.failures.length < 5) {
                                diag.failures.push({
                                    cls: String(cls.mc || classCode),
                                    reason: 'error:' + String(e && e.message || e)
                                });
                            }
                        }
                        totalClasses++;
                        await sleep(GAP_MS);
                    }
                }
            }

            totalLessons += batchLessons.length;
            progress('已扫描 ' + (ci + 1) + '/' + colleges.length + ' 个学院：' +
                totalClasses + ' 个班级，' + totalLessons + ' 条排课记录');

            if (batchClasses.length > 0) {
                post({
                    type: 'roomscan_batch',
                    college: collegeName,
                    classes: batchClasses,
                    lessons: batchLessons
                });
            }
            await sleep(GAP_MS);
        }

        if (stopped()) {
            finish();
            post({ type: 'roomscan_done', ok: false, error: '已取消扫描' });
            return;
        }

        finish();
        post({
            type: 'roomscan_done',
            ok: true,
            term: termCode,
            termName: termName,
            gradeFrom: gradeFrom,
            gradeTo: gradeTo,
            classCount: totalClasses,
            lessonCount: totalLessons,
            coarseCount: totalCoarse,
            elapsedSec: Math.round((Date.now() - t0) / 1000),
            diag: diag
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
