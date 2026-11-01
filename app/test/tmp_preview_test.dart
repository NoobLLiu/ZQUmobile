/// 临时预览测试：渲染首页截图，用完即删。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zhangshang_yanyuan/main.dart';

final String _profile = jsonEncode({
  'studentId': '202301010101',
  'term': '2026-2027-1',
  'hasCampusNetwork': true,
  'webvpnPassword': 'vpn-pass',
  'jwglPassword': 'jwgl-pass',
});

Future<void> _loadFont() async {
  final bytes = await File(
          r'C:\Users\BrianLiu\AppData\Local\Temp\simhei.ttf')
      .readAsBytes();
  final loader = FontLoader('Microsoft YaHei')
    ..addFont(Future.value(ByteData.view(bytes.buffer)));
  await loader.load();
}

void main() {
  Future<void> shoot(WidgetTester tester, Brightness brightness, String name) async {
    tester.platformDispatcher.platformBrightnessTestValue = brightness;
    SharedPreferences.setMockInitialValues({'zsy_profile': _profile});
    await tester.pumpWidget(const ZhangShangZhaoYuanApp());
    await tester.pumpAndSettle();
    await expectLater(
        find.byType(MaterialApp), matchesGoldenFile('preview_$name.png'));
  }

  testWidgets('preview dark', (tester) async {
    await _loadFont();
    tester.view.physicalSize = const Size(760, 1640);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await shoot(tester, Brightness.dark, 'dark');
  });

  testWidgets('preview light', (tester) async {
    await _loadFont();
    tester.view.physicalSize = const Size(760, 1640);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await shoot(tester, Brightness.light, 'light');
  });
}
