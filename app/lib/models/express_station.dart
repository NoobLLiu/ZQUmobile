/// 快递站营业数据与状态判定。
///
/// 数据本体不写在代码里：唯一数据源是仓库根的 `data/express_stations.json`，
/// CI 编译时生成内置快照（[kBundledExpressStationData]）并打进 assets，
/// 运行时再由 `ExpressStationRepository` 从 Gitee 热更新覆盖。
///
/// 营业时间结合当前系统时间判定能否去拿快递：
///   - 红：未营业（含「驿站开门但校门已关 → 不可达」两种情况）
///   - 黄：营业中距打烊不足 30 分钟，或尚未营业但距开门不足 30 分钟
///   - 绿：正常营业中
///   - 灰：数据待补充
library;

import 'dart:convert';

import '../generated/express_stations_bundled.dart';

/// 打烊预警窗口：距结束营业不足该时长时，卡片转黄。
const int kClosingSoonMinutes = 30;

/// 开门预警窗口：距开始营业不足该时长时，卡片也转黄。
const int kOpeningSoonMinutes = 30;

/// 当前支持的快递站 JSON 结构版本，高于它的新数据不覆盖本地，避免解析错乱。
const int kExpressStationSchemaVersion = 1;

/// 一段当日营业时间，按分钟存储（[open, close) 左闭右开）。
class TimeRange {
  const TimeRange(this.open, this.close);

  /// 由 "HH:mm" 字符串构造，如 `TimeRange.hhmm('07:00', '23:00')`。
  factory TimeRange.hhmm(String open, String close) => TimeRange(
        _parseMinutes(open),
        _parseMinutes(close),
      );

  /// 由 "HH:mm-HH:mm" 字符串构造（JSON 里用的格式）。
  factory TimeRange.parse(String text) {
    final parts = text.split('-');
    if (parts.length != 2) {
      throw FormatException('营业时间应为 HH:mm-HH:mm：$text');
    }
    return TimeRange(_parseMinutes(parts[0]), _parseMinutes(parts[1]));
  }

  /// 解析可为 null 的 JSON 字段；空值返回 null。
  static TimeRange? maybeParse(Object? value) {
    if (value == null) return null;
    final text = value.toString().trim();
    if (text.isEmpty) return null;
    return TimeRange.parse(text);
  }

  /// 开门时刻（分钟数）。
  final int open;

  /// 关门时刻（分钟数）。
  final int close;

  static int _parseMinutes(String hhmm) {
    final parts = hhmm.trim().split(':');
    if (parts.length != 2) {
      throw FormatException('时间应为 HH:mm：$hhmm');
    }
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) {
      throw FormatException('时间应为 HH:mm：$hhmm');
    }
    return h * 60 + m;
  }

  /// [minutes] 是否在营业时段内。
  bool contains(int minutes) => minutes >= open && minutes < close;

  /// 距关门还剩多少分钟（不在时段内时无意义）。
  int minutesToClose(int minutes) => close - minutes;

  /// 展示为 "07:00-23:00"。
  String format() => '${_fmt(open)}-${_fmt(close)}';

  static String _fmt(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }
}

/// 一个快递驿站。
class ExpressStation {
  const ExpressStation({
    required this.name,
    this.id,
    this.location = '',
    this.note = '',
    this.hours,
    this.weekdayHours = const {},
  });

  factory ExpressStation.fromJson(Map<String, dynamic> json) => ExpressStation(
        id: json['id'] as String?,
        name: (json['name'] as String? ?? '').trim(),
        location: json['location'] as String? ?? '',
        note: json['note'] as String? ?? '',
        hours: TimeRange.maybeParse(json['hours']),
        weekdayHours: _parseWeekdayHours(json['weekdayHours']),
      );

  /// 稳定标识（可选，便于日后按 id 做增量更新）。
  final String? id;

  /// 驿站名称。
  final String name;

  /// 具体位置，空串表示待补充。
  final String location;

  /// 备注（如特殊营业安排），空串表示无。
  final String note;

  /// 默认营业时间；null 表示数据待补充。
  final TimeRange? hours;

  /// 按星期覆盖的时间（DateTime.weekday：1=周一 … 7=周日），
  /// 如肯德基旁驿站周五 11:00-20:50。
  final Map<int, TimeRange> weekdayHours;

  /// 是否已录入营业时间。
  bool get hasData => hours != null;

  /// 某天生效的营业时间（无覆盖时用默认值）。
  TimeRange? hoursFor(int weekday) => weekdayHours[weekday] ?? hours;

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'name': name,
        if (location.isNotEmpty) 'location': location,
        if (note.isNotEmpty) 'note': note,
        if (hours != null) 'hours': hours!.format(),
        if (weekdayHours.isNotEmpty)
          'weekdayHours': {
            for (final e in weekdayHours.entries)
              e.key.toString(): e.value.format(),
          },
      };
}

Map<int, TimeRange> _parseWeekdayHours(Object? raw) {
  final result = <int, TimeRange>{};
  if (raw is! Map) return result;
  raw.forEach((key, value) {
    final day = int.tryParse(key.toString());
    final range = TimeRange.maybeParse(value);
    if (day != null && day >= 1 && day <= 7 && range != null) {
      result[day] = range;
    }
  });
  return result;
}

/// 一组驿站（按校门分组），可附带校门开放时间。
class ExpressStationGroup {
  const ExpressStationGroup({
    required this.name,
    required this.stations,
    this.id,
    this.location = '',
    this.note = '',
    this.gateHours,
  });

  factory ExpressStationGroup.fromJson(Map<String, dynamic> json) =>
      ExpressStationGroup(
        id: json['id'] as String?,
        name: (json['name'] as String? ?? '').trim(),
        location: json['location'] as String? ?? '',
        note: json['note'] as String? ?? '',
        gateHours: TimeRange.maybeParse(json['gateHours']),
        stations: [
          for (final s in (json['stations'] as List? ?? const []))
            if (s is Map)
              ExpressStation.fromJson(Map<String, dynamic>.from(s)),
        ],
      );

  /// 稳定标识（可选）。
  final String? id;

  /// 分组名，如「东门」。
  final String name;

  /// 分组所在方位，空串表示待补充。
  final String location;

  /// 分组备注（如校门关闭提示）。
  final String note;

  /// 校门开放时间；null 表示未录入（不做校门判定）。
  final TimeRange? gateHours;

  /// 组内驿站。
  final List<ExpressStation> stations;

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'name': name,
        if (location.isNotEmpty) 'location': location,
        if (note.isNotEmpty) 'note': note,
        if (gateHours != null) 'gateHours': gateHours!.format(),
        'stations': [for (final s in stations) s.toJson()],
      };
}

/// 一份完整快递站数据（出厂内置 / 本地缓存 / 热更新都用这个结构）。
class ExpressStationData {
  const ExpressStationData({
    required this.revision,
    required this.updatedAt,
    required this.notice,
    required this.groups,
    this.schemaVersion = kExpressStationSchemaVersion,
  });

  factory ExpressStationData.fromJson(Map<String, dynamic> json) {
    final rawGroups = json['groups'];
    if (rawGroups is! List) {
      throw const FormatException('快递站数据缺少 groups');
    }
    return ExpressStationData(
      schemaVersion:
          (json['schemaVersion'] as num?)?.toInt() ?? kExpressStationSchemaVersion,
      revision: (json['revision'] as num?)?.toInt() ?? 0,
      updatedAt: json['updatedAt'] as String? ?? '',
      notice: json['notice'] as String? ?? '',
      groups: [
        for (final g in rawGroups)
          if (g is Map) ExpressStationGroup.fromJson(Map<String, dynamic>.from(g)),
      ],
    );
  }

  /// 从 JSON 字符串解析，格式非法抛 FormatException。
  factory ExpressStationData.parse(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const FormatException('快递站数据格式异常');
    }
    return ExpressStationData.fromJson(Map<String, dynamic>.from(decoded));
  }

  /// 结构版本，高于 [kExpressStationSchemaVersion] 的数据会被拒绝。
  final int schemaVersion;

  /// 数据版本号（单调递增），用于判断远端是否比本地新。
  final int revision;

  /// 数据更新日期（展示用）。
  final String updatedAt;

  /// 页面底部说明文字。
  final String notice;

  /// 按校门分组的驿站列表。
  final List<ExpressStationGroup> groups;

  /// 是否可作为有效数据使用。
  bool get isValid =>
      groups.isNotEmpty && schemaVersion <= kExpressStationSchemaVersion;

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'revision': revision,
        'updatedAt': updatedAt,
        'notice': notice,
        'groups': [for (final g in groups) g.toJson()],
      };

  String encode() =>
      '${const JsonEncoder.withIndent('  ').convert(toJson())}\n';
}

/// 出厂内置快照：由 `tool/gen_express_stations.dart` 从
/// `data/express_stations.json` 生成，请勿手改。
final ExpressStationData kBundledExpressStationData =
    ExpressStationData.parse(kBundledExpressStationJson);

/// 兼容旧引用：出厂内置的分组列表（首帧与测试用）。
List<ExpressStationGroup> get kExpressStationGroups =>
    kBundledExpressStationData.groups;

/// 驿站当前状态。
enum ExpressStatus {
  /// 营业中（绿）。
  open,

  /// 营业中，距打烊不足 30 分钟（黄）。
  closingSoon,

  /// 尚未营业，但距开门不足 30 分钟（黄）。
  openingSoon,

  /// 未营业（红）。
  closed,

  /// 驿站在营业，但校门已关，走不过去（红）。
  unreachable,

  /// 数据待补充（灰）。
  noData,
}

/// 一次状态判定的完整结果。
class ExpressStatusResult {
  const ExpressStatusResult({
    required this.status,
    this.hours,
    this.minutesToClose,
    this.minutesToOpen,
  });

  /// 当前状态。
  final ExpressStatus status;

  ///今日生效的营业时间（noData 时为 null）。
  final TimeRange? hours;

  /// 距打烊分钟数（仅「即将打烊」有意义）。
  final int? minutesToClose;

  /// 距开门分钟数（仅「即将营业」有意义）。
  final int? minutesToOpen;
}

/// 判定驿站当前状态。
///
/// [gateHours] 为所属校门的开放时间，null 时不做校门判定。
ExpressStatusResult evaluateExpressStation(
  ExpressStation station,
  DateTime now, {
  TimeRange? gateHours,
}) {
  if (!station.hasData) {
    return const ExpressStatusResult(status: ExpressStatus.noData);
  }
  final minutes = now.hour * 60 + now.minute;
  final today = station.hoursFor(now.weekday)!;

  if (!today.contains(minutes)) {
    // 开门前不足 30 分钟：同样用黄色提醒「快开门了」；打烊后不触发。
    final untilOpen = today.open - minutes;
    if (untilOpen > 0 && untilOpen <= kOpeningSoonMinutes) {
      return ExpressStatusResult(
        status: ExpressStatus.openingSoon,
        hours: today,
        minutesToOpen: untilOpen,
      );
    }
    return ExpressStatusResult(
      status: ExpressStatus.closed,
      hours: today,
    );
  }
  // 驿站开着，但校门关了：显示不可达。
  if (gateHours != null && !gateHours.contains(minutes)) {
    return ExpressStatusResult(
      status: ExpressStatus.unreachable,
      hours: today,
      minutesToClose: today.minutesToClose(minutes),
    );
  }
  final remain = today.minutesToClose(minutes);
  if (remain <= kClosingSoonMinutes) {
    return ExpressStatusResult(
      status: ExpressStatus.closingSoon,
      hours: today,
      minutesToClose: remain,
    );
  }
  return ExpressStatusResult(
    status: ExpressStatus.open,
    hours: today,
    minutesToClose: remain,
  );
}
