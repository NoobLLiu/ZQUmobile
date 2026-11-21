// ============================================================================
// 班级课表扫描脚本（空教室功能的数据采集端）。
//
// 数据来源（教务系统「班级课表」模块，需已登录）：
//   页面    GET  xsbjkbcx!xsbjkbMain.action            学期/院系下拉框
//   级联    POST xsbjkbcx!getFind.action               院系→专业→班级
//   课表    GET  xsbjkbcx!xskbList.action?xnxqdm&bjdm&zc  班级课表 HTML
//
// 遍历规则：年级取 [当前年份-5, 当前年份]（如 2026 → 2021..2026）；
// 学院无专业、专业无班级属正常现象，getFind 返回 [] 直接跳过。
//
// 回传协议（经 window.zsyBridge 发给 Flutter）：
//   {type:'roomscan_progress', message}                       进度
//   {type:'roomscan_batch', classes:[...], lessons:[...]}     每个学院一批
//   {type:'roomscan_done', ok:true, term, termName, ...}      完成
//   {type:'roomscan_done', ok:false, error}                   失败
//
// batch.classes 为该学院扫到的班级数组；lessons 里的 c 字段是
// classes 数组下标。w 为压缩周次串（"1-8,10-17"）。
//
// 由 App 以 IIFE 包裹注入（见 jwgl_adapter_repository），可重复注入。
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
     * 解析周次文本，兼容 "1-8,10-17周" / "1,3,5周" / "1111111100000000"
     * 位串 / "1-16(单)" 等写法（与拾光适配脚本同一套规则）。
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
            .replace(/周|星期/g, '')
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
            // 纯数字（可能逗号分隔多天）
            var nums = s.match(/[1-7]/g) || [];
            for (var i = 0; i < nums.length; i++) {
                var n = parseInt(nums[i], 10);
                if (out.indexOf(n) === -1) out.push(n);
            }
        }
        return out.sort(function (x, y) { return x - y; });
    }

    // ---------------------------------------------------------------- 数据获取

    function fetchDoc(url) {
        return fetch(url, { method: 'GET', credentials: 'include' })
            .then(function (resp) {
                if (!resp.ok) throw new Error('HTTP ' + resp.status);
                return resp.text();
            })
            .then(function (html) {
                return new DOMParser().parseFromString(html, 'text/html');
            });
    }

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

    /**
     * 从班级课表 HTML 中解析「上课信息」列表。
     *
     * 列头按文本匹配列含义；缺星期/节次列时退化为「整天占用」
     * （d=0、s=1..e=14），由 App 端按保守策略处理。
     *
     * @returns {{lessons: Array, coarse: number, rows: number}}
     *   lessons: {d,s,e,w(压缩串),p(地点),n(课程名)}
     */
    function parseClassTimetable(html, fallbackWeek) {
        var doc = new DOMParser().parseFromString(html, 'text/html');
        var tables = doc.querySelectorAll('table');
        var best = null;
        var bestScore = 0;

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
            // 认定是列表的最低标准：有地点列 + 至少还有一个其他关键列
            if (cols.position === undefined || score < 4) continue;
            if (score > bestScore) { bestScore = score; best = { cols: cols, table: tb }; }
        }

        if (!best) return { lessons: [], coarse: 0, rows: 0, reason: 'no-table' };

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
        return { lessons: uniq, coarse: coarse, rows: rows.length - 1 };
    }

    async function fetchClassTimetable(base, termCode, classCode) {
        var url = base + KB_API +
            '?xnxqdm=' + encodeURIComponent(termCode) +
            '&bjdm=' + encodeURIComponent(classCode) +
            '&zc=1';
        var resp = await fetch(url, { method: 'GET', credentials: 'include' });
        if (!resp.ok) throw new Error('课表请求 HTTP ' + resp.status);
        return parseClassTimetable(await resp.text(), 1);
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

        // 1. 班级课表页面：取学期与院系下拉
        progress('正在打开班级课表页面 ...');
        var doc;
        try {
            doc = await fetchDoc(base + MAIN_PAGE);
        } catch (e) {
            finish();
            post({ type: 'roomscan_done', ok: false, error: '无法打开班级课表页：' + e.message });
            return;
        }

        var termSel = readSelectOptions(doc, 'xnxqdm');
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
            // 兜底：取最后一个选项（通常是最新的学期）
            var withValue = termSel.opts.filter(function (o) { return o.value; });
            if (withValue.length === 0) {
                finish();
                post({ type: 'roomscan_done', ok: false, error: '学期下拉框为空，请确认已登录教务系统' });
                return;
            }
            termCode = withValue[withValue.length - 1].value;
            termName = withValue[withValue.length - 1].text;
        }

        var collegeSel = readSelectOptions(doc, 'xsyxdm');
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

        // 3. 遍历：院系 → 专业 → 年级 → 班级 → 课表
        var totalClasses = 0;
        var totalLessons = 0;
        var totalCoarse = 0;
        var missStreak = 0;
        var badClasses = 0;

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

                    for (var ki = 0; ki < classes.length; ki++) {
                        if (stopped()) break;
                        var cls = classes[ki];
                        var classIdx = batchClasses.length;
                        batchClasses.push({
                            dm: String(cls.dm).trim(),
                            mc: String(cls.mc || '').trim(),
                            zy: String(major.dm).trim(),
                            zymc: majorName,
                            nf: grade
                        });

                        try {
                            var parsed = await fetchClassTimetable(base, termCode, String(cls.dm).trim());
                            if (parsed.reason === 'no-table') badClasses++;
                            for (var li = 0; li < parsed.lessons.length; li++) {
                                var L = parsed.lessons[li];
                                L.c = classIdx;
                                batchLessons.push(L);
                            }
                            totalCoarse += parsed.coarse;
                        } catch (e) {
                            badClasses++;
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
            badClassCount: badClasses,
            elapsedSec: Math.round((Date.now() - t0) / 1000)
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
