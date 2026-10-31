/// 个人信息模型与校验的测试。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:zhangshang_yanyuan/models/profile.dart';

void main() {
  group('学号校验', () {
    test('12 位纯数字通过', () {
      expect(isValidStudentId('202301010101'), isTrue);
    });

    test('少于 12 位不通过', () {
      expect(isValidStudentId('20230101'), isFalse);
    });

    test('多于 12 位不通过', () {
      expect(isValidStudentId('2023010101011'), isFalse);
    });

    test('含字母不通过', () {
      expect(isValidStudentId('20230101010a'), isFalse);
    });

    test('首尾空格会被忽略', () {
      expect(isValidStudentId('  202301010101  '), isTrue);
    });
  });

  group('Profile', () {
    test('默认值：未填学号、默认第一学期、未购校园网、无密码', () {
      const p = Profile();
      expect(p.studentId, isEmpty);
      expect(p.term, kDefaultTerm);
      expect(p.hasCampusNetwork, isFalse);
      expect(p.jwglPassword, isEmpty);
      expect(p.webvpnPassword, isEmpty);
      expect(p.isComplete, isFalse);
    });

    test('学号、学期、两套密码都齐才算完整', () {
      const p = Profile(
        studentId: '202301010101',
        jwglPassword: 'a1b2c3',
        webvpnPassword: 'd4e5f6',
      );
      expect(p.isComplete, isTrue);
    });

    test('缺教务密码不算完整', () {
      const p = Profile(
        studentId: '202301010101',
        webvpnPassword: 'd4e5f6',
      );
      expect(p.isComplete, isFalse);
    });

    test('缺 WebVPN 密码不算完整', () {
      const p = Profile(
        studentId: '202301010101',
        jwglPassword: 'a1b2c3',
      );
      expect(p.isComplete, isFalse);
    });

    test('密码全是空格不算填写', () {
      const p = Profile(
        studentId: '202301010101',
        jwglPassword: '   ',
        webvpnPassword: '   ',
      );
      expect(p.isComplete, isFalse);
    });

    test('JSON 往返保持一致（含两套密码）', () {
      const p = Profile(
        studentId: '202301010101',
        term: '2026-2027-2',
        hasCampusNetwork: true,
        jwglPassword: 'jwgl-pass',
        webvpnPassword: 'vpn-pass',
      );
      final back = Profile.fromJson(p.toJson());
      expect(back.studentId, p.studentId);
      expect(back.term, p.term);
      expect(back.hasCampusNetwork, isTrue);
      expect(back.jwglPassword, 'jwgl-pass');
      expect(back.webvpnPassword, 'vpn-pass');
      expect(back.isComplete, isTrue);
    });

    test('旧版本数据没有密码字段时按空串处理', () {
      final back = Profile.fromJson({
        'studentId': '202301010101',
        'term': '2026-2027-1',
        'hasCampusNetwork': false,
      });
      expect(back.jwglPassword, isEmpty);
      expect(back.webvpnPassword, isEmpty);
      expect(back.isComplete, isFalse);
    });

    test('学期选项包含两个预留学期，默认是第一个', () {
      expect(kTermOptions, ['2026-2027-1', '2026-2027-2']);
      expect(kDefaultTerm, kTermOptions.first);
    });
  });
}
