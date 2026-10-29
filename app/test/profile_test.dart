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
    test('默认值：未填学号、默认第一学期、未购校园网', () {
      const p = Profile();
      expect(p.studentId, isEmpty);
      expect(p.term, kDefaultTerm);
      expect(p.hasCampusNetwork, isFalse);
      expect(p.isComplete, isFalse);
    });

    test('学号合法且学期非空才算完整', () {
      const p = Profile(studentId: '202301010101');
      expect(p.isComplete, isTrue);
    });

    test('JSON 往返保持一致', () {
      const p = Profile(
        studentId: '202301010101',
        term: '2026-2027-2',
        hasCampusNetwork: true,
      );
      final back = Profile.fromJson(p.toJson());
      expect(back.studentId, p.studentId);
      expect(back.term, p.term);
      expect(back.hasCampusNetwork, isTrue);
    });

    test('学期选项包含两个预留学期，默认是第一个', () {
      expect(kTermOptions, ['2026-2027-1', '2026-2027-2']);
      expect(kDefaultTerm, kTermOptions.first);
    });
  });
}
