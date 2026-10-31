/// 课表网格渲染的回归测试：验证有数据时能被画出来。
///
/// 背景：用户反馈「导入成功 13 门课，但课表页全空」。
/// 这里用与真实导入同构的数据直接渲染网格，确认渲染层没问题。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zhangshang_yanyuan/models/timetable.dart';
import 'package:zhangshang_yanyuan/services/timetable_repository.dart';
import 'package:zhangshang_yanyuan/widgets/schedule_grid.dart';

List<TimeSlot> _slots() => List.generate(
      14,
      (i) => TimeSlot(
        number: i + 1,
        startTime: '08:00',
        endTime: '08:40',
      ),
    );

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('本周有课时，课程名应被渲染出来', (tester) async {
    final courses = [
      Course(
        name: '高等数学',
        teacher: '张老师',
        position: 'A101',
        day: 1,
        startSection: 1,
        endSection: 2,
        weeks: [9, 10, 11],
      ),
      Course(
        name: '大学英语',
        teacher: '李老师',
        position: 'B202',
        day: 3,
        startSection: 3,
        endSection: 4,
        weeks: [9],
      ),
    ];

    await tester.pumpWidget(_wrap(
      ScheduleGrid(
        courses: courses,
        week: 9,
        totalWeeks: 18,
        timeSlots: _slots(),
        semesterStartDate: '2026-08-31',
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('高等数学'), findsOneWidget);
    expect(find.text('大学英语'), findsOneWidget);
  });

  testWidgets('本周没课但学期内有课时，应灰化展示而非消失', (tester) async {
    final courses = [
      Course(
        name: '线性代数',
        teacher: '王老师',
        position: 'C303',
        day: 2,
        startSection: 5,
        endSection: 6,
        weeks: [1, 2, 3],
      ),
    ];

    await tester.pumpWidget(_wrap(
      ScheduleGrid(
        courses: courses,
        week: 9,
        totalWeeks: 18,
        timeSlots: _slots(),
        semesterStartDate: '2026-08-31',
      ),
    ));
    await tester.pumpAndSettle();

    // 非本周课程仍应占位显示（灰化）
    expect(find.text('线性代数'), findsOneWidget);
  });

  test('经仓库保存再读取后，课程与周次都还在', () async {
    SharedPreferences.setMockInitialValues({});
    await TimetableRepository.clear();

    final tt = Timetable(
      term: '202601',
      termName: '2026-2027-1',
      totalWeeks: 18,
      semesterStartDate: '2026-08-31',
      courses: [
        Course(
          name: '高等数学',
          teacher: '张老师',
          position: 'A101',
          day: 1,
          startSection: 1,
          endSection: 2,
          weeks: [1, 2, 3, 9],
        ),
      ],
      timeSlots: _slots(),
    );

    await TimetableRepository.save(tt);
    final loaded = await TimetableRepository.load();

    expect(loaded, isNotNull);
    expect(loaded!.courses.length, 1);
    expect(loaded.courses.first.weeks, [1, 2, 3, 9]);
    expect(loaded.totalWeeks, 18);
    expect(loaded.semesterStartDate, '2026-08-31');
  });

  testWidgets('同一时段保留两门课时，两门课并排显示且位置不重叠', (tester) async {
    final courses = [
      Course(
        name: '高等数学',
        teacher: '张老师',
        position: 'A101',
        day: 1,
        startSection: 1,
        endSection: 2,
        weeks: [9, 10, 11],
      ),
      Course(
        name: '大学物理',
        teacher: '李老师',
        position: 'B202',
        day: 1,
        startSection: 1,
        endSection: 2,
        weeks: [9, 10, 11],
      ),
    ];

    await tester.pumpWidget(_wrap(
      ScheduleGrid(
        courses: courses,
        week: 9,
        totalWeeks: 18,
        timeSlots: _slots(),
        semesterStartDate: '2026-08-31',
      ),
    ));
    await tester.pumpAndSettle();

    // 两门课都要渲染出来
    expect(find.text('高等数学'), findsOneWidget);
    expect(find.text('大学物理'), findsOneWidget);

    // 且水平位置错开（并排），不能叠在同一处互相遮挡
    final rectA = tester.getRect(find.text('高等数学'));
    final rectB = tester.getRect(find.text('大学物理'));
    expect(rectA.left, isNot(closeTo(rectB.left, 1.0)));
  });

  testWidgets('起止节次不同但区间重叠时，两门课也并排显示', (tester) async {
    final courses = [
      Course(
        name: '高等数学',
        teacher: '张老师',
        position: 'A101',
        day: 1,
        startSection: 1,
        endSection: 2,
        weeks: [9, 10, 11],
      ),
      Course(
        name: '大学物理',
        teacher: '李老师',
        position: 'B202',
        day: 1,
        startSection: 2,
        endSection: 3,
        weeks: [9, 10, 11],
      ),
    ];

    await tester.pumpWidget(_wrap(
      ScheduleGrid(
        courses: courses,
        week: 9,
        totalWeeks: 18,
        timeSlots: _slots(),
        semesterStartDate: '2026-08-31',
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('高等数学'), findsOneWidget);
    expect(find.text('大学物理'), findsOneWidget);

    // 部分重叠（共享第 2 节）也应分道并排，而不是叠在一起
    final rectA = tester.getRect(find.text('高等数学'));
    final rectB = tester.getRect(find.text('大学物理'));
    expect(rectA.left, isNot(closeTo(rectB.left, 1.0)));
  });

  testWidgets('节次相邻但不重叠时，两门课共享同一列（都应全宽）', (tester) async {
    final courses = [
      Course(
        name: '高等数学',
        teacher: '张老师',
        position: 'A101',
        day: 1,
        startSection: 1,
        endSection: 2,
        weeks: [9, 10, 11],
      ),
      Course(
        name: '大学物理',
        teacher: '李老师',
        position: 'B202',
        day: 1,
        startSection: 3,
        endSection: 4,
        weeks: [9, 10, 11],
      ),
    ];

    await tester.pumpWidget(_wrap(
      ScheduleGrid(
        courses: courses,
        week: 9,
        totalWeeks: 18,
        timeSlots: _slots(),
        semesterStartDate: '2026-08-31',
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('高等数学'), findsOneWidget);
    expect(find.text('大学物理'), findsOneWidget);

    // 不重叠的两门课不需要分道，左边界应一致（各自占满整列）
    final rectA = tester.getRect(find.text('高等数学'));
    final rectB = tester.getRect(find.text('大学物理'));
    expect(rectA.left, closeTo(rectB.left, 1.0));
  });

  testWidgets('隐藏周末时周六课程不渲染，显示周末时渲染', (tester) async {
    final courses = [
      Course(
        name: '周末选修',
        teacher: '赵老师',
        position: 'D404',
        day: 6,
        startSection: 1,
        endSection: 2,
        weeks: [9],
      ),
    ];

    // 隐藏周末
    await tester.pumpWidget(_wrap(
      ScheduleGrid(
        courses: courses,
        week: 9,
        totalWeeks: 18,
        timeSlots: _slots(),
        semesterStartDate: '2026-08-31',
        showWeekends: false,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('周末选修'), findsNothing);
    expect(find.text('周六'), findsNothing);

    // 显示周末
    await tester.pumpWidget(_wrap(
      ScheduleGrid(
        courses: courses,
        week: 9,
        totalWeeks: 18,
        timeSlots: _slots(),
        semesterStartDate: '2026-08-31',
        showWeekends: true,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('周末选修'), findsOneWidget);
    expect(find.text('周六'), findsOneWidget);
  });

  group('findCourseConflicts 冲突检测', () {
    Course c(String name, int day, int s, int e, List<int> weeks) => Course(
          name: name,
          teacher: '',
          position: '',
          day: day,
          startSection: s,
          endSection: e,
          weeks: weeks,
        );

    test('节次重叠且周次有交集 → 判为冲突', () {
      final conflicts = findCourseConflicts([
        c('高等数学', 1, 1, 2, [1, 2, 3]),
        c('大学物理', 1, 2, 3, [3, 4, 5]),
      ]);
      expect(conflicts.length, 1);
      expect(conflicts.first.courses.length, 2);
    });

    test('节次重叠但周次无交集 → 不算冲突', () {
      final conflicts = findCourseConflicts([
        c('高等数学', 1, 1, 2, [1, 2]),
        c('大学物理', 1, 1, 2, [5, 6]),
      ]);
      expect(conflicts, isEmpty);
    });

    test('不同星期几 → 不算冲突', () {
      final conflicts = findCourseConflicts([
        c('高等数学', 1, 1, 2, [1, 2, 3]),
        c('大学物理', 2, 1, 2, [1, 2, 3]),
      ]);
      expect(conflicts, isEmpty);
    });
  });

  test('课表 JSON 往返不丢课程', () {
    final tt = Timetable(
      term: '202601',
      termName: '2026-2027-1',
      totalWeeks: 18,
      semesterStartDate: '2026-08-31',
      courses: [
        Course(
          name: '高等数学',
          teacher: '张老师',
          position: 'A101',
          day: 1,
          startSection: 1,
          endSection: 2,
          weeks: [1, 2, 9],
        ),
      ],
      timeSlots: _slots(),
    );

    final restored = Timetable.fromJson(tt.toJson());
    expect(restored.courses.length, 1);
    expect(restored.courses.first.name, '高等数学');
    expect(restored.courses.first.weeks, [1, 2, 9]);
    expect(restored.courses.first.day, 1);
    expect(restored.courses.first.startSection, 1);
    expect(restored.courses.first.endSection, 2);
  });
}
