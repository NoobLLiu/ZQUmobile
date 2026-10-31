/// 掌上砚园基础组件的冒烟测试。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zhangshang_yanyuan/main.dart';

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
