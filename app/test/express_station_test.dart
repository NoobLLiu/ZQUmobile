/// 快递站状态：状态判定逻辑 + 页面组件测试。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zhangshang_yanyuan/main.dart';
import 'package:zhangshang_yanyuan/models/express_station.dart';
import 'package:zhangshang_yanyuan/pages/express_station_page.dart';

/// 2026-10-28 是周三，2026-10-30 是周五。
DateTime _at(int day, int hour, [int minute = 0]) =>
    DateTime(2026, 10, day, hour, minute);

/// 从 [kExpressStationGroups] 里按名字取驿站。
ExpressStation _station(String name) => kExpressStationGroups
    .expand((g) => g.stations)
    .firstWhere((s) => s.name == name);

ExpressStationGroup _group(String name) => kExpressStationGroups
    .firstWhere((g) => g.name == name);

void main() {
  group('TimeRange', () {
    test('解析与格式化互逆', () {
      final range = TimeRange.hhmm('07:00', '23:00');
      expect(range.open, 420);
      expect(range.close, 1380);
      expect(range.format(), '07:00-23:00');
      expect(range.contains(420), isTrue);
      expect(range.contains(1379), isTrue);
      // 右开：关门时刻即视为已关门
      expect(range.contains(1380), isFalse);
    });
  });

  group('evaluateExpressStation', () {
    test('营业时段内为营业中', () {
      final r = evaluateExpressStation(
        _station('东门申通快递'),
        _at(28, 15),
        gateHours: _group('东门').gateHours,
      );
      expect(r.status, ExpressStatus.open);
      expect(r.hours!.format(), '10:00-21:00');
    });

    test('开门前与关门后均为未营业（关门时刻恰好不算营业）', () {
      final gate = _group('东门').gateHours;
      expect(
        evaluateExpressStation(_station('东门申通快递'), _at(28, 9),
                gateHours: gate)
            .status,
        ExpressStatus.closed,
      );
      expect(
        evaluateExpressStation(_station('东门申通快递'), _at(28, 21), gateHours: gate)
            .status,
        ExpressStatus.closed,
      );
    });

    test('距打烊不足 30 分钟转黄，30 分钟整也算', () {
      final gate = _group('东门').gateHours;
      // 20:29 → 剩 31 分钟，仍绿
      expect(
        evaluateExpressStation(_station('东门申通快递'), _at(28, 20, 29),
                gateHours: gate)
            .status,
        ExpressStatus.open,
      );
      // 20:30 → 剩 30 分钟，转黄
      final r = evaluateExpressStation(
        _station('东门申通快递'),
        _at(28, 20, 30),
        gateHours: gate,
      );
      expect(r.status, ExpressStatus.closingSoon);
      expect(r.minutesToClose, 30);
    });

    test('肯德基旁驿站周五用特殊时间，其他日用默认时间', () {
      final gate = _group('东门').gateHours;
      // 周五 10:30：还没到 11:00 开门
      expect(
        evaluateExpressStation(_station('肯德基旁驿站'), _at(30, 10, 30),
                gateHours: gate)
            .status,
        ExpressStatus.closed,
      );
      // 周五 20:40：剩 10 分钟，转黄
      expect(
        evaluateExpressStation(_station('肯德基旁驿站'), _at(30, 20, 40),
                gateHours: gate)
            .status,
        ExpressStatus.closingSoon,
      );
      // 周五 21:00：周五 20:50 已关门
      expect(
        evaluateExpressStation(_station('肯德基旁驿站'), _at(30, 21), gateHours: gate)
            .status,
        ExpressStatus.closed,
      );
      // 周三 10:30：默认 10:00 开门，营业中
      expect(
        evaluateExpressStation(_station('肯德基旁驿站'), _at(28, 10, 30),
                gateHours: gate)
            .status,
        ExpressStatus.open,
      );
    });

    test('驿站开门但校门已关 → 不可达', () {
      // 东门实测数据不会出现该情况，用合成数据覆盖逻辑分支。
      const station = ExpressStation(
        name: '测试驿站',
        hours: TimeRange(360, 1410), // 06:00-23:30
      );
      const gate = TimeRange(420, 1380); // 07:00-23:00
      // 06:30：驿站在营业，校门未开
      expect(
        evaluateExpressStation(station, _at(28, 6, 30), gateHours: gate).status,
        ExpressStatus.unreachable,
      );
      // 23:05：驿站营业到 23:30，校门 23:00 已关
      expect(
        evaluateExpressStation(station, _at(28, 23, 5), gateHours: gate).status,
        ExpressStatus.unreachable,
      );
      // 12:00：两边都开，正常营业
      expect(
        evaluateExpressStation(station, _at(28, 12), gateHours: gate).status,
        ExpressStatus.open,
      );
      // 不传校门时间时不做校门判定
      expect(
        evaluateExpressStation(station, _at(28, 6, 30)).status,
        ExpressStatus.open,
      );
    });

    test('未录入时间 → 数据待补充', () {
      final r = evaluateExpressStation(
        _station('南门车库驿站'),
        _at(28, 12),
      );
      expect(r.status, ExpressStatus.noData);
      expect(r.hours, isNull);
    });
  });

  group('预录入数据', () {
    test('东门 4 家驿站且带校门时间，南门 1 家待补充', () {
      final east = _group('东门');
      expect(east.gateHours!.format(), '07:00-23:00');
      expect(east.stations, hasLength(4));
      expect(_group('南门').gateHours, isNull);
      expect(_station('南门车库驿站').hasData, isFalse);
    });
  });

  group('ExpressStationPage', () {
    // 页面卡片较高，把测试画布加高让所有分组一次可见。
    Future<void> pumpPage(
      WidgetTester tester, {
      DateTime Function()? clock,
    }) async {
      await tester.binding.setSurfaceSize(const Size(800, 1500));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(home: ExpressStationPage(clock: clock)),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('展示分组、驿站与营业状态（周三 15:00）', (tester) async {
      await pumpPage(tester, clock: () => _at(28, 15));

      expect(find.text('快递站状态'), findsOneWidget);
      expect(find.text('东门'), findsOneWidget);
      expect(find.text('南门'), findsOneWidget);
      expect(find.text('校门开放 07:00-23:00'), findsOneWidget);
      expect(find.text('东门菜鸟驿站'), findsOneWidget);
      expect(find.text('菜鸟の茶驿站'), findsOneWidget);
      expect(find.text('南门车库驿站'), findsOneWidget);
      // 东门 4 家全部营业中
      expect(find.text('营业中'), findsNWidgets(4));
      // 南门车库驿站灰卡
      expect(find.text('数据待补充'), findsOneWidget);
      expect(find.text('营业时间待录入'), findsOneWidget);
    });

    testWidgets('未营业时提示开门时间（周三 08:00）', (tester) async {
      await pumpPage(tester, clock: () => _at(28, 8));

      // 菜鸟驿站 07:00 已开门
      expect(find.text('营业中'), findsOneWidget);
      // 其余三家 10:00 开门
      expect(find.text('未营业 · 10:00 开门'), findsNWidgets(3));
    });

    testWidgets('距打烊不足 30 分钟显示剩余分钟（周三 22:50）', (tester) async {
      await pumpPage(tester, clock: () => _at(28, 22, 50));

      // 菜鸟驿站 23:00 关门，剩 10 分钟
      expect(find.text('即将打烊 · 剩 10 分钟'), findsOneWidget);
      // 其余三家均已打烊
      expect(find.text('已打烊'), findsNWidgets(3));
    });

    testWidgets('周五使用特殊营业时间并标注「今日」（周五 10:30）', (tester) async {
      await pumpPage(tester, clock: () => _at(30, 10, 30));

      expect(find.text('未营业 · 11:00 开门'), findsOneWidget);
      expect(find.text('今日 11:00-20:50'), findsOneWidget);
      expect(find.text('营业中'), findsNWidgets(3));
    });

    testWidgets('点分组栏可折叠/展开该组', (tester) async {
      await pumpPage(tester, clock: () => _at(28, 15));

      expect(find.text('东门菜鸟驿站'), findsOneWidget);

      // 折叠东门
      await tester.tap(find.text('东门'));
      await tester.pumpAndSettle();
      expect(find.text('东门菜鸟驿站'), findsNothing);
      expect(find.text('菜鸟の茶驿站'), findsNothing);
      // 南门分组不受影响
      expect(find.text('南门车库驿站'), findsOneWidget);

      // 再点一次展开
      await tester.tap(find.text('东门'));
      await tester.pumpAndSettle();
      expect(find.text('东门菜鸟驿站'), findsOneWidget);
    });

    testWidgets('每 30 秒自动按当前时间刷新', (tester) async {
      var fakeNow = _at(28, 15);
      await pumpPage(tester, clock: () => fakeNow);

      expect(find.textContaining('现在 15:00'), findsOneWidget);

      // 时间走到 20:40，推进 30 秒触发定时器
      fakeNow = _at(28, 20, 40);
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();

      expect(find.textContaining('现在 20:40'), findsOneWidget);
      // 申通与肯德基（周三默认 10:00-21:00）→ 剩 20 分钟，双双转黄
      expect(find.text('即将打烊 · 剩 20 分钟'), findsNWidgets(2));
    });
  });

  group('功能页入口', () {
    testWidgets('功能页宫格可以进入快递站状态页', (tester) async {
      SharedPreferences.setMockInitialValues({
        'zsy_profile': '{"studentId":"202301010101","term":"2026-2027-1",'
            '"hasCampusNetwork":true,"webvpnPassword":"vpn-pass",'
            '"jwglPassword":"jwgl-pass"}',
        'zsy_notice_guide_seen': true,
        // 新鲜水电缓存，避免看板页发起真实网络请求
        'zsy_utility_cache':
            '{"studentId":"202301010101","fetchedAt":${DateTime.now().millisecondsSinceEpoch},'
            '"rooms":[{"roomName":"12栋 507","electricity":23.6,"water":8.2}]}',
      });

      await tester.pumpWidget(const ZhangShangZhaoYuanApp());
      await tester.pumpAndSettle();

      // 默认在「看板」，先切到「功能页」
      await tester.tap(find.text('功能页'));
      await tester.pumpAndSettle();

      // 宫格第 3 行在首屏之下，分两次拖动滚到位
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -320));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -320));
      await tester.pumpAndSettle();

      await tester.tap(find.text('快递站状态'));
      await tester.pumpAndSettle();

      // 进入快递站状态页（功能页宫格的同名卡片仍在导航栈下层）
      expect(find.text('东门'), findsOneWidget);
      expect(find.textContaining('每 30 秒自动刷新'), findsOneWidget);
    });
  });
}
