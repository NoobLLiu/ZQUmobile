/// 拾光风格的课表网格。
///
/// 视觉与交互对齐拾光课表（Apache-2.0）的 ScheduleGrid / CourseBlock：
/// - 布局：左列节次轴（40dp）+ 每天等宽列，表头 45dp、每节 70dp
/// - 课程卡：柔和纯色底 + 深色字，课程名加粗自动换行，教师与地点（@前缀）固定在底部
/// - 连堂课按节数跨行占格
/// - 非本周的课程灰化，并叠加斜纹遮罩
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/grid_style.dart';
import '../models/timetable.dart';

/// 课表网格。
class ScheduleGrid extends StatelessWidget {
  const ScheduleGrid({
    super.key,
    required this.courses,
    required this.week,
    required this.totalWeeks,
    required this.timeSlots,
    required this.semesterStartDate,
    this.onCourseTap,
    this.showWeekends = true,
  });

  /// 该学期的全部课程。
  final List<Course> courses;

  /// 当前显示的周次。
  final int week;

  /// 学期总周数。
  final int totalWeeks;

  /// 作息时间表。
  final List<TimeSlot> timeSlots;

  /// 学期第 1 周的周一日期。
  final String semesterStartDate;

  /// 点击课程回调。
  final void Function(Course course)? onCourseTap;

  /// 是否显示周末。
  final bool showWeekends;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // 网格几何常量（拾光默认值）
    const style = ScheduleGridStyle.defaultStyle;
    final leftW = style.timeColumnWidth;
    final headerH = style.dayHeaderHeight;
    final rowH = style.sectionHeight;

    final displayDays = showWeekends ? 7 : 5;
    final maxSection = math.max(
      8,
      timeSlots.isEmpty
          ? 8
          : timeSlots
              .map((t) => t.number)
              .reduce((a, b) => a > b ? a : b),
    );

    // 当周日期
    final dates = _datesOfWeek(week);

    // 本周有课的记录 + 冲突分列
    final blocks = _buildBlocks(week, displayDays);

    return LayoutBuilder(builder: (context, constraints) {
      // 每天列宽：按可用宽度**精确等分**，保证整张表刚好铺满屏幕。
      // 之前强制最小 56 会导致 7 列时总宽超出屏幕，周日被裁掉一半。
      final availW = constraints.maxWidth - leftW;
      final colW = math.max(38.0, availW / displayDays);
      final gridW = leftW + colW * displayDays;
      final gridH = maxSection * rowH;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 表头：左列显示当前周次，每天显示星期 + 日期
          _DayHeader(
            leftW: leftW,
            colW: colW,
            headerH: headerH,
            displayDays: displayDays,
            dates: dates,
            week: week,
            totalWeeks: totalWeeks,
            theme: theme,
            isDark: isDark,
          ),
          Expanded(
            child: SingleChildScrollView(
              child: SizedBox(
                width: gridW,
                height: gridH,
                child: Stack(
                  children: [
                    // 背景网格线
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _GridPainter(
                          leftW: leftW,
                          colW: colW,
                          rowH: rowH,
                          rows: maxSection,
                          displayDays: displayDays,
                          color: theme.dividerColor.withValues(alpha: 0.35),
                        ),
                      ),
                    ),
                    // 左侧节次列
                    for (var p = 1; p <= maxSection; p++)
                      Positioned(
                        left: 0,
                        top: (p - 1) * rowH,
                        width: leftW,
                        height: rowH,
                        child: _TimeCell(
                          slot: timeSlots
                              .where((t) => t.number == p)
                              .cast<TimeSlot?>()
                              .firstWhere((_) => true, orElse: () => null),
                          theme: theme,
                        ),
                      ),
                    // 课程卡片
                    for (final b in blocks)
                      Positioned(
                        left: leftW + (b.displayColumn) * colW +
                            style.blockOuterPadding,
                        top: (b.startSection - 1) * rowH + style.blockOuterPadding,
                        width: colW * b.subColumnWidthFactor -
                            style.blockOuterPadding * 2,
                        height: (b.endSection - b.startSection + 1) * rowH -
                            style.blockOuterPadding * 2,
                        child: _CourseBlockWidget(
                          course: b.course,
                          demoted: b.isVisualDemoted,
                          style: style,
                          isDark: isDark,
                          onTap: onCourseTap,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    });
  }

  /// 计算某一周的日期（索引 0 = 周一）。
  List<DateTime> _datesOfWeek(int week) {
    final start = DateTime.tryParse(semesterStartDate);
    if (start == null) return const [];
    final monday = DateTime(start.year, start.month, start.day);
    final first = monday.add(Duration(days: (week - 1) * 7));
    return List.generate(7, (i) => first.add(Duration(days: i)));
  }

  /// 构建该周的展示块，处理同一格多门课的并排显示。
  List<_GridBlock> _buildBlocks(int week, int displayDays) {
    final active = <Course>[];
    final demoted = <Course>[];

    for (final c in courses) {
      // 坐标非法会导致块被画到网格外（看起来就像“课程消失”），先剔除
      if (c.day < 1 || c.day > 7) continue;
      // 隐藏周末时，周六日的课程不参与布局
      if (c.day > displayDays) continue;
      if (c.startSection < 1) continue;
      final end = c.endSection < c.startSection ? c.startSection : c.endSection;

      // 周次为空的课程无法判断属于哪一周，按“本学期有效”处理，
      // 否则既不算本周有课、也不算非本周，会整条凭空消失
      if (c.weeks.isEmpty) {
        active.add(c.copyWith(endSection: end));
        continue;
      }

      if (c.isActiveInWeek(week)) {
        active.add(c.copyWith(endSection: end));
      } else {
        demoted.add(c.copyWith(endSection: end));
      }
    }

    final result = <_GridBlock>[];

    // 先按 (星期, 起始节) 分组，检测冲突
    final groups = <String, List<Course>>{};
    for (final c in active) {
      final key = '${c.day}_${c.startSection}';
      groups.putIfAbsent(key, () => []).add(c);
    }

    for (final entry in groups.entries) {
      final list = entry.value;
      if (list.length == 1) {
        result.add(_GridBlock(course: list.first, subColumnIndex: 0, subColumnCount: 1));
      } else {
        // 冲突：同一格内均分宽度
        for (var i = 0; i < list.length; i++) {
          result.add(_GridBlock(
            course: list[i],
            subColumnIndex: i,
            subColumnCount: list.length,
          ));
        }
      }
    }

    // 灰化课程只在同格无其他课时显示，避免遮挡
    final activeKeys = groups.keys.toSet();
    for (final c in demoted) {
      final key = '${c.day}_${c.startSection}';
      if (activeKeys.contains(key)) continue;
      result.add(_GridBlock(course: c, subColumnIndex: 0, subColumnCount: 1, isVisualDemoted: true));
    }

    return result;
  }
}

/// 网格中一个展示块。
class _GridBlock {
  _GridBlock({
    required this.course,
    required this.subColumnIndex,
    required this.subColumnCount,
    this.isVisualDemoted = false,
  });

  final Course course;
  final int subColumnIndex;
  final int subColumnCount;
  final bool isVisualDemoted;

  /// 在网格中的显示列（0-based）。
  int get displayColumn => course.day - 1;

  /// 起始节次。
  int get startSection => course.startSection;

  /// 结束节次。
  int get endSection => course.endSection;

  /// 占宽度比例。
  double get subColumnWidthFactor => 1 / subColumnCount;
}

/// 表头组件。
class _DayHeader extends StatelessWidget {
  const _DayHeader({
    required this.leftW,
    required this.colW,
    required this.headerH,
    required this.displayDays,
    required this.dates,
    required this.week,
    required this.totalWeeks,
    required this.theme,
    required this.isDark,
  });

  final double leftW;
  final double colW;
  final double headerH;
  final int displayDays;
  final List<DateTime> dates;
  final int week;
  final int totalWeeks;
  final ThemeData theme;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final lineColor = theme.dividerColor.withValues(alpha: 0.35);
    final today = DateTime.now();
    final todayIndex = dates.indexWhere((d) =>
        d.year == today.year && d.month == today.month && d.day == today.day);

    return Container(
      height: headerH,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: lineColor, width: 0.5)),
      ),
      child: Row(
        children: [
          // 左上角：当前周次
          Container(
            width: leftW,
            height: headerH,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: lineColor, width: 0.5)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '第$week周',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '共$totalWeeks周',
                  style: TextStyle(fontSize: 9, color: theme.colorScheme.outline),
                ),
              ],
            ),
          ),
          for (var i = 0; i < displayDays; i++)
            Container(
              width: colW,
              height: headerH,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: i == todayIndex
                    ? theme.colorScheme.primaryContainer.withValues(alpha: 0.4)
                    : null,
                border: Border(right: BorderSide(color: lineColor, width: 0.5)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '周${_weekdayCn(i + 1)}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  if (i < dates.length)
                    Text(
                      _fmtDate(dates[i]),
                      style: TextStyle(fontSize: 10, color: theme.colorScheme.outline, height: 1.2),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _weekdayCn(int d) => const ['一', '二', '三', '四', '五', '六', '日'][d - 1];

  static String _fmtDate(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// 左侧节次单元格。
class _TimeCell extends StatelessWidget {
  const _TimeCell({required this.slot, required this.theme});

  final TimeSlot? slot;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final s = slot;
    if (s == null) {
      return Center(
        child: Text('',
            style: TextStyle(fontSize: 11, color: theme.colorScheme.outline)),
      );
    }
    // 拾光默认：节高足够时显示「节号 + 开始时间 + 结束时间」两行
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            s.alias ?? '${s.number}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            s.startTime,
            style: TextStyle(fontSize: 10, color: theme.colorScheme.outline, height: 1),
          ),
          Text(
            s.endTime,
            style: TextStyle(fontSize: 10, color: theme.colorScheme.outline, height: 1),
          ),
        ],
      ),
    );
  }
}

/// 课程卡片。
class _CourseBlockWidget extends StatelessWidget {
  const _CourseBlockWidget({
    required this.course,
    required this.demoted,
    required this.style,
    required this.isDark,
    this.onTap,
  });

  final Course course;
  final bool demoted;
  final ScheduleGridStyle style;
  final bool isDark;
  final void Function(Course course)? onTap;

  @override
  Widget build(BuildContext context) {
    final colorIndex = course.colorIndex ??
        _hashIndex(course.name, kDefaultColorMaps.length);
    final pair = kDefaultColorMaps[colorIndex % kDefaultColorMaps.length];
    final bg = Color(isDark ? pair.dark : pair.light);
    final fg = Color(isDark ? 0xFFFFFFFF : 0xFF1F1F1F);

    return GestureDetector(
      onTap: onTap == null ? null : () => onTap!(course),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(style.blockCornerRadius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: bg.withValues(alpha: style.blockAlpha)),
            Padding(
              padding: const EdgeInsets.all(4),
              child: LayoutBuilder(builder: (context, box) {
                // 按可用高度决定各段能排几行，尽量不截断、全部靠左对齐。
                // 密度规则：
                //   矮卡片（单节课）：课程名 2 行，不显示教师/地点
                //   中等卡片：课程名 + 教师/地点各 2 行
                //   高卡片（连堂）：课程名优先，信息行按剩余空间给
                final h = box.maxHeight;
                final w = box.maxWidth;
                final nameFont = w >= 84 ? 13.0 : (w >= 64 ? 12.0 : 11.0);
                final infoFont = w >= 84 ? 10.5 : 10.0;
                final nameLineH = nameFont * 1.2;
                final infoLineH = infoFont * 1.25;

                final compact = h < 56;
                final showInfo = !compact && h >= 72;

                // 给信息留出的行数：空间越富余给得越多
                final infoLines = compact
                    ? 0
                    : (h >= 150 ? 2 : (h >= 110 ? 2 : 1));

                final infoH = infoLines * infoLineH * 2; // 教师 + 地点
                final nameSpace = h - (showInfo ? infoH : 0);
                final nameLines = math.max(1, (nameSpace / nameLineH).floor())
                    .clamp(1, 6);

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    // 课程名：多行、靠左、自动换行
                    Flexible(
                      child: Text(
                        course.name,
                        softWrap: true,
                        maxLines: nameLines,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.left,
                        style: TextStyle(
                          fontSize: nameFont,
                          fontWeight: FontWeight.bold,
                          height: 1.2,
                          color: fg,
                        ),
                      ),
                    ),
                    if (showInfo) ...[
                      if (course.teacher.isNotEmpty)
                        Text(
                          course.teacher,
                          softWrap: true,
                          maxLines: infoLines,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.left,
                          style: TextStyle(
                            fontSize: infoFont,
                            height: 1.25,
                            color: fg.withValues(alpha: 0.82),
                          ),
                        ),
                      if (course.position.isNotEmpty)
                        Text(
                          '@${course.position}',
                          softWrap: true,
                          maxLines: infoLines,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.left,
                          style: TextStyle(
                            fontSize: infoFont,
                            height: 1.25,
                            color: fg,
                          ),
                        ),
                    ],
                  ],
                );
              }),
            ),
            // 非本周课程：灰化 + 斜纹遮罩（对齐拾光的 isVisualDemoted 处理）
            if (demoted)
              Container(
                color: (isDark ? Colors.black : Colors.white).withValues(alpha: 0.618),
                foregroundDecoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      (isDark ? Colors.white : Colors.black).withValues(alpha: 0.06),
                      (isDark ? Colors.white : Colors.black).withValues(alpha: 0.06),
                      Colors.transparent,
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.45, 0.55, 1.0],
                    tileMode: TileMode.repeated,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 按课程名散列取色，保证同一课程每周同色。
  static int _hashIndex(String name, int length) {
    if (length <= 0) return 0;
    var h = 0;
    for (final rune in name.codeUnits) {
      h = (h * 31 + rune) & 0x7fffffff;
    }
    return h % length;
  }
}

/// 网格背景线绘制。
class _GridPainter extends CustomPainter {
  _GridPainter({
    required this.leftW,
    required this.colW,
    required this.rowH,
    required this.rows,
    required this.displayDays,
    required this.color,
  });

  final double leftW;
  final double colW;
  final double rowH;
  final int rows;
  final int displayDays;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 0.5;

    // 横线（每节一行）
    for (var r = 0; r <= rows; r++) {
      final y = r * rowH;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    // 竖线（左列 + 各天）
    for (var c = 0; c <= displayDays; c++) {
      final x = c == 0 ? 0.0 : leftW + (c - 1) * colW;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) =>
      old.rows != rows ||
      old.rowH != rowH ||
      old.colW != colW ||
      old.displayDays != displayDays ||
      old.color != color;
}
