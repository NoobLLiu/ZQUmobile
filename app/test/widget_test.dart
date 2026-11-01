/// 掌上砚园基础组件的冒烟测试。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zhangshang_yanyuan/main.dart';
import 'package:zhangshang_yanyuan/models/timetable.dart';
import 'package:zhangshang_yanyuan/pages/notice_rewrite_page.dart';
import 'package:zhangshang_yanyuan/services/timetable_repository.dart';
import 'package:zhangshang_yanyuan/services/utility_provider.dart';
import 'package:zhangshang_yanyuan/services/utility_service.dart';

/// 一份完整的个人信息，避免首屏引导弹窗挡住界面。
final String _completeProfile = jsonEncode({
  'studentId': '202301010101',
  'term': '2026-2027-1',
  'hasCampusNetwork': true,
  'webvpnPassword': 'vpn-pass',
  'jwglPassword': 'jwgl-pass',
});

/// 一份完整的新鲜水电缓存，避免看板页发起真实网络请求。
String _utilityCache() => jsonEncode({
  'studentId': '202301010101',
  'fetchedAt': DateTime.now().millisecondsSinceEpoch,
  'rooms': [
    {'roomName': '12栋 507', 'electricity': 23.6, 'water': 8.2},
  ],
});

void main() {
  setUp(() async {
    // 先给一份空 mock 让 clear() 能跑，再写入本用例的正式数据
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // 清掉课表仓库的静态缓存，避免上一个用例的课表串场
    await TimetableRepository.clear();
    SharedPreferences.setMockInitialValues({
      'zsy_profile': _completeProfile,
      // 默认当作已看过使用示例，免得每次进通知转写页都被弹窗挡住
      'zsy_notice_guide_seen': true,
      // 新鲜水电缓存，看板页直接用，不发起网络请求
      'zsy_utility_cache': _utilityCache(),
    });
  });

  testWidgets('应用能启动并显示底部导航', (WidgetTester tester) async {
    await tester.pumpWidget(const ZhangShangZhaoYuanApp());

    // 底部导航应有三个目的地：看板 / 功能页 / 我的
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('看板'), findsOneWidget);
    expect(find.text('功能页'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
  });

  testWidgets('功能页按分类展示功能入口', (WidgetTester tester) async {
    await tester.pumpWidget(const ZhangShangZhaoYuanApp());
    await tester.pumpAndSettle();

    // 默认在「看板」，先切到「功能页」
    await tester.tap(find.text('功能页'));
    await tester.pumpAndSettle();

    // 可见的标题只有功能页的（看板页同名标题在 IndexedStack 里处于 offstage，
    // 默认 finder 会跳过）
    expect(find.text('掌上砚园'), findsOneWidget);
    expect(find.textContaining('肇庆学院校园助手'), findsNothing);
    expect(find.text('课表已就绪'), findsNothing);

    expect(find.text('学习功能'), findsOneWidget);
    expect(find.text('我的课表'), findsOneWidget);
    expect(find.text('教务系统'), findsOneWidget);
    expect(find.text('班委工作'), findsOneWidget);
    expect(find.text('通知转写'), findsOneWidget);
    // AI 小标签
    expect(find.text('AI'), findsOneWidget);
    // 不再有「全部功能」
    expect(find.text('全部功能'), findsNothing);

    // 「校园生活」在首屏之外，滚一点再断言
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -240));
    await tester.pumpAndSettle();
    expect(find.text('校园生活'), findsOneWidget);
    expect(find.text('水电余额'), findsOneWidget);
    expect(find.text('快递站状态'), findsOneWidget);
  });

  testWidgets('切换到「我的」标签显示我的页面', (WidgetTester tester) async {
    await tester.pumpWidget(const ZhangShangZhaoYuanApp());

    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();

    expect(find.text('清空课表缓存'), findsOneWidget);
    expect(find.text('个人资料'), findsOneWidget);
  });

  testWidgets('「我的」里能进入验证码训练', (WidgetTester tester) async {
    await tester.pumpWidget(const ZhangShangZhaoYuanApp());

    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();

    final entry = find.text('验证码训练');
    await tester.dragUntilVisible(
      entry,
      find.byType(ListView),
      const Offset(0, -80),
    );
    await tester.pumpAndSettle();
    expect(entry, findsOneWidget);
    // 还没训练过：副标题应说明需要手动输入
    expect(find.textContaining('未训练'), findsOneWidget);
  });

  testWidgets('功能页可以进入通知转写', (WidgetTester tester) async {
    await tester.pumpWidget(const ZhangShangZhaoYuanApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('功能页'));
    await tester.pumpAndSettle();

    // 宫格第二行默认在首屏之外，先滚一点
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -260));
    await tester.pumpAndSettle();

    final entry = find.text('通知转写');
    expect(entry, findsOneWidget);
    await tester.tap(entry);
    await tester.pumpAndSettle();

    expect(find.text('通知转写助手'), findsOneWidget);
  });

  testWidgets('通知转写未粘贴原文时不发起请求', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: NoticeRewritePage()));

    final button = find.text('开始转写');
    await tester.dragUntilVisible(
      button,
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();

    await tester.tap(button);
    await tester.pumpAndSettle();

    // 前端先拦下来，不白花一次额度
    expect(find.text('请先粘贴原通知'), findsOneWidget);
  });

  testWidgets('通知转写给出演示期用 Key 的说明', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: NoticeRewritePage()));

    final notice = find.textContaining('作品提交阶段');
    await tester.dragUntilVisible(
      notice,
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();

    expect(notice, findsOneWidget);
  });

  testWidgets('首次进入通知转写会弹出使用示例，之后不再打扰',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const MaterialApp(home: NoticeRewritePage()));
    await tester.pumpAndSettle();

    expect(find.text('使用示例'), findsOneWidget);
    // 示例图与文字说明都要在
    expect(find.byType(Image), findsWidgets);
    expect(find.textContaining('粘进「① 原通知」'), findsOneWidget);
    expect(find.text('填入示例'), findsOneWidget);

    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    expect(find.text('使用示例'), findsNothing);

    // 再进一次不该再弹
    await tester.pumpWidget(
      const MaterialApp(home: NoticeRewritePage(key: ValueKey('second'))),
    );
    await tester.pumpAndSettle();
    expect(find.text('使用示例'), findsNothing);
  });

  testWidgets('示例能一键填进表单', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: NoticeRewritePage()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('使用示例'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('填入示例'));
    await tester.pumpAndSettle();

    // 原通知、来源、问好对象都被填好，用户可以直接点开始转写
    expect(find.textContaining('挑战杯'), findsWidgets);
    expect(find.textContaining('整句问候：法学5班的同学们下午好'), findsOneWidget);
  });

  testWidgets('个人信息不完整时会弹出填写引导', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const ZhangShangZhaoYuanApp());
    // 等首帧后的异步检查完成
    await tester.pumpAndSettle();

    expect(find.text('个人信息'), findsOneWidget);
    expect(find.text('保存'), findsOneWidget);
  });

  testWidgets('个人信息弹窗要求分别填写教务与 WebVPN 密码', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const ZhangShangZhaoYuanApp());
    await tester.pumpAndSettle();

    expect(find.text('教务系统密码'), findsOneWidget);
    expect(find.text('WebVPN 密码'), findsOneWidget);
  });

  /// 构造一份「本周」的课表：今天有一节 1-2 节的课。
  String timetableJson() {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    String fmt(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}'
        '-${d.month.toString().padLeft(2, '0')}'
        '-${d.day.toString().padLeft(2, '0')}';
    final tt = Timetable(
      term: '202601',
      termName: '2026-2027-1',
      totalWeeks: 20,
      semesterStartDate: fmt(monday),
      courses: [
        Course(
          name: '数据结构',
          teacher: '刘老师',
          position: '工科楼 C402',
          day: now.weekday,
          startSection: 1,
          endSection: 2,
          weeks: List.generate(20, (i) => i + 1),
        ),
      ],
      timeSlots: const [
        TimeSlot(number: 1, startTime: '08:00', endTime: '08:45'),
        TimeSlot(number: 2, startTime: '08:55', endTime: '09:40'),
      ],
    );
    return jsonEncode(tt.toJson());
  }

  testWidgets('看板页默认显示今日课程与水电余额', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'zsy_profile': _completeProfile,
      'zsy_notice_guide_seen': true,
      'zsy_timetable_json': timetableJson(),
      'zsy_utility_cache': _utilityCache(),
    });

    await tester.pumpWidget(const ZhangShangZhaoYuanApp());
    await tester.pumpAndSettle();

    expect(find.textContaining('今天 · '), findsOneWidget);
    expect(find.textContaining('第 1 周'), findsOneWidget);
    expect(find.text('数据结构'), findsOneWidget);
    expect(find.textContaining('工科楼 C402'), findsOneWidget);
    expect(find.text('生活数据'), findsOneWidget);
    expect(find.text('23.6'), findsOneWidget);
    expect(find.text('度'), findsOneWidget);
    expect(find.text('8.2'), findsOneWidget);
    expect(find.text('吨'), findsOneWidget);
    // 有新鲜缓存，不应出现「数据可能过期」的感叹号
    expect(find.byIcon(Icons.error_outline), findsNothing);
  });

  testWidgets('看板页左右滑动可切换日期', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'zsy_profile': _completeProfile,
      'zsy_notice_guide_seen': true,
      'zsy_timetable_json': timetableJson(),
      'zsy_utility_cache': _utilityCache(),
    });

    await tester.pumpWidget(const ZhangShangZhaoYuanApp());
    await tester.pumpAndSettle();

    // 在日期标题上向左滑 → 切到明天
    await tester.drag(find.textContaining('今天 · '), const Offset(-200, 0));
    await tester.pumpAndSettle();

    expect(find.textContaining('今天 · '), findsNothing);
    expect(find.text('回到今天'), findsOneWidget);

    // 点「回到今天」恢复
    await tester.tap(find.text('回到今天'));
    await tester.pumpAndSettle();
    expect(find.textContaining('今天 · '), findsOneWidget);
  });

  testWidgets('看板页无课表时引导去导入', (WidgetTester tester) async {
    await tester.pumpWidget(const ZhangShangZhaoYuanApp());
    await tester.pumpAndSettle();

    expect(find.text('还没有课表'), findsOneWidget);
    expect(find.text('去导入课表'), findsOneWidget);
  });

  testWidgets('看板页水电查不到时显示「未查到」并标感叹号', (WidgetTester tester) async {
    addTearDown(
      () => UtilityDataProvider.fetcher = UtilityService.fetchRooms,
    );
    // 缓存缺失，后台刷新必然失败且无缓存可回退 → 显示「未查到」
    UtilityDataProvider.fetcher =
        (studentId) async => throw UtilityException('该学号未绑定宿舍房间');
    SharedPreferences.setMockInitialValues({
      'zsy_profile': _completeProfile,
      'zsy_notice_guide_seen': true,
    });

    await tester.pumpWidget(const ZhangShangZhaoYuanApp());
    await tester.pumpAndSettle();

    expect(find.text('未查到'), findsNWidgets(2));
    expect(find.text('23.6'), findsNothing);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });

  testWidgets('看板页刷新失败但有旧缓存时展示旧数据并标感叹号', (WidgetTester tester) async {
    addTearDown(
      () => UtilityDataProvider.fetcher = UtilityService.fetchRooms,
    );
    // 缓存已过期（13 小时前），后台刷新失败 → 回退旧缓存 + 感叹号
    UtilityDataProvider.fetcher =
        (studentId) async => throw UtilityException('连接超时，请稍后重试');
    SharedPreferences.setMockInitialValues({
      'zsy_profile': _completeProfile,
      'zsy_notice_guide_seen': true,
      'zsy_utility_cache': jsonEncode({
        'studentId': '202301010101',
        'fetchedAt': DateTime.now()
            .subtract(const Duration(hours: 13))
            .millisecondsSinceEpoch,
        'rooms': [
          {'roomName': '12栋 507', 'electricity': 23.6, 'water': 8.2},
        ],
      }),
    });

    await tester.pumpWidget(const ZhangShangZhaoYuanApp());
    await tester.pumpAndSettle();

    expect(find.text('23.6'), findsOneWidget);
    expect(find.text('8.2'), findsOneWidget);
    expect(find.text('未查到'), findsNothing);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });
}
