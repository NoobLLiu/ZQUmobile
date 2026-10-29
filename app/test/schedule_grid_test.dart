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
