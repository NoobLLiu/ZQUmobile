/// 掌上砚园基础组件的冒烟测试。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zhangshang_yanyuan/main.dart';
import 'package:zhangshang_yanyuan/pages/notice_rewrite_page.dart';

/// 一份完整的个人信息，避免首屏引导弹窗挡住界面。
final String _completeProfile = jsonEncode({
  'studentId': '202301010101',
  'term': '2026-2027-1',
  'hasCampusNetwork': true,
  'webvpnPassword': 'vpn-pass',
  'jwglPassword': 'jwgl-pass',
});

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'zsy_profile': _completeProfile,
    });
  });

  testWidgets('应用能启动并显示底部导航', (WidgetTester tester) async {
    await tester.pumpWidget(const ZhangShangZhaoYuanApp());

    // 底部导航应有两个目的地：首页 / 我的
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('首页'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
  });

  testWidgets('首页展示功能入口', (WidgetTester tester) async {
    await tester.pumpWidget(const ZhangShangZhaoYuanApp());

    expect(find.textContaining('掌上砚园'), findsWidgets);
    expect(find.text('我的课表'), findsOneWidget);
    expect(find.text('教务系统'), findsOneWidget);
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

  testWidgets('首页可以进入通知转写', (WidgetTester tester) async {
    await tester.pumpWidget(const ZhangShangZhaoYuanApp());

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
}
