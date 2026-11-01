/// 附属日程（晚自习 / 阳光体育）模型、存储与页面测试。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zhangshang_yanyuan/main.dart';
import 'package:zhangshang_yanyuan/models/attachment_schedule.dart';
import 'package:zhangshang_yanyuan/models/timetable.dart';
import 'package:zhangshang_yanyuan/pages/attachment_schedule_page.dart';
import 'package:zhangshang_yanyuan/services/attachment_schedule_repository.dart';
import 'package:zhangshang_yanyuan/services/timetable_repository.dart';

AttachmentSchedule _schedule({
  String id = 's1',
  AttachmentScheduleType type = AttachmentScheduleType.eveningStudy,
  String title = '图书馆晚自习',
  List<int> weekdays = const [1, 2, 3, 4, 5],
  String start = '19:00',
  String end = '21:00',
}) =>
    AttachmentSchedule(
      id: id,
      type: type,
      title: title,
      weekdays: weekdays,
      start: start,
      end: end,
      location: '图书馆三楼',
    );

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await TimetableRepository.clear();
  });

  group('AttachmentSchedule 模型', () {
    test('星期摘要：连续段折叠、全程「每天」、散列顿号相连', () {
      expect(
        _schedule(weekdays: [1, 2, 3, 4, 5]).weekdayLabel,
        '周一至周五',
      );
      expect(
        _schedule(weekdays: [1, 2, 3, 4, 5, 6, 7]).weekdayLabel,
        '每天',
      );
      expect(_schedule(weekdays: [1, 3, 5]).weekdayLabel, '周一、周三、周五');
      expect(_schedule(weekdays: [6, 7]).weekdayLabel, '周六、周日');
      expect(_schedule(weekdays: [2, 3, 4, 6]).weekdayLabel, '周二至周四、周六');
      expect(_schedule(weekdays: []).weekdayLabel, '未设重复');
    });

    test('时间校验：结束必须晚于开始，格式非法为 false', () {
      expect(AttachmentSchedule.isValidRange('19:00', '21:00'), isTrue);
      expect(AttachmentSchedule.isValidRange('19:00', '19:00'), isFalse);
      expect(AttachmentSchedule.isValidRange('21:00', '19:00'), isFalse);
      expect(AttachmentSchedule.isValidRange('25:00', '26:00'), isFalse);
      expect(AttachmentSchedule.isValidRange('abc', '21:00'), isFalse);
    });

    test('occursOn 与 JSON 往返', () {
      final s = _schedule();
      expect(s.occursOn(1), isTrue);
      expect(s.occursOn(6), isFalse);

      final restored = AttachmentSchedule.fromJson(s.toJson());
      expect(restored.id, s.id);
      expect(restored.type, s.type);
      expect(restored.title, s.title);
      expect(restored.weekdays, s.weekdays);
      expect(restored.start, s.start);
      expect(restored.end, s.end);
      expect(restored.location, s.location);
      expect(restored.enabled, isTrue);
    });

    test('非法星期与未知类型在反序列化时被丢弃 / 兜底', () {
      final s = AttachmentSchedule.fromJson({
        'id': 'x',
        'type': 'unknown',
        'title': 't',
        'weekdays': [0, 3, 9],
        'start': '19:00',
        'end': '21:00',
      });
      expect(s.type, AttachmentScheduleType.eveningStudy);
      expect(s.weekdays, [3]);
    });
  });

  group('AttachmentScheduleRepository', () {
    test('空存储返回空列表', () async {
      expect(await AttachmentScheduleRepository.load(), isEmpty);
    });

    test('add 生成 id 并落库，load 按开始时间排序', () async {
      final a = await AttachmentScheduleRepository.add(
        _schedule(start: '21:00', end: '22:00'),
      );
      final b = await AttachmentScheduleRepository.add(
        _schedule(id: '', title: '更早的', start: '19:00', end: '20:00'),
      );
      expect(a.id, isNotEmpty);
      expect(b.id, isNotEmpty);

      final list = await AttachmentScheduleRepository.load();
      expect(list.length, 2);
      expect(list.first.title, '更早的');
      expect(list.last.title, '图书馆晚自习');
    });

    test('update / setEnabled / remove 生效', () async {
      final added = await AttachmentScheduleRepository.add(_schedule());
      await AttachmentScheduleRepository.update(
        added.copyWith(title: '改了名'),
      );
      var list = await AttachmentScheduleRepository.load();
      expect(list.single.title, '改了名');

      await AttachmentScheduleRepository.setEnabled(added.id, false);
      list = await AttachmentScheduleRepository.load();
      expect(list.single.enabled, isFalse);

      await AttachmentScheduleRepository.remove(added.id);
      expect(await AttachmentScheduleRepository.load(), isEmpty);
    });

    test('存储损坏时返回空列表而不是抛异常', () async {
      final sp = await SharedPreferences.getInstance();
      await sp.setString('zsy_attachment_schedules', '{not json');
      expect(await AttachmentScheduleRepository.load(), isEmpty);
    });
  });

  group('附属日程页', () {
    testWidgets('同一页展示两个分类，可新建晚自习', (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: AttachmentSchedulePage()));
      await tester.pumpAndSettle();

      expect(find.text('晚自习'), findsOneWidget);
      expect(find.text('阳光体育'), findsOneWidget);
      expect(find.text('新建晚自习'), findsOneWidget);
      expect(find.text('新建阳光体育'), findsOneWidget);

      // 点「新建晚自习」进入编辑页，默认周一至周五 + 19:00-21:00，直接创建
      await tester.tap(find.text('新建晚自习'));
      await tester.pumpAndSettle();
      expect(find.text('新建晚自习', skipOffstage: false), findsNWidgets(2));

      await tester.dragUntilVisible(
        find.text('创建日程'),
        find.byType(ListView).last,
        const Offset(0, -150),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('创建日程'));
      await tester.pumpAndSettle();

      // 返回列表：分类标题 + 条目各一个「晚自习」
      expect(find.text('晚自习'), findsNWidgets(2));
      expect(find.text('1 条'), findsOneWidget);
      expect(find.text('19:00 - 21:00 · 周一至周五'), findsOneWidget);
    });

    testWidgets('已有日程可停用再启用', (WidgetTester tester) async {
      await AttachmentScheduleRepository.add(_schedule());
      await tester.pumpWidget(const MaterialApp(home: AttachmentSchedulePage()));
      await tester.pumpAndSettle();

      // 初始为启用
      expect(find.text('图书馆晚自习'), findsOneWidget);
      final switches = find.byType(Switch);
      expect(tester.widget<Switch>(switches.first).value, isTrue);

      await tester.tap(switches.first);
      await tester.pumpAndSettle();
      expect(
        tester.widget<Switch>(find.byType(Switch).first).value,
        isFalse,
      );
    });

    testWidgets('编辑页结束时间早于开始时保存被拦截', (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: AttachmentSchedulePage()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('新建阳光体育'));
      await tester.pumpAndSettle();

      // 未选任何重复星期 → 应弹提示且不返回列表：
      // 关掉周一至周五全部 chips（默认选中 1..5）
      for (final label in ['一', '二', '三', '四', '五']) {
        await tester.tap(find.text(label).last);
        await tester.pumpAndSettle();
      }
      await tester.dragUntilVisible(
        find.text('创建日程'),
        find.byType(ListView).last,
        const Offset(0, -150),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('创建日程'));
      await tester.pumpAndSettle();

      expect(find.text('至少选择一个重复的星期'), findsOneWidget);
      // 仍在编辑页
      expect(find.text('新建阳光体育', skipOffstage: false), findsNWidgets(2));
    });
  });

  group('看板合并展示', () {
    String timetableJson() {
      final now = DateTime.now();
      final monday = now.subtract(Duration(days: now.weekday - 1));
      String fmt(DateTime d) =>
          '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';
      final tt = Timetable(
        term: '2026-2027-1',
        termName: '2026-2027-1',
        totalWeeks: 20,
        semesterStartDate: fmt(monday),
        courses: const [],
        timeSlots: const [
          TimeSlot(number: 1, startTime: '08:00', endTime: '08:45'),
        ],
      );
      return jsonEncode(tt.toJson());
    }

    testWidgets('当天有附属日程时在看板课程下方展示', (WidgetTester tester) async {
      final todayWeekday = DateTime.now().weekday;
      SharedPreferences.setMockInitialValues({
        'zsy_profile': jsonEncode({
          'studentId': '202301010101',
          'term': '2026-2027-1',
          'hasCampusNetwork': true,
          'webvpnPassword': 'vpn-pass',
          'jwglPassword': 'jwgl-pass',
        }),
        'zsy_notice_guide_seen': true,
        'zsy_timetable_json': timetableJson(),
        'zsy_utility_cache': jsonEncode({
          'studentId': '202301010101',
          'fetchedAt': DateTime.now().millisecondsSinceEpoch,
          'rooms': [
            {'roomName': '12栋 507', 'electricity': 23.6, 'water': 8.2},
          ],
        }),
        'zsy_attachment_schedules': jsonEncode([
          {
            'id': 's1',
            'type': 'eveningStudy',
            'title': '图书馆晚自习',
            'weekdays': [todayWeekday],
            'start': '19:00',
            'end': '21:00',
            'location': '图书馆三楼',
            'note': '',
            'enabled': true,
          },
        ]),
      });

      await tester.pumpWidget(const ZhangShangZhaoYuanApp());
      await tester.pumpAndSettle();

      // 今天没课但附属日程存在，不应显示「今天没有课」
      expect(find.text('今天没有课'), findsNothing);
      expect(find.text('附属日程'), findsOneWidget);
      expect(find.text('图书馆晚自习'), findsOneWidget);
      expect(find.text('19:00'), findsOneWidget);
      expect(find.text('21:00'), findsOneWidget);
    });

    testWidgets('当天没有附属日程时保持原空状态', (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({
        'zsy_profile': jsonEncode({
          'studentId': '202301010101',
          'term': '2026-2027-1',
          'hasCampusNetwork': true,
          'webvpnPassword': 'vpn-pass',
          'jwglPassword': 'jwgl-pass',
        }),
        'zsy_notice_guide_seen': true,
        'zsy_timetable_json': timetableJson(),
        'zsy_utility_cache': jsonEncode({
          'studentId': '202301010101',
          'fetchedAt': DateTime.now().millisecondsSinceEpoch,
          'rooms': [
            {'roomName': '12栋 507', 'electricity': 23.6, 'water': 8.2},
          ],
        }),
      });

      await tester.pumpWidget(const ZhangShangZhaoYuanApp());
      await tester.pumpAndSettle();

      expect(find.text('今天没有课'), findsOneWidget);
      expect(find.text('附属日程'), findsNothing);
    });
  });
}
