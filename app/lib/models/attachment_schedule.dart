/// 附属日程：晚自习、阳光体育等随课表之外的固定作息安排。
///
/// 每条日程按星期重复（不绑定具体日期与教学周），
/// 在附属日程页管理，并合并展示到首页看板的 Today 列表里。
library;

/// 附属日程类型。
enum AttachmentScheduleType {
  eveningStudy,
  sunshineSport;

  /// 中文名。
  String get label => switch (this) {
        AttachmentScheduleType.eveningStudy => '晚自习',
        AttachmentScheduleType.sunshineSport => '阳光体育',
      };
}

/// 一条附属日程。
class AttachmentSchedule {
  AttachmentSchedule({
    required this.id,
    required this.type,
    required this.title,
    required this.weekdays,
    required this.start,
    required this.end,
    this.location = '',
    this.note = '',
    this.enabled = true,
  });

  /// 唯一标识（毫秒时间戳 + 微秒尾巴，本机生成即可）。
  final String id;

  final AttachmentScheduleType type;

  /// 名称，如「图书馆晚自习」。
  final String title;

  /// 重复的星期，1 = 周一 … 7 = 周日。
  final List<int> weekdays;

  /// 开始时间，HH:mm。
  final String start;

  /// 结束时间，HH:mm。
  final String end;

  /// 地点，可为空。
  final String location;

  /// 备注，可为空。
  final String note;

  /// 是否启用（停用的日程不展示到看板）。
  final bool enabled;

  bool occursOn(int weekday) => weekdays.contains(weekday);

  /// 「19:00 - 21:00」。
  String get timeRange => '$start - $end';

  /// 星期摘要：连续三天以上折叠成「周一至周四」，全程为「每天」，其余顿号相连。
  String get weekdayLabel {
    if (weekdays.isEmpty) return '未设重复';
    final sorted = weekdays.toList()..sort();
    if (sorted.length == 7) return '每天';

    // 按 1..7 顺序切成连续段。
    final segments = <List<int>>[];
    var current = <int>[sorted.first];
    for (var i = 1; i < sorted.length; i++) {
      if (sorted[i] == sorted[i - 1] + 1) {
        current.add(sorted[i]);
      } else {
        segments.add(current);
        current = <int>[sorted[i]];
      }
    }
    segments.add(current);

    return [
      for (final seg in segments)
        seg.length >= 3
            ? '${_weekdayName(seg.first)}至${_weekdayName(seg.last)}'
            : [for (final d in seg) _weekdayName(d)].join('、'),
    ].join('、');
  }

  static String _weekdayName(int weekday) =>
      const ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][weekday - 1];

  /// 「HH:mm」→ 当天分钟数；格式非法返回 -1。
  static int toMinute(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return -1;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) return -1;
    return h * 60 + m;
  }

  /// 是否为合法的起止时间（结束必须晚于开始）。
  static bool isValidRange(String start, String end) {
    final s = toMinute(start);
    final e = toMinute(end);
    return s >= 0 && e > s;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'title': title,
        'weekdays': weekdays,
        'start': start,
        'end': end,
        'location': location,
        'note': note,
        'enabled': enabled,
      };

  factory AttachmentSchedule.fromJson(Map<String, dynamic> j) {
    final typeName = (j['type'] ?? '').toString();
    return AttachmentSchedule(
      id: (j['id'] ?? '').toString(),
      type: typeName == 'sunshineSport'
          ? AttachmentScheduleType.sunshineSport
          : AttachmentScheduleType.eveningStudy,
      title: (j['title'] ?? '').toString(),
      weekdays: [
        if (j['weekdays'] is List)
          for (final d in j['weekdays'] as List)
            if (d is num && d >= 1 && d <= 7) d.toInt(),
      ],
      start: (j['start'] ?? '').toString(),
      end: (j['end'] ?? '').toString(),
      location: (j['location'] ?? '').toString(),
      note: (j['note'] ?? '').toString(),
      enabled: (j['enabled'] ?? true) == true,
    );
  }

  AttachmentSchedule copyWith({
    String? id,
    AttachmentScheduleType? type,
    String? title,
    List<int>? weekdays,
    String? start,
    String? end,
    String? location,
    String? note,
    bool? enabled,
  }) =>
      AttachmentSchedule(
        id: id ?? this.id,
        type: type ?? this.type,
        title: title ?? this.title,
        weekdays: weekdays ?? this.weekdays,
        start: start ?? this.start,
        end: end ?? this.end,
        location: location ?? this.location,
        note: note ?? this.note,
        enabled: enabled ?? this.enabled,
      );
}
