/// 肇庆学院教务系统（乘方 URP 系）桥接层。
///
/// 取数、解析、聚合均由注入 WebView 的上游适配脚本
/// （`assets/js/zqu_upstream.js`）完成，本文件只负责解析它回传给
/// Flutter 的桥接消息（进度 / 课程 / 学期配置 / 作息 / 完成）。
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
/// 消息类型（[type]）：
///   progress —— 进度提示；
///   courses  —— 官方脚本 saveImportedCourses 回传的课程数组；
///   config   —— 官方脚本 saveCourseConfig 回传的学期配置；
///   slots    —— 官方脚本 savePresetTimeSlots 回传的作息时间；
///   done     —— 官方脚本 notifyTaskCompletion，表示全部数据已就绪；
///   result   —— 旧格式：一次性携带全部结果（兼容保留）。
class JwglBridgeMessage {
  const JwglBridgeMessage({
    required this.type,
    this.json,
    this.message,
    this.result,
    this.error,
  });

  /// 消息类型。
  final String type;

  /// 原始解析后的 JSON，供调用方按需取字段。
  final Map<String, dynamic>? json;

  /// 进度文本。
  final String? message;

  /// 旧格式一次性结果。
  final JwglFetchResult? result;

  /// 失败原因。
  final String? error;

  bool get isProgress => type == 'progress';
  bool get isDone => type == 'done';
  bool get isFailed => error != null;
  bool get isSuccess => result != null;
}

/// 解析适配脚本回传的消息。
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
      json: j,
      message: (j['message'] ?? '').toString(),
    );
  }

  // result 且 ok=false 视为失败；其余类型原样交给调用方处理
  if (type == 'result' && j['ok'] != true) {
    return JwglBridgeMessage(
      type: 'result',
      json: j,
      error: (j['error'] ?? '抓取失败').toString(),
    );
  }

  if (type == 'result') {
    return JwglBridgeMessage(
      type: 'result',
      json: j,
      result: parseFetchPayload(raw),
    );
  }

  return JwglBridgeMessage(type: type, json: j);
}
