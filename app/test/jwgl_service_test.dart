/// 教务桥接消息解析的单元测试。
///
/// 覆盖适配脚本回传的 payload 与桥接通道消息的分流逻辑。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:zhangshang_yanyuan/services/jwgl_service.dart';

void main() {
  group('parseFetchPayload 回传解析', () {
    test('正常结果解析', () {
      final raw = '{"ok":true,"term":"202601","termName":"2026-2027-1",'
          '"semesterStartDate":"2026-08-31","totalWeeks":22,'
          '"courses":[{"name":"体育","teacher":"王老师","position":"操场",'
          '"day":1,"startSection":1,"endSection":2,"weeks":[1,2]}],'
          '"timeSlots":[{"number":1,"startTime":"08:00","endTime":"08:40"}]}';
      final r = parseFetchPayload(raw);
      expect(r.term, '202601');
      expect(r.termName, '2026-2027-1');
      expect(r.totalWeeks, 22);
      expect(r.semesterStartDate, '2026-08-31');
      expect(r.courses.length, 1);
      expect(r.timeSlots.length, 1);
    });

    test('失败结果抛出异常', () {
      expect(
        () => parseFetchPayload('{"ok":false,"error":"未登录"}'),
        throwsA(isA<JwglException>()),
      );
    });

    test('空课程列表抛出异常', () {
      expect(
        () => parseFetchPayload('{"ok":true,"courses":[]}'),
        throwsA(isA<JwglException>()),
      );
    });
  });

  group('parseBridgeMessage 通道消息分流', () {
    test('progress 消息解析为进度', () {
      final m = parseBridgeMessage('{"type":"progress","message":"正在读取课表 ..."}');
      expect(m.isProgress, isTrue);
      expect(m.message, '正在读取课表 ...');
      expect(m.result, isNull);
    });

    test('result 成功消息带出课程数据', () {
      final raw = '{"type":"result","ok":true,"term":"202601",'
          '"termName":"2026-2027-1","semesterStartDate":"2026-08-31",'
          '"totalWeeks":20,"courses":[{"name":"体育","teacher":"王","position":"操场",'
          '"day":1,"startSection":1,"endSection":2,"weeks":[1]}]}';
      final m = parseBridgeMessage(raw);
      expect(m.isProgress, isFalse);
      expect(m.isSuccess, isTrue);
      expect(m.result!.courses.length, 1);
      expect(m.result!.term, '202601');
    });

    test('result 失败消息带出错误原因', () {
      final m = parseBridgeMessage('{"type":"result","ok":false,"error":"登录已失效"}');
      expect(m.isProgress, isFalse);
      expect(m.isSuccess, isFalse);
      expect(m.error, '登录已失效');
    });

    test('缺少 type 的旧格式按 result 处理', () {
      final raw = '{"ok":true,"courses":[{"name":"体育","teacher":"","position":"",'
          '"day":1,"startSection":1,"endSection":1,"weeks":[1]}]}';
      final m = parseBridgeMessage(raw);
      expect(m.isProgress, isFalse);
      expect(m.isSuccess, isTrue);
    });
  });
}
