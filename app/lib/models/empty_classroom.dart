/// 空教室功能的数据模型。
///
/// 扫描数据来自注入教务系统的班级课表扫描脚本（assets/js/zqu_room_scan.js），
/// 按「学院 → 专业 → 年级 → 班级」遍历全院班级课表后聚合而成。
/// 存储层做两处去重：地点字符串与课程名字符串各存一份索引表，
/// 排课记录只存下标，控制 SharedPreferences 里的 JSON 体积。
library;

/// 一条排课记录（某班某门课在某地点某时段上课）。
///
/// [day] 1=周一 … 7=周日；**0 表示星期未知**（扫描时列表缺星期列），
/// 查询时按「占用所有星期」的保守策略处理。
class RoomLesson {
  const RoomLesson({
    required this.day,
    required this.startSection,
    required this.endSection,
    required this.weeks,
    required this.positionIndex,
    required this.nameIndex,
  });

  /// 星期，1=周一 … 7=周日，0=未知（整天占用）。
  final int day;

  /// 起始节次。
  final int startSection;

  /// 结束节次。
  final int endSection;

  /// 上课周次集合。
  final List<int> weeks;

  /// 地点在 [RoomScanData.positions] 里的下标。
  final int positionIndex;

  /// 课程名在 [RoomScanData.courseNames] 里的下标。
  final int nameIndex;

  factory RoomLesson.fromJson(Map<String, dynamic> j) => RoomLesson(
        day: (j['d'] as num?)?.toInt() ?? 0,
        startSection: (j['s'] as num?)?.toInt() ?? 1,
        endSection: (j['e'] as num?)?.toInt() ?? 14,
        weeks: ((j['w'] as List?) ?? [])
            .map((e) => (e as num).toInt())
            .toList(),
        positionIndex: (j['p'] as num?)?.toInt() ?? 0,
        nameIndex: (j['n'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'd': day,
        's': startSection,
        'e': endSection,
        'w': weeks,
        'p': positionIndex,
        'n': nameIndex,
      };
}

/// 一次完整扫描的结果。
class RoomScanData {
  const RoomScanData({
    required this.term,
    required this.termName,
    required this.scannedAt,
    required this.gradeFrom,
    required this.gradeTo,
    required this.classCount,
    required this.positions,
    required this.courseNames,
    required this.lessons,
    this.semesterStartDate = '',
    this.coarseCount = 0,
  });

  /// 学期编号，如 "202601"。
  final String term;

  /// 学期名称，如 "2026-2027-1"。
  final String termName;

  /// 本学期第 1 周的周一日期 "YYYY-MM-DD"（扫描时从教务接口取到）。
  /// 未导入个人课表时，用它推算查询周次。
  final String semesterStartDate;

  /// 扫描完成时间。
  final DateTime scannedAt;

  /// 扫描的年级窗口（入学年份）。
  final int gradeFrom;
  final int gradeTo;

  /// 扫过的班级总数。
  final int classCount;

  /// 去重后的上课地点字符串表。
  final List<String> positions;

  /// 去重后的课程名字符串表。
  final List<String> courseNames;

  /// 全部排课记录。
  final List<RoomLesson> lessons;

  /// 因列表缺星期/节次列而退化为「整天占用」的记录数。
  final int coarseCount;

  factory RoomScanData.fromJson(Map<String, dynamic> j) => RoomScanData(
        term: j['term']?.toString() ?? '',
        termName: j['termName']?.toString() ?? '',
        scannedAt:
            DateTime.tryParse(j['scannedAt']?.toString() ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0),
        gradeFrom: (j['gradeFrom'] as num?)?.toInt() ?? 0,
        gradeTo: (j['gradeTo'] as num?)?.toInt() ?? 0,
        classCount: (j['classCount'] as num?)?.toInt() ?? 0,
        semesterStartDate: j['semesterStartDate']?.toString() ?? '',
        positions: ((j['positions'] as List?) ?? [])
            .map((e) => e.toString())
            .toList(),
        courseNames: ((j['courseNames'] as List?) ?? [])
            .map((e) => e.toString())
            .toList(),
        lessons: ((j['lessons'] as List?) ?? [])
            .whereType<Map<String, dynamic>>()
            .map(RoomLesson.fromJson)
            .toList(),
        coarseCount: (j['coarseCount'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'term': term,
        'termName': termName,
        'scannedAt': scannedAt.toIso8601String(),
        'gradeFrom': gradeFrom,
        'gradeTo': gradeTo,
        'classCount': classCount,
        'semesterStartDate': semesterStartDate,
        'positions': positions,
        'courseNames': courseNames,
        'lessons': lessons.map((l) => l.toJson()).toList(),
        'coarseCount': coarseCount,
      };

  /// 根据扫描时取到的开学日期推算某日期是第几周（1..30），
  /// 未取到开学日期或超出范围返回 null。
  int? weekOf(DateTime date) {
    final start = DateTime.tryParse(semesterStartDate);
    if (start == null) return null;
    final monday = DateTime(start.year, start.month, start.day);
    final target = DateTime(date.year, date.month, date.day);
    if (target.isBefore(monday)) return null;
    final week = target.difference(monday).inDays ~/ 7 + 1;
    if (week < 1 || week > 30) return null;
    return week;
  }
}

/// 扫描数据构建器：分批接收扫描脚本的回传，最后组装成 [RoomScanData]。
class RoomScanBuilder {
  final List<String> _positions = [];
  final Map<String, int> _positionIndex = {};
  final List<String> _courseNames = [];
  final Map<String, int> _nameIndex = {};
  final List<RoomLesson> _lessons = [];

  int _classCount = 0;
  int _coarseCount = 0;

  int get classCount => _classCount;
  int get lessonCount => _lessons.length;

  /// 收一批回传。
  ///
  /// [classes] 是本批班级数组；[lessons] 里 `c` 字段指向本批 classes 的下标，
  /// `w` 是压缩周次串（"1-8,10-17"），`coarse` 标记退化记录。
  void addBatch(
    List<Map<String, dynamic>> classes,
    List<Map<String, dynamic>> lessons,
  ) {
    _classCount += classes.length;
    for (final l in lessons) {
      final ci = (l['c'] as num?)?.toInt() ?? 0;
      if (ci < 0 || ci >= classes.length) continue;

      final position = (l['p'] ?? '').toString().trim();
      final name = (l['n'] ?? '').toString().trim();

      final weeks = parseWeeksCompact((l['w'] ?? '').toString());
      final coarse = l['coarse'] == true;
      if (coarse) _coarseCount++;

      _lessons.add(RoomLesson(
        day: (l['d'] as num?)?.toInt() ?? 0,
        startSection: (l['s'] as num?)?.toInt() ?? 1,
        endSection: (l['e'] as num?)?.toInt() ?? 14,
        weeks: weeks,
        positionIndex: _indexFor(_positions, _positionIndex, position),
        nameIndex: _indexFor(_courseNames, _nameIndex, name),
      ));
    }
  }

  static int _indexFor(
    List<String> list,
    Map<String, int> index,
    String value,
  ) {
    final existing = index[value];
    if (existing != null) return existing;
    final next = list.length;
    list.add(value);
    index[value] = next;
    return next;
  }

  RoomScanData build({
    required String term,
    required String termName,
    required int gradeFrom,
    required int gradeTo,
    String semesterStartDate = '',
  }) {
    return RoomScanData(
      term: term,
      termName: termName,
      scannedAt: DateTime.now(),
      gradeFrom: gradeFrom,
      gradeTo: gradeTo,
      classCount: _classCount,
      semesterStartDate: semesterStartDate,
      positions: List.unmodifiable(_positions),
      courseNames: List.unmodifiable(_courseNames),
      lessons: List.unmodifiable(_lessons),
      coarseCount: _coarseCount,
    );
  }
}

/// 解析压缩周次串 "1-8,10-17" → [1..8, 10..17]。
List<int> parseWeeksCompact(String compact) {
  final out = <int>[];
  if (compact.trim().isEmpty) return out;
  for (final part in compact.split(',')) {
    final p = part.trim();
    if (p.isEmpty) continue;
    final range = RegExp(r'^(\d+)-(\d+)$').firstMatch(p);
    if (range != null) {
      final a = int.parse(range.group(1)!);
      final b = int.parse(range.group(2)!);
      if (a > 0 && b >= a) {
        for (var w = a; w <= b; w++) {
          out.add(w);
        }
      }
      continue;
    }
    final n = int.tryParse(p);
    if (n != null && n > 0) out.add(n);
  }
  return out..sort();
}
