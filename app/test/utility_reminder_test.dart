/// 水电余额提醒决策逻辑（planUtilityAlert）的单元测试。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:zhangshang_yanyuan/models/utility.dart';
import 'package:zhangshang_yanyuan/services/utility_reminder.dart';

UtilityRoom _room({String name = '12栋 507', double elec = 20, double water = 5}) =>
    UtilityRoom(roomName: name, electricity: elec, water: water);

void main() {
  group('planUtilityAlert', () {
    test('首次检查（无历史状态）余额充足时不提醒', () {
      final plan = planUtilityAlert(
        prevElecLow: null,
        prevWaterLow: null,
        rooms: [_room(elec: 20, water: 5)],
      );
      expect(plan.shouldNotify, isFalse);
      expect(plan.elecLowNow, isFalse);
      expect(plan.waterLowNow, isFalse);
      expect(plan.lines, isEmpty);
      expect(plan.toState(), {'elecLow': false, 'waterLow': false});
    });

    test('首次检查（无历史状态）已低于阈值时提醒', () {
      final plan = planUtilityAlert(
        prevElecLow: null,
        prevWaterLow: null,
        rooms: [_room(elec: 3, water: 0.5)],
      );
      expect(plan.shouldNotify, isTrue);
      expect(plan.lines, hasLength(2));
      expect(plan.lines.first, contains('12栋 507'));
      expect(plan.lines.first, contains('电费'));
      expect(plan.lines.last, contains('水费'));
    });

    test('阈值边界：恰好等于阈值视为不足', () {
      final plan = planUtilityAlert(
        prevElecLow: false,
        prevWaterLow: false,
        rooms: [_room(elec: kLowElectricity, water: kLowWater)],
      );
      expect(plan.elecLowNow, isTrue);
      expect(plan.waterLowNow, isTrue);
      expect(plan.shouldNotify, isTrue);
    });

    test('持续低余额不重复提醒', () {
      final first = planUtilityAlert(
        prevElecLow: null,
        prevWaterLow: null,
        rooms: [_room(elec: 2, water: 8)],
      );
      expect(first.shouldNotify, isTrue);

      // 半小时后再查，仍是低电费：不重复提醒
      final second = planUtilityAlert(
        prevElecLow: first.elecLowNow,
        prevWaterLow: first.waterLowNow,
        rooms: [_room(elec: 1, water: 8)],
      );
      expect(second.shouldNotify, isFalse);
      expect(second.elecLowNow, isTrue);
    });

    test('恢复正常后复位，再次变低会重新提醒', () {
      final first = planUtilityAlert(
        prevElecLow: null,
        prevWaterLow: null,
        rooms: [_room(elec: 2, water: 8)],
      );
      expect(first.shouldNotify, isTrue);

      final recovered = planUtilityAlert(
        prevElecLow: first.elecLowNow,
        prevWaterLow: first.waterLowNow,
        rooms: [_room(elec: 30, water: 8)],
      );
      expect(recovered.shouldNotify, isFalse);
      expect(recovered.elecLowNow, isFalse);

      final again = planUtilityAlert(
        prevElecLow: recovered.elecLowNow,
        prevWaterLow: recovered.waterLowNow,
        rooms: [_room(elec: 0.5, water: 8)],
      );
      expect(again.shouldNotify, isTrue);
    });

    test('多房间聚合：任一房间低于阈值即告警，正文只列不足项', () {
      final plan = planUtilityAlert(
        prevElecLow: false,
        prevWaterLow: false,
        rooms: [
          _room(name: '12栋 507', elec: 20, water: 5),
          _room(name: '12栋 508', elec: 1, water: 9),
        ],
      );
      expect(plan.shouldNotify, isTrue);
      expect(plan.elecLowNow, isTrue);
      expect(plan.waterLowNow, isFalse);
      expect(plan.lines, hasLength(1));
      expect(plan.lines.single, contains('12栋 508'));
      expect(plan.lines.single, contains('电费'));
    });
  });
}
