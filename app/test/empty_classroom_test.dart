/// 空教室功能测试：地点解析、教室目录资源、占用判定与数据模型。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zhangshang_yanyuan/models/empty_classroom.dart';
import 'package:zhangshang_yanyuan/pages/empty_classroom_page.dart';
import 'package:zhangshang_yanyuan/services/classroom_directory.dart';
import 'package:zhangshang_yanyuan/services/empty_room_query.dart';
import 'package:flutter/material.dart';

RoomScanData _scanWith(List<(String position, RoomLesson lesson)> items) {
  final builder = RoomScanBuilder();
  final lessons = <Map<String, dynamic>>[];
  var idx = 0;
  for (final (position, lesson) in items) {
    lessons.add({
      'c': idx++,
      'd': lesson.day,
      's': lesson.startSection,
      'e': lesson.endSection,
      'w': lesson.weeks.join(','),
      'p': position,
      'n': '课程$idx',
      if (lesson.day == 0) 'coarse': true,
    });
  }
  builder.addBatch([
    for (var i = 0; i < items.length; i++) {'dm': 'C$i', 'mc': '班级$i'},
  ], lessons);
  return builder.build(
    term: '202601',
    termName: '2026-2027-1',
    gradeFrom: 2021,
    gradeTo: 2026,
  );
}

RoomLesson _lesson({
  int day = 1,
  int s = 1,
  int e = 2,
  List<int> weeks = const [],
  int pos = 0,
  int name = 0,
}) =>
    RoomLesson(
      day: day,
      startSection: s,
      endSection: e,
      weeks: weeks,
      positionIndex: pos,
      nameIndex: name,
    );

void main() {
  group('parseRoomRef 上课地点归一化', () {
    test('常见写法都能解析出楼栋与房间号', () {
      expect(parseRoomRef('1号教学楼101'),
          const RoomRef(building: 1, number: '101'));
      expect(parseRoomRef('1号教学楼 101'),
          const RoomRef(building: 1, number: '101'));
      expect(parseRoomRef('第1教学楼101'),
          const RoomRef(building: 1, number: '101'));
      expect(parseRoomRef('第一教学楼101'),
          const RoomRef(building: 1, number: '101'));
      expect(parseRoomRef('一教101'), const RoomRef(building: 1, number: '101'));
      expect(parseRoomRef('1教101'), const RoomRef(building: 1, number: '101'));
      expect(parseRoomRef('2号教学楼201'),
          const RoomRef(building: 2, number: '201'));
      expect(parseRoomRef('第二教学楼202'),
          const RoomRef(building: 2, number: '202'));
      expect(parseRoomRef('二教203'), const RoomRef(building: 2, number: '203'));
    });

    test('带修饰与空白', () {
      expect(parseRoomRef('1号教学楼101（多媒体）'),
          const RoomRef(building: 1, number: '101'));
      expect(parseRoomRef(' 2号教学楼203 '),
          const RoomRef(building: 2, number: '203'));
    });

    test('非一教二教或无法解析返回 null', () {
      expect(parseRoomRef(''), isNull);
      expect(parseRoomRef('砚湖楼101'), isNull);
      expect(parseRoomRef('实验楼3-201'), isNull);
      expect(parseRoomRef('第一教学楼'), isNull); // 无房间号
      expect(parseRoomRef('教学楼101'), isNull); // 无楼栋标识
    });
  });

  group('parseWeeksCompact', () {
    test('区间与单周混合', () {
      expect(parseWeeksCompact('1-8,10-17'),
          [1, 2, 3, 4, 5, 6, 7, 8, 10, 11, 12, 13, 14, 15, 16, 17]);
      expect(parseWeeksCompact('3'), [3]);
      expect(parseWeeksCompact(''), isEmpty);
      expect(parseWeeksCompact('5,2'), [2, 5]); // 输出已排序
    });
  });

  group('教室目录（内置资源）', () {
    late ClassroomDirectory directory;

    setUpAll(() async {
      directory = await ClassroomDirectory.load();
    });

    test('一教 + 二教共 161 间教室', () {
      expect(directory.rooms.length, 161);
      expect(
        directory.rooms.where((r) => r.building == 1).length,
        90,
      );
      expect(
        directory.rooms.where((r) => r.building == 2).length,
        71,
      );
    });

    test('按楼栋房间号可查到教室', () {
      final room = directory.lookup(1, '101');
      expect(room, isNotNull);
      expect(room!.floor, 1);
      expect(room.type, isNotEmpty);
      expect(directory.contains(1, '101'), isTrue);
      expect(directory.contains(1, '999'), isFalse);
    });

    test('目录按楼栋/楼层/房间号排序', () {
      for (var i = 1; i < directory.rooms.length; i++) {
        final a = directory.rooms[i - 1];
        final b = directory.rooms[i];
        if (a.building != b.building) {
          expect(a.building, lessThan(b.building));
        } else if (a.floor != b.floor) {
          expect(a.floor, lessThan(b.floor));
        } else {
          expect(a.number.compareTo(b.number), lessThanOrEqualTo(0));
        }
      }
    });
  });

  group('空教室判定', () {
    late ClassroomDirectory directory;

    setUpAll(() async {
      directory = await ClassroomDirectory.load();
    });

    test('被占用的教室不算空', () {
      final scan = _scanWith([
        (
          '1号教学楼101',
          _lesson(day: 1, s: 1, e: 2, weeks: [1, 2, 3, 4, 5, 6, 7, 8]),
        ),
      ]);

      final results = findRooms(
        scan: scan,
        directory: directory,
        week: 5,
        day: 1,
        sections: {1, 2},
        building: 1,
      );

      final busy = results.firstWhere((r) => r.room.number == '101');
      expect(busy.isEmpty, isFalse);
      expect(busy.occupancyLabel(null), contains('课程1'));

      final free = results.firstWhere((r) => r.room.number == '102');
      expect(free.isEmpty, isTrue);
    });

    test('周次不匹配则视为空', () {
      final scan = _scanWith([
        ('1号教学楼101', _lesson(day: 1, s: 1, e: 2, weeks: [1, 2, 3])),
      ]);
      final results = findRooms(
        scan: scan,
        directory: directory,
        week: 10, // 不在上课周次里
        day: 1,
        sections: {1, 2},
        building: 1,
      );
      expect(
        results.firstWhere((r) => r.room.number == '101').isEmpty,
        isTrue,
      );
    });

    test('星期未知（d=0）保守视为占用所有星期', () {
      final scan = _scanWith([
        ('2号教学楼201', _lesson(day: 0, s: 1, e: 14, weeks: [1, 2, 3])),
      ]);
      final results = findRooms(
        scan: scan,
        directory: directory,
        week: 2,
        day: 6, // 周六
        sections: {8},
        building: 2,
      );
      expect(
        results.firstWhere((r) => r.room.number == '201').isEmpty,
        isFalse,
      );
    });

    test('节次集合乱序传入也能正确判定交集', () {
      final scan = _scanWith([
        ('1号教学楼101', _lesson(day: 1, s: 3, e: 4, weeks: [1, 2])),
      ]);
      final results = findRooms(
        scan: scan,
        directory: directory,
        week: 1,
        day: 1,
        sections: {5, 1, 3}, // 乱序，且与 3-4 有交集
        building: 1,
      );
      expect(
        results.firstWhere((r) => r.room.number == '101').isEmpty,
        isFalse,
      );
    });

    test('非一教二教的地点不参与判定', () {
      final scan = _scanWith([
        ('图书馆报告厅', _lesson(day: 1, s: 1, e: 2, weeks: [1])),
      ]);
      final results = findRooms(
        scan: scan,
        directory: directory,
        week: 1,
        day: 1,
        sections: {1, 2},
      );
      expect(results.every((r) => r.isEmpty), isTrue);
    });

    test('空教室排在前面', () {
      final scan = _scanWith([
        ('1号教学楼101', _lesson(day: 1, s: 1, e: 2, weeks: [1])),
      ]);
      final results = findRooms(
        scan: scan,
        directory: directory,
        week: 1,
        day: 1,
        sections: {1, 2},
        building: 1,
      );
      expect(results.first.isEmpty, isTrue);
      expect(results.last.isEmpty, isFalse);
      expect(results.last.room.number, '101');
    });

    test('daySchedule 返回某教室某天的全部排课并按节次排序', () {
      final scan = _scanWith([
        ('1号教学楼101', _lesson(day: 1, s: 3, e: 4, weeks: [1])),
        ('1号教学楼101', _lesson(day: 1, s: 1, e: 2, weeks: [2])),
        ('1号教学楼101', _lesson(day: 2, s: 5, e: 6, weeks: [1])),
        ('1号教学楼102', _lesson(day: 1, s: 7, e: 8, weeks: [1])),
      ]);
      final lessons = daySchedule(
        scan: scan,
        directory: directory,
        ref: const RoomRef(building: 1, number: '101'),
        day: 1,
      );
      expect(lessons.length, 2);
      expect(lessons[0].startSection, 1); // 已排序
      expect(lessons[0].weeks, [2]);
      expect(lessons[1].startSection, 3);
    });

    test('weeksLabel 连续周合并展示', () {
      expect(weeksLabel([1, 2, 3, 4]), '1-4周');
      expect(weeksLabel([1, 2, 3, 4, 10]), '1-4,10周');
      expect(weeksLabel([5]), '5周');
      expect(weeksLabel([]), '');
    });
  });

  group('扫描数据模型', () {
    test('RoomScanData JSON 往返', () {
      final data = _scanWith([
        ('1号教学楼101', _lesson(day: 1, s: 1, e: 2, weeks: [1, 2])),
        ('2号教学楼201', _lesson(day: 0, s: 1, e: 14, weeks: [3])),
      ]);
      final restored = RoomScanData.fromJson({
        ...data.toJson(),
        'semesterStartDate': '2026-08-31',
      });
      expect(restored.term, '202601');
      expect(restored.termName, '2026-2027-1');
      expect(restored.gradeFrom, 2021);
      expect(restored.gradeTo, 2026);
      expect(restored.classCount, 2);
      expect(restored.semesterStartDate, '2026-08-31');
      expect(restored.lessons.length, 2);
      expect(restored.positions, ['1号教学楼101', '2号教学楼201']);
      expect(restored.lessons.first.day, 1);
      expect(restored.lessons.last.day, 0);
    });

    test('weekOf 用扫描自带的开学日期推算周次', () {
      final data = RoomScanData.fromJson({
        ..._scanWith([]).toJson(),
        'semesterStartDate': '2026-08-31', // 周一
      });
      // 开学当天是第 1 周；一周后是第 2 周；往前往后超出范围返回 null
      expect(data.weekOf(DateTime(2026, 8, 31)), 1);
      expect(data.weekOf(DateTime(2026, 9, 6)), 1);
      expect(data.weekOf(DateTime(2026, 9, 7)), 2);
      expect(data.weekOf(DateTime(2026, 8, 30)), isNull);
      expect(
        RoomScanData.fromJson(_scanWith([]).toJson()).weekOf(DateTime(2026, 9, 1)),
        isNull,
      );
    });

    test('构建器对地点与课程名去重', () {
      final builder = RoomScanBuilder();
      builder.addBatch([
        {'dm': 'C1', 'mc': '法学1班'},
      ], [
        {'c': 0, 'd': 1, 's': 1, 'e': 2, 'w': '1-8', 'p': '1号教学楼101', 'n': '法学'},
        {'c': 0, 'd': 3, 's': 3, 'e': 4, 'w': '1-8', 'p': '1号教学楼101', 'n': '法学'},
      ]);
      final data = builder.build(
        term: '202601',
        termName: '2026-2027-1',
        gradeFrom: 2021,
        gradeTo: 2026,
        semesterStartDate: '2026-08-31',
      );
      expect(data.positions.length, 1);
      expect(data.courseNames.length, 1);
      expect(data.lessons.length, 2);
      expect(data.semesterStartDate, '2026-08-31');
      expect(data.lessons[0].positionIndex, 0);
      expect(data.lessons[1].positionIndex, 0);
    });

    test('构建器跳过下标越界的排课记录', () {
      final builder = RoomScanBuilder();
      builder.addBatch(
        [],
        [
          {'c': 5, 'd': 1, 's': 1, 'e': 2, 'w': '1', 'p': '1号教学楼101', 'n': 'x'},
        ],
      );
      expect(builder.lessonCount, 0);
    });
  });

  group('空教室页面', () {
    testWidgets('无扫描数据时显示引导卡', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(const MaterialApp(home: EmptyClassroomPage()));
      await tester.pumpAndSettle();

      expect(find.text('还没有教室数据'), findsOneWidget);
      expect(find.text('去扫描教室数据'), findsOneWidget);
      // 无数据时不渲染查询按钮（引导用户先扫描）
      expect(find.text('查询空教室'), findsNothing);
    });
  });
}
