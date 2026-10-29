/// 课表数据模型。
///
/// 字段语义对齐拾光课表的 CourseJsonModel / TimeSlotJsonModel，
/// 以便 WebView 适配脚本抓到的数据可以直接落库。
library;

/// 一个作时间段（节次）。
class TimeSlot {
  const TimeSlot({
    required this.number,
    required this.startTime,
    required this.endTime,
    this.alias,
  });

  /// 节号，从 1 开始。
  final int number;

  /// 开始时间 "HH:mm"。
  final String startTime;

  /// 结束时间 "HH:mm"。
  final String endTime;

  /// 节次别名（如「上午」），为空则显示节号。
  final String? alias;

  factory TimeSlot.fromJson(Map<String, dynamic> j) => TimeSlot(
        number: (j['number'] as num?)?.toInt() ?? 0,
        startTime: j['startTime']?.toString() ?? '',
        endTime: j['endTime']?.toString() ?? '',
        alias: j['alias']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'number': number,
        'startTime': startTime,
        'endTime': endTime,
        if (alias != null) 'alias': alias,
      };
}

/// 一门课（含其上课周次）。
class Course {
  Course({
    required this.name,
    required this.teacher,
    required this.position,
    required this.day,
    required this.startSection,
    required this.endSection,
    required this.weeks,
    this.colorIndex,
  });

  /// 课程名。
  final String name;

  /// 教师。
  final String teacher;

  /// 上课地点。
  final String position;

  /// 星期，1=周一 … 7=周日。
  final int day;

  /// 起始节次。
  final int startSection;

  /// 结束节次。
  final int endSection;

  /// 上课周次集合。
  final List<int> weeks;

  /// 配色索引（null 表示按课程名散列自动取色）。
  final int? colorIndex;

  /// 本周是否上课。
  bool isActiveInWeek(int week) => weeks.contains(week);

  /// 深拷贝（用于编辑）。
  Course copyWith({
    String? name,
    String? teacher,
    String? position,
    int? day,
    int? startSection,
    int? endSection,
    List<int>? weeks,
    int? colorIndex,
  }) =>
      Course(
        name: name ?? this.name,
        teacher: teacher ?? this.teacher,
        position: position ?? this.position,
        day: day ?? this.day,
        startSection: startSection ?? this.startSection,
        endSection: endSection ?? this.endSection,
        weeks: weeks ?? this.weeks,
        colorIndex: colorIndex ?? this.colorIndex,
      );

  factory Course.fromJson(Map<String, dynamic> j) => Course(
        name: j['name']?.toString() ?? '',
        teacher: j['teacher']?.toString() ?? '',
        position: j['position']?.toString() ?? '',
        day: (j['day'] as num?)?.toInt() ?? 0,
        startSection: (j['startSection'] as num?)?.toInt() ?? 0,
        endSection: (j['endSection'] as num?)?.toInt() ?? 0,
        weeks: ((j['weeks'] as List?) ?? [])
            .map((e) => (e as num).toInt())
            .toList(),
        colorIndex: (j['colorIndex'] as num?)?.toInt(),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'teacher': teacher,
        'position': position,
        'day': day,
        'startSection': startSection,
        'endSection': endSection,
        'weeks': weeks,
        if (colorIndex != null) 'colorIndex': colorIndex,
      };
}

/// 一门课在网格中的展示块（可能合并了同课程同时段的冲突记录）。
class MergedCourseBlock {
  const MergedCourseBlock({
    required this.day,
    required this.startSection,
    required this.endSection,
    required this.courses,
    required this.isVisualDemoted,
    this.subColumnIndex = 0,
    this.subColumnCount = 1,
  });

  /// 星期（1..7）。
  final int day;

  /// 起始节次（1..n）。
  final int startSection;

  /// 结束节次。
  final int endSection;

  /// 该块包含的课程（正常情况下只有一门）。
  final List<Course> courses;

  /// 是否为「非本周课程」的灰化展示。
  final bool isVisualDemoted;

  /// 同一格里并排显示时的子列序号。
  final int subColumnIndex;

  /// 同一格里并排显示时的子列总数。
  final int subColumnCount;

  Course get course => courses.first;
}

/// 一整个学期的课表。
class Timetable {
  const Timetable({
    required this.term,
    required this.termName,
    required this.totalWeeks,
    required this.semesterStartDate,
    required this.courses,
    required this.timeSlots,
    this.fetchedAt,
  });

  /// 学期编号，如 "202601"。
  final String term;

  /// 学期名称，如 "2026-2027-1"。
  final String termName;

  /// 学期总周数。
  final int totalWeeks;

  /// 本学期第 1 周的周一日期 "YYYY-MM-DD"。
  final String semesterStartDate;

  /// 全部课程。
  final List<Course> courses;

  /// 作息时间表。
  final List<TimeSlot> timeSlots;

  /// 抓取时间。
  final String? fetchedAt;

  /// 根据开学日期推算某日期是第几周（1..totalWeeks），超出范围返回 null。
  int? weekOf(DateTime date) {
    final start = DateTime.tryParse(semesterStartDate);
    if (start == null) return null;
    final monday = DateTime(start.year, start.month, start.day);
    final target = DateTime(date.year, date.month, date.day);
    final diff = target.difference(monday).inDays;
    final week = diff ~/ 7 + 1;
    if (week < 1 || week > totalWeeks) return null;
    return week;
  }

  /// 某周的日期列表（索引 0 = 周一）。
  List<DateTime> datesOfWeek(int week) {
    final start = DateTime.tryParse(semesterStartDate);
    if (start == null) return const [];
    final monday = DateTime(start.year, start.month, start.day);
    final first = monday.add(Duration(days: (week - 1) * 7));
    return List.generate(7, (i) => first.add(Duration(days: i)));
  }

  factory Timetable.fromJson(Map<String, dynamic> j) => Timetable(
        term: j['term']?.toString() ?? '',
        termName: j['termName']?.toString() ?? '',
        totalWeeks: (j['totalWeeks'] as num?)?.toInt() ?? 0,
        semesterStartDate: j['semesterStartDate']?.toString() ?? '',
        courses: ((j['courses'] as List?) ?? [])
            .whereType<Map<String, dynamic>>()
            .map(Course.fromJson)
            .toList(),
        timeSlots: ((j['timeSlots'] as List?) ?? [])
            .whereType<Map<String, dynamic>>()
            .map(TimeSlot.fromJson)
            .toList(),
        fetchedAt: j['fetchedAt']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'term': term,
        'termName': termName,
        'totalWeeks': totalWeeks,
        'semesterStartDate': semesterStartDate,
        'courses': courses.map((c) => c.toJson()).toList(),
        'timeSlots': timeSlots.map((t) => t.toJson()).toList(),
        if (fetchedAt != null) 'fetchedAt': fetchedAt,
      };
}
