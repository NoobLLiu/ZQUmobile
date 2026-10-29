/// ZQU 教务对接解析逻辑的单元测试。
///
/// 覆盖拾光适配脚本 zqu_01.js 中的关键解析函数：
/// parseSections / parseWeekText / mergeAndDistinctCourses / collectCourses。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:zhangshang_yanyuan/services/jwgl_service.dart';

void main() {
  group('parseSections 节次解析', () {
    test('逗号分隔形式 "01,02,03"', () {
      expect(parseSections('01,02,03', null), [1, 2, 3]);
    });

    test('连写形式 "0102" 拆成每两位一个节号', () {
      expect(parseSections(null, '0102'), [1, 2]);
    });

    test('混用形式，节号去重且升序', () {
      expect(parseSections('03,01,01', null), [1, 3]);
    });

    test('空值返回空列表', () {
      expect(parseSections(null, null), isEmpty);
      expect(parseSections('', ''), isEmpty);
    });
  });

  group('parseWeekText 周次解析', () {
    test('区间形式 "1-8,10-17周"', () {
      final w = parseWeekText('1-8,10-17周');
      expect(w.first, 1);
      expect(w.last, 17);
      expect(w.length, 8 + 8);
      expect(w.contains(9), isFalse);
    });

    test('逗号分隔形式 "1,3,5周"', () {
      expect(parseWeekText('1,3,5周'), [1, 3, 5]);
    });

    test('位串形式 "1111111100000000"', () {
      expect(parseWeekText('1111111100000000'), [1, 2, 3, 4, 5, 6, 7, 8]);
    });

    test('带单双周后缀 "1-16(单)"', () {
      expect(parseWeekText('1-16(单)'), List.generate(16, (i) => i + 1));
    });

    test('空值返回空列表', () {
      expect(parseWeekText(null), isEmpty);
      expect(parseWeekText(''), isEmpty);
    });
  });

  group('collectCourses 聚合', () {
    test('按课程名/教师/教室/星期/节次聚合周次', () {
      final records = [
        {
          'xq': '1',
          'kcmc': '高等数学',
          'teaxms': '张老师',
          'jxcdmc': 'A101',
          'jcdm2': '01,02',
          'zc': '1-8周',
        },
        {
          'xq': '1',
          'kcmc': '高等数学',
          'teaxms': '张老师',
          'jxcdmc': 'A101',
          'jcdm2': '01,02',
          'zc': '9-16周',
        },
      ];

      final result = collectCourses(records);
      expect(result.courses.length, 1);
      expect(result.courses.first['name'], '高等数学');
      expect(result.courses.first['startSection'], 1);
      expect(result.courses.first['endSection'], 2);
      expect(result.courses.first['weeks'], [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]);
      expect(result.totalWeeks, 16);
    });

    test('教室为空时使用占位文本', () {
      final result = collectCourses([
        {
          'xq': '3',
          'kcmc': '大学英语',
          'teaxms': '李老师',
          'jxcdmc': '',
          'jcdm2': '03',
          'zc': '1-16周',
        },
      ]);
      expect(result.courses.first['position'], kUnknownPosition);
    });

    test('非法星期与空课程名被跳过', () {
      final result = collectCourses([
        {'xq': '9', 'kcmc': '无效课', 'jcdm2': '01', 'zc': '1-8周'},
        {'xq': '1', 'kcmc': '', 'jcdm2': '01', 'zc': '1-8周'},
      ]);
      expect(result.courses, isEmpty);
    });
  });

  group('mergeAndDistinctCourses 合并去重', () {
    test('连续节次合并成一条', () {
      final merged = mergeAndDistinctCourses([
        {
          'name': '体育',
          'teacher': '王老师',
          'position': '操场',
          'day': 1,
          'startSection': 1,
          'endSection': 1,
          'weeks': [1, 2],
        },
        {
          'name': '体育',
          'teacher': '王老师',
          'position': '操场',
          'day': 1,
          'startSection': 2,
          'endSection': 2,
          'weeks': [1, 2],
        },
      ]);
      expect(merged.length, 1);
      expect(merged.first['startSection'], 1);
      expect(merged.first['endSection'], 2);
    });

    test('同节次不同周次合并周次', () {
      final merged = mergeAndDistinctCourses([
        {
          'name': '思政',
          'teacher': '赵老师',
          'position': 'B201',
          'day': 2,
          'startSection': 3,
          'endSection': 3,
          'weeks': [1, 2],
        },
        {
          'name': '思政',
          'teacher': '赵老师',
          'position': 'B201',
          'day': 2,
          'startSection': 3,
          'endSection': 3,
          'weeks': [3, 4],
        },
      ]);
      expect(merged.length, 1);
      expect(merged.first['weeks'], [1, 2, 3, 4]);
    });
  });

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
}
