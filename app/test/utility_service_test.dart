/// 完美校园水电查询解析的单元测试。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:zhangshang_yanyuan/services/utility_service.dart';

void main() {
  group('parseRooms 返回解析', () {
    test('body 为 JSON 字符串且含 roomlist 时解析多字段', () {
      const raw =
          '{"body":"{\\"roomlist\\":[{\\"roomfullname\\":\\"12栋 507\\",'
          '\\"roomverify\\":\\"8888\\",\\"detaillist\\":[{\\"businesstype\\":\\"0\\",'
          '\\"odd\\":\\"23.45\\",\\"use\\":\\"100.00\\"},{\\"businesstype\\":\\"1\\",'
          '\\"odd\\":\\"8.2\\",\\"use\\":\\"50.00\\"}]}]}","message":"操作成功"}';
      final rooms = UtilityService.parseRooms(raw);
      expect(rooms.length, 1);
      expect(rooms.first.roomName, '12栋 507');
      expect(rooms.first.electricity, 23.45);
      expect(rooms.first.water, 8.2);
    });

    test('无 roomlist 时视为单房间', () {
      const raw =
          '{"body":{"roomfullname":"20栋 101","detaillist":'
          '[{"businesstype":"0","odd":"3.20"}]}}';
      final rooms = UtilityService.parseRooms(raw);
      expect(rooms.length, 1);
      expect(rooms.first.roomName, '20栋 101');
      expect(rooms.first.electricity, 3.20);
      expect(rooms.first.water, 0); // 缺水费条目时为 0
    });

    test('odd 为数字类型时同样可解析', () {
      const raw =
          '{"body":{"roomfullname":"A栋","detaillist":'
          '[{"businesstype":"1","odd":12.5}]}}';
      final rooms = UtilityService.parseRooms(raw);
      expect(rooms.first.water, 12.5);
    });

    test('多房间全部解析', () {
      const raw =
          '{"body":"{\\"roomlist\\":[{\\"roomfullname\\":\\"12栋 507\\",'
          '\\"detaillist\\":[{\\"businesstype\\":\\"0\\",\\"odd\\":\\"10\\"}]},'
          '{\\"roomfullname\\":\\"12栋 508\\",\\"detaillist\\":'
          '[{\\"businesstype\\":\\"1\\",\\"odd\\":\\"2\\"}]}]}"}';
      final rooms = UtilityService.parseRooms(raw);
      expect(rooms.length, 2);
      expect(rooms[0].roomName, '12栋 507');
      expect(rooms[1].roomName, '12栋 508');
    });

    test('未绑定房间时抛出 UtilityException', () {
      expect(
        () => UtilityService.parseRooms('{"body":""}'),
        throwsA(isA<UtilityException>()),
      );
      expect(
        () => UtilityService.parseRooms('{}'),
        throwsA(isA<UtilityException>()),
      );
    });

    test('非法 JSON 抛出 UtilityException', () {
      expect(
        () => UtilityService.parseRooms('not-json'),
        throwsA(isA<UtilityException>()),
      );
    });
  });
}
