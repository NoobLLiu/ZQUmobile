/// 肇庆学院教务系统（乘方 URP 系）对接层。
///
/// 逻辑移植自拾光课表的官方适配脚本
/// `shiguang_warehouse/resources/ZQU/zqu_01.js`（Apache-2.0），
/// 去掉拾光专用的 bridge 调用，改为在 WebView 页面内执行 JS 取数后回调 Dart。
///
/// 数据来源（教务系统内部页，非 WebVPN 首页）：
///   学期列表：GET {base}xsgrkbcx!getXsgrbkList.action  → 页面里的 #xnxqdm 下拉框
///   课表数据：GET {base}xsgrkbcx!getKbRq.action?xnxqdm=<学期>&zc=<周次>&xsdm=
///     - zc 传空表示不限周次，一次可取回整学期排课记录
///     - 每条记录自带 zc 字段标明该门课的上课周次，故无需逐周请求
library;

import 'dart:convert';

/// 教务对接异常。
class JwglException implements Exception {
  JwglException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 教务对接配置。
class JwglConfig {
  const JwglConfig({
    required this.baseUrl,
    this.term,
    this.weeks,
    this.semesterStartDate,
  });

  /// 教务站点根，如 https://jwgl.zqu.edu.cn/ 或 WebVPN 加密路径。
  final String baseUrl;

  /// 学期编号，如 202601；为空则取默认（当前学期）。
  final String? term;

  /// 只取指定周次（1-based），为空表示整学期。
  final List<int>? weeks;

  /// 学期第 1 周的周一日期 "YYYY-MM-DD"。
  final String? semesterStartDate;
}

/// 一次抓取的结果。
class JwglFetchResult {
  const JwglFetchResult({
    required this.term,
    required this.termName,
    required this.totalWeeks,
    required this.semesterStartDate,
    required this.courses,
    required this.timeSlots,
  });

  final String term;
  final String termName;
  final int totalWeeks;
  final String semesterStartDate;
  final List<Map<String, dynamic>> courses;
  final List<Map<String, dynamic>> timeSlots;
}

/// 肇庆学院作息时间（每天 14 节）。
///
/// 教务系统不提供作息数据，导入时按学校实际作息表预设。
const List<Map<String, dynamic>> kPresetTimeSlots = [
  {'number': 1, 'startTime': '08:00', 'endTime': '08:40'},
  {'number': 2, 'startTime': '08:50', 'endTime': '09:30'},
  {'number': 3, 'startTime': '09:50', 'endTime': '10:30'},
  {'number': 4, 'startTime': '10:40', 'endTime': '11:20'},
  {'number': 5, 'startTime': '11:30', 'endTime': '12:10'},
  {'number': 6, 'startTime': '14:30', 'endTime': '15:10'},
  {'number': 7, 'startTime': '15:20', 'endTime': '16:00'},
  {'number': 8, 'startTime': '16:15', 'endTime': '16:55'},
  {'number': 9, 'startTime': '17:05', 'endTime': '17:45'},
  {'number': 10, 'startTime': '17:55', 'endTime': '18:35'},
  {'number': 11, 'startTime': '19:00', 'endTime': '19:40'},
  {'number': 12, 'startTime': '19:50', 'endTime': '20:30'},
  {'number': 13, 'startTime': '20:40', 'endTime': '21:20'},
  {'number': 14, 'startTime': '21:30', 'endTime': '22:10'},
];

/// 教室字段为空时的占位文本。
const String kUnknownPosition = '未获取到教室';

/// 解析节次字段，返回节号数组。
///
/// jcdm2 形如 "01,02,03"；jcdm 形如 "0102"（连写）。
List<int> parseSections(dynamic jcdm2, dynamic jcdm) {
  final txt = (jcdm2 ?? jcdm ?? '').toString().trim();
  final nums = <int>[];
  void push(int n) {
    if (n > 0 && !nums.contains(n)) nums.add(n);
  }

  for (final raw in txt.split(RegExp(r'[,\s]+'))) {
    final part = raw.trim();
    if (part.isEmpty || !RegExp(r'^\d+$').hasMatch(part)) continue;
    if (part.length <= 2) {
      push(int.parse(part));
    } else {
      // 连写形式：每两位一个节号
      for (var i = 0; i < part.length; i += 2) {
        final chunk = part.substring(i, i + 2);
        if (chunk.length == 2) push(int.parse(chunk));
      }
    }
  }
  nums.sort();
  return nums;
}

/// 解析课程记录自带的周次字段，返回周号数组。
///
/// 兼容多种教务写法：
///   "1-8,10-17周"      区间
///   "1,3,5周"          逗号分隔
///   "1111111100000000" 位串（第 i 位为 1 表示第 i+1 周）
///   "1-16(单)"         带单双周后缀
List<int> parseWeekText(dynamic zc) {
  final txt = (zc ?? '').toString().trim();
  if (txt.isEmpty) return const [];

  // 位串
  if (RegExp(r'^[01]{4,}$').hasMatch(txt)) {
    final out = <int>[];
    for (var i = 0; i < txt.length; i++) {
      if (txt[i] == '1') out.add(i + 1);
    }
    return out;
  }

  // 区间 / 列表：去掉「周、单、双、(单)」等修饰
  var cleaned = txt.replaceAll(RegExp(r'周|星期'), '');
  cleaned = cleaned.replaceAll(RegExp(r'[（(][^）)]*[）)]'), '');
  cleaned = cleaned.replaceAll(RegExp(r'[单双]'), '');

  final out = <int>[];
  for (final raw in cleaned.split(RegExp(r'[,，\s]+'))) {
    final part = raw.trim();
    if (part.isEmpty) continue;
    final range = RegExp(r'^(\d+)\s*-\s*(\d+)$').firstMatch(part);
    if (range != null) {
      final a = int.parse(range.group(1)!);
      final b = int.parse(range.group(2)!);
      if (a > 0 && b >= a) {
        for (var i = a; i <= b; i++) {
          out.add(i);
        }
      }
      continue;
    }
    if (RegExp(r'^\d+$').hasMatch(part)) {
      final n = int.parse(part);
      if (n > 0) out.add(n);
    }
  }
  return out.toSet().toList()..sort();
}

/// 节次与周次合并去重（对应拾光官方 wiki 的 mergeAndDistinctCourses）。
///
/// 阶段 1：合并连续节次与完全重复记录。
/// 阶段 2：合并同节次的周次。
List<Map<String, dynamic>> mergeAndDistinctCourses(
    List<Map<String, dynamic>> courses) {
  if (courses.length <= 1) return courses;

  final list = courses.map((c) => {
        ...c,
        'name': c['name'] ?? '',
        'teacher': c['teacher'] ?? '',
        'position': c['position'] ?? '',
        'weeks': ((c['weeks'] as List?) ?? []).map((e) => (e as num).toInt()).toList()..sort(),
      }).toList();

  // 阶段 1：合并连续节次与完全重复记录
  list.sort((a, b) {
    final n = (a['name'] as String).compareTo(b['name'] as String);
    if (n != 0) return n;
    final t = (a['teacher'] as String).compareTo(b['teacher'] as String);
    if (t != 0) return t;
    final p = (a['position'] as String).compareTo(b['position'] as String);
    if (p != 0) return p;
    final d = ((a['day'] as num?)?.toInt() ?? 0) - ((b['day'] as num?)?.toInt() ?? 0);
    if (d != 0) return d;
    final w = (a['weeks'] as List).join(',').compareTo((b['weeks'] as List).join(','));
    if (w != 0) return w;
    return ((a['startSection'] as num?)?.toInt() ?? 0) -
        ((b['startSection'] as num?)?.toInt() ?? 0);
  });

  final step1 = <Map<String, dynamic>>[];
  var current = Map<String, dynamic>.from(list.first);

  for (var i = 1; i < list.length; i++) {
    final next = list[i];

    final sameCourseAndWeeks =
        current['name'] == next['name'] &&
            current['teacher'] == next['teacher'] &&
            current['position'] == next['position'] &&
            current['day'] == next['day'] &&
            (current['weeks'] as List).join(',') == (next['weeks'] as List).join(',');

    final endSection = (current['endSection'] as num?)?.toInt() ?? 0;
    final nextStart = (next['startSection'] as num?)?.toInt() ?? 0;
    final nextEnd = (next['endSection'] as num?)?.toInt() ?? 0;
    final curStart = (current['startSection'] as num?)?.toInt() ?? 0;

    final isContinuous = endSection + 1 == nextStart;
    final isDuplicate = curStart == nextStart && endSection == nextEnd;

    if (sameCourseAndWeeks && isContinuous) {
      current['endSection'] = nextEnd;
    } else if (sameCourseAndWeeks && isDuplicate) {
      continue;
    } else {
      step1.add(current);
      current = Map<String, dynamic>.from(next);
    }
  }
  step1.add(current);

  // 阶段 2：合并同节次的周次
  step1.sort((a, b) {
    final n = (a['name'] as String).compareTo(b['name'] as String);
    if (n != 0) return n;
    final t = (a['teacher'] as String).compareTo(b['teacher'] as String);
    if (t != 0) return t;
    final p = (a['position'] as String).compareTo(b['position'] as String);
    if (p != 0) return p;
    final d = ((a['day'] as num?)?.toInt() ?? 0) - ((b['day'] as num?)?.toInt() ?? 0);
    if (d != 0) return d;
    final s = ((a['startSection'] as num?)?.toInt() ?? 0) -
        ((b['startSection'] as num?)?.toInt() ?? 0);
    if (s != 0) return s;
    return ((a['endSection'] as num?)?.toInt() ?? 0) -
        ((b['endSection'] as num?)?.toInt() ?? 0);
  });

  final step2 = <Map<String, dynamic>>[];
  var cur = Map<String, dynamic>.from(step1.first);

  for (var i = 1; i < step1.length; i++) {
    final nxt = step1[i];

    final sameCourseAndSection =
        cur['name'] == nxt['name'] &&
            cur['teacher'] == nxt['teacher'] &&
            cur['position'] == nxt['position'] &&
            cur['day'] == nxt['day'] &&
            cur['startSection'] == nxt['startSection'] &&
            cur['endSection'] == nxt['endSection'];

    if (sameCourseAndSection) {
      final merged = ((cur['weeks'] as List?) ?? [])
          .map((e) => (e as num).toInt())
          .toSet();
      merged.addAll(((nxt['weeks'] as List?) ?? []).map((e) => (e as num).toInt()));
      cur['weeks'] = merged.toList()..sort();
    } else {
      step2.add(cur);
      cur = Map<String, dynamic>.from(nxt);
    }
  }
  step2.add(cur);

  return step2;
}

/// 解析整学期数据，聚合成课程数组。
///
/// 服务端一次返回整学期的排课记录，每条自带 zc（该门课上课的周次），
/// 按「课程名+教师+教室+星期+起止节次」聚合出 weeks 数组。
JwglCollectResult collectCourses(List<Map<String, dynamic>> records) {
  final courses = <Map<String, dynamic>>[];

  for (final c in records) {
    final day = int.tryParse((c['xq'] ?? '').toString()) ?? 0;
    if (day < 1 || day > 7) continue;

    final name = (c['kcmc'] ?? '').toString().trim();
    if (name.isEmpty) continue;

    final sections = parseSections(c['jcdm2'], c['jcdm']);
    if (sections.isEmpty) continue;

    final weeks = parseWeekText(c['zc']);
    if (weeks.isEmpty) continue;

    final teacher = (c['teaxms'] ?? '').toString().trim();
    final positionRaw = (c['jxcdmc'] ?? '').toString().trim();
    final position = positionRaw.isEmpty ? kUnknownPosition : positionRaw;
    final startSection = sections.first;
    final endSection = sections.last;

    // 同一门课同一时段可能有多条记录（不同周次区间），按周次归并
    final exist = courses.indexWhere((x) =>
        x['name'] == name &&
        x['teacher'] == teacher &&
        x['position'] == position &&
        x['day'] == day &&
        x['startSection'] == startSection &&
        x['endSection'] == endSection);

    if (exist >= 0) {
      final merged = ((courses[exist]['weeks'] as List?) ?? []).toSet();
      merged.addAll(weeks);
      courses[exist]['weeks'] = merged.toList()..sort();
    } else {
      courses.add({
        'name': name,
        'teacher': teacher,
        'position': position,
        'day': day,
        'startSection': startSection,
        'endSection': endSection,
        'weeks': weeks,
      });
    }
  }

  // 总周数取所有课程周次的最大值
  var totalWeeks = 0;
  for (final c in courses) {
    for (final w in (c['weeks'] as List)) {
      final wi = (w as num).toInt();
      if (wi > totalWeeks) totalWeeks = wi;
    }
  }

  return JwglCollectResult(
    courses: mergeAndDistinctCourses(courses),
    totalWeeks: totalWeeks,
  );
}

/// collectCourses 的返回值。
class JwglCollectResult {
  const JwglCollectResult({required this.courses, required this.totalWeeks});

  final List<Map<String, dynamic>> courses;
  final int totalWeeks;
}

/// 从 WebView 注入脚本返回的原始 JSON 构建抓取结果。
///
/// [raw] 是适配脚本在页面内执行后回传的字符串，结构：
/// ```json
/// {"ok": true, "term": "202601", "termName": "2026-2027-1",
///  "semesterStartDate": "2026-08-31", "totalWeeks": 22,
///  "courses": [...], "timeSlots": [...]}
/// ```
JwglFetchResult parseFetchPayload(String raw) {
  final Map<String, dynamic> j;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw JwglException('抓取结果格式异常');
    }
    j = decoded;
  } on FormatException {
    throw JwglException('抓取结果解析失败：$raw');
  }

  if (j['ok'] != true) {
    throw JwglException((j['error'] ?? '抓取失败').toString());
  }

  final courses = ((j['courses'] as List?) ?? [])
      .whereType<Map<String, dynamic>>()
      .toList();
  if (courses.isEmpty) {
    throw JwglException('未获取到课表数据，请确认该学期已选课。');
  }

  return JwglFetchResult(
    term: (j['term'] ?? '').toString(),
    termName: (j['termName'] ?? '').toString(),
    totalWeeks: (j['totalWeeks'] as num?)?.toInt() ?? 0,
    semesterStartDate: (j['semesterStartDate'] ?? '').toString(),
    courses: courses,
    timeSlots: ((j['timeSlots'] as List?) ?? [])
        .whereType<Map<String, dynamic>>()
        .toList(),
  );
}

/// 适配脚本回传的一条消息。
///
/// 脚本会回传两种消息（[type] 区分）：
///   progress —— 进度提示，展示在页面状态栏；
///   result   —— 最终结果，[result] 非空表示成功，否则 [error] 为失败原因。
class JwglBridgeMessage {
  const JwglBridgeMessage({
    required this.type,
    this.message,
    this.result,
    this.error,
  });

  /// 消息类型：progress / result。
  final String type;

  /// 进度文本。
  final String? message;

  /// 成功时的抓取结果。
  final JwglFetchResult? result;

  /// 失败原因。
  final String? error;

  bool get isProgress => type == 'progress';
  bool get isSuccess => result != null;
}

/// 解析适配脚本回传的消息。
///
/// 兼容两种格式：
///   {"type":"progress","message":"正在读取课表 ..."}
///   {"type":"result","ok":true,"courses":[...], ...}
/// 未带 type 的旧格式按 result 处理。
JwglBridgeMessage parseBridgeMessage(String raw) {
  Map<String, dynamic> j;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw JwglException('回传消息格式异常：$raw');
    }
    j = decoded;
  } on FormatException {
    throw JwglException('回传消息解析失败：$raw');
  }

  final type = (j['type'] ?? 'result').toString();
  if (type == 'progress') {
    return JwglBridgeMessage(
      type: 'progress',
      message: (j['message'] ?? '').toString(),
    );
  }

  // result：ok 为 false 时把 error 抛出，由调用方展示
  if (j['ok'] != true) {
    return JwglBridgeMessage(
      type: 'result',
      error: (j['error'] ?? '抓取失败').toString(),
    );
  }

  return JwglBridgeMessage(type: 'result', result: parseFetchPayload(raw));
}
