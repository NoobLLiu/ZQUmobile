/// 快递站营业数据与状态判定。
///
/// 营业时间为预先录入的驿站公示时间，结合当前系统时间判定能否去拿快递：
///   - 红：未营业（含「驿站开门但校门已关 → 不可达」两种情况）
///   - 黄：营业中，但距结束营业不足 30 分钟
///   - 绿：正常营业中
///   - 灰：数据待补充
library;

/// 打烊预警窗口：距结束营业不足该时长时，卡片转黄。
const int kClosingSoonMinutes = 30;

/// 一段当日营业时间，按分钟存储（[open, close) 左闭右开）。
class TimeRange {
  const TimeRange(this.open, this.close);

  /// 由 "HH:mm" 字符串构造，如 `TimeRange.hhmm('07:00', '23:00')`。
  factory TimeRange.hhmm(String open, String close) => TimeRange(
        _parseMinutes(open),
        _parseMinutes(close),
      );

  /// 开门时刻（分钟数）。
  final int open;

  /// 关门时刻（分钟数）。
  final int close;

  static int _parseMinutes(String hhmm) {
    final parts = hhmm.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
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
    this.hours,
    this.weekdayHours = const {},
  });

  /// 驿站名称。
  final String name;

  /// 默认营业时间；null 表示数据待补充。
  final TimeRange? hours;

  /// 按星期覆盖的时间（DateTime.weekday：1=周一 … 7=周日），
  /// 如肯德基旁驿站周五 11:00-20:50。
  final Map<int, TimeRange> weekdayHours;

  /// 是否已录入营业时间。
  bool get hasData => hours != null;

  /// 某天生效的营业时间（无覆盖时用默认值）。
  TimeRange? hoursFor(int weekday) => weekdayHours[weekday] ?? hours;
}

/// 一组驿站（按校门分组），可附带校门开放时间。
class ExpressStationGroup {
  const ExpressStationGroup({
    required this.name,
    required this.stations,
    this.gateHours,
  });

  /// 分组名，如「东门」。
  final String name;

  /// 校门开放时间；null 表示未录入（不做校门判定）。
  final TimeRange? gateHours;

  /// 组内驿站。
  final List<ExpressStation> stations;
}

/// 驿站当前状态。
enum ExpressStatus {
  /// 营业中（绿）。
  open,

  /// 营业中，距打烊不足 30 分钟（黄）。
  closingSoon,

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
  });

  /// 当前状态。
  final ExpressStatus status;

  ///今日生效的营业时间（noData 时为 null）。
  final TimeRange? hours;

  /// 距打烊分钟数（仅营业中有意义）。
  final int? minutesToClose;
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

/// 预先录入的驿站数据（以驿站现场公告为准，欢迎反馈补充）。
final List<ExpressStationGroup> kExpressStationGroups = [
  ExpressStationGroup(
    name: '校内',
    stations: [
      ExpressStation(
        name: '京东快递站',
        hours: TimeRange.hhmm('10:00', '19:00'),
      ),
      ExpressStation(
        name: '顺丰营业点',
        hours: TimeRange.hhmm('10:00', '19:00'),
      ),
    ],
  ),
  ExpressStationGroup(
    name: '东门',
    gateHours: TimeRange.hhmm('07:00', '23:00'),
    stations: [
      ExpressStation(
        name: '东门菜鸟驿站',
        hours: TimeRange.hhmm('10:00', '23:00'),
      ),
      ExpressStation(
        name: '东门申通快递',
        hours: TimeRange.hhmm('10:00', '21:00'),
      ),
      ExpressStation(
        name: '肯德基旁驿站',
        hours: TimeRange.hhmm('10:00', '21:00'),
        weekdayHours: {
          // 周五
          5: TimeRange.hhmm('11:00', '20:50'),
        },
      ),
      ExpressStation(
        name: '菜鸟の茶驿站',
        hours: TimeRange.hhmm('10:00', '22:00'),
      ),
    ],
  ),
  ExpressStationGroup(
    name: '南门',
    stations: [
      ExpressStation(name: '南门车库驿站'),
    ],
  ),
];
