/// 空教室查询逻辑（纯函数，便于单测）。
///
/// 判定规则：
///   教务系统上课地点写法不统一（"1号教学楼101"、"第一教学楼101"、"一教101"），
///   先归一化成「楼栋 + 房间号」，再与内置教室目录比对；
///   教室在所选 (周次, 星期, 节次) 内没有任何排课记录即视为空教室。
///
/// 保守策略（扫描数据不完整时宁可少报空教室，不误报）：
///   - 星期未知（d=0）的排课记录视为占用所有星期；
///   - 节次未知的排课记录按整 day 占用处理；
///   - 周次未知的排课记录按整学期占用处理（扫描脚本已按此回传）。
library;

import '../models/empty_classroom.dart';
import 'classroom_directory.dart';

/// 归一化后的教室引用。
class RoomRef {
  const RoomRef({required this.building, required this.number});

  /// 1=第一教学楼，2=第二教学楼。
  final int building;

  /// 房间编号，如 "101"。
  final String number;

  @override
  bool operator ==(Object other) =>
      other is RoomRef && other.building == building && other.number == number;

  @override
  int get hashCode => Object.hash(building, number);
}

/// 从上课地点文本中解析楼栋与房间号；不属于一教/二教或解析不出返回 null。
///
/// 兼容写法（实测教务系统地点字段）：
///   "1号教学楼101" / "1号教学楼 101" / "第1教学楼101"
///   "第一教学楼101" / "一教101" / "1教101"
///   "2号教学楼201" / "第二教学楼202" / "二教203"
///   末尾可能带 "（多媒体）" 等修饰。
RoomRef? parseRoomRef(String location) {
  final text = location.trim();
  if (text.isEmpty) return null;

  // 楼栋：数字或中文写法
  final buildingMatch = RegExp(
    r'([12])\s*号教学楼|第\s*([12一二])\s*教学楼|第\s*([一二])\s*教学楼|([12一二])\s*教(?!学)',
  ).firstMatch(text);
  if (buildingMatch == null) return null;
  final buildingOpt = _buildingOf(
    buildingMatch.group(1),
    buildingMatch.group(2),
    buildingMatch.group(3),
    buildingMatch.group(4),
  );
  if (buildingOpt == null || (buildingOpt != 1 && buildingOpt != 2)) {
    return null;
  }
  final building = buildingOpt;

  // 房间号：楼栋片段之后的第一段 3~4 位数字
  final rest = text.substring(buildingMatch.end);
  final numberMatch = RegExp(r'(\d{3,4})').firstMatch(rest);
  if (numberMatch == null) return null;
  return RoomRef(building: building, number: numberMatch.group(1)!);
}

/// 楼栋分组里无论哪个分组命中，都从中提取楼栋号。
int? _buildingOf(String? g1, String? g2, String? g3, String? g4) {
  for (final g in [g1, g2, g3, g4]) {
    if (g == null || g.isEmpty) continue;
    final digit = _digitOf(g);
    if (digit != null) return digit;
    final cn = _cnDigitOf(g);
    if (cn != null) return cn;
  }
  return null;
}

int? _digitOf(String? s) {
  if (s == null || s.isEmpty) return null;
  final c = s.codeUnitAt(0);
  if (c >= 0x30 && c <= 0x39) return c - 0x30;
  return null;
}

int? _cnDigitOf(String? s) {
  if (s == null || s.isEmpty) return null;
  switch (s[0]) {
    case '一':
      return 1;
    case '二':
      return 2;
    default:
      return null;
  }
}

/// 一间教室的查询结果。
class RoomQueryResult {
  const RoomQueryResult({
    required this.room,
    this.occupiedLessons = const [],
    this.courseNames = const [],
  });

  final Classroom room;

  /// 与查询条件冲突的排课记录（空教室该列表为空）。
  final List<RoomLesson> occupiedLessons;

  /// 课程名表（配合 [RoomLesson.nameIndex] 取占用课程名）。
  final List<String> courseNames;

  bool get isEmpty => occupiedLessons.isEmpty;

  /// 占用摘要，如 "高等数学（第1-2节）"；无占用返回 null。
  String? occupancyLabel(String Function(RoomLesson)? describe) {
    if (occupiedLessons.isEmpty) return null;
    final first = occupiedLessons.first;
    if (describe != null) return describe(first);
    final course = first.nameIndex >= 0 && first.nameIndex < courseNames.length
        ? courseNames[first.nameIndex]
        : '';
    final section = first.startSection == first.endSection
        ? '第${first.startSection}节'
        : '第${first.startSection}-${first.endSection}节';
    return course.isEmpty ? section : '$course（$section）';
  }
}

/// 排课占用索引：把扫描数据按教室聚合，供快速判定。
class RoomOccupancyIndex {
  /// 构建索引；不在教室目录内（非一教/二教或房间号对不上）的记录忽略。
  RoomOccupancyIndex(RoomScanData scan, ClassroomDirectory directory) {
    for (final lesson in scan.lessons) {
      if (lesson.positionIndex < 0 ||
          lesson.positionIndex >= scan.positions.length) {
        continue;
      }
      final ref = parseRoomRef(scan.positions[lesson.positionIndex]);
      if (ref == null) continue;
      if (!directory.contains(ref.building, ref.number)) continue;
      _byRoom.putIfAbsent(ref, () => <RoomLesson>[]).add(lesson);
    }
  }

  final Map<RoomRef, List<RoomLesson>> _byRoom = {};

  /// 命中索引的教室数（调试/展示用）。
  int get roomCount => _byRoom.length;

  /// 某教室在 (week, day) 的、与 [sections] 有交集的排课记录。
  List<RoomLesson> occupiedBy(
    RoomRef ref,
    int week,
    int day,
    Set<int> sections,
  ) {
    final lessons = _byRoom[ref];
    if (lessons == null || sections.isEmpty) return const [];
    // Set 迭代序不保证有序，显式取最小/最大节次
    var minSection = 0x7fffffff;
    var maxSection = 0;
    for (final s in sections) {
      if (s < minSection) minSection = s;
      if (s > maxSection) maxSection = s;
    }
    return lessons.where((l) {
      if (l.weeks.isNotEmpty && !l.weeks.contains(week)) return false;
      // day == 0 表示星期未知：保守视为占用
      if (l.day != 0 && l.day != day) return false;
      return l.endSection >= minSection && l.startSection <= maxSection;
    }).toList();
  }
}

/// 查询空教室。
///
/// 返回目录里 [building]（null=全部楼栋）的所有教室，空教室在前，
/// 被占用教室携带占用信息附在后面（调用方决定是否展示）。
List<RoomQueryResult> findRooms({
  required RoomScanData scan,
  required ClassroomDirectory directory,
  required int week,
  required int day,
  required Set<int> sections,
  int? building,
}) {
  assert(sections.isNotEmpty, '节次不能为空');
  final index = RoomOccupancyIndex(scan, directory);
  final results = <RoomQueryResult>[];
  for (final room in directory.rooms) {
    if (building != null && room.building != building) continue;
    final ref = RoomRef(building: room.building, number: room.number);
    final occupied = index.occupiedBy(ref, week, day, sections);
    results.add(RoomQueryResult(
      room: room,
      occupiedLessons: occupied,
      courseNames: scan.courseNames,
    ));
  }
  final empty = results.where((r) => r.isEmpty).toList();
  final busy = results.where((r) => !r.isEmpty).toList();
  return [...empty, ...busy];
}
