/// 教务适配脚本的来源管理。
///
/// 设计目标：让「软件本体」与「对接脚本」解耦 ——
/// 脚本来自拾光课表的适配仓库
/// （https://github.com/ShiGuangSchedule/shiguang_warehouse），
/// 应用内可以单独检查更新、下载最新脚本，无需重新发版；
/// 下载失败或内容校验不通过时继续使用内置副本，保证永远可用。
///
/// 内置副本：assets/js/zqu_upstream.js（上游原文）
/// 桥接层：assets/js/shiguang_bridge_shim.js（固定随 App 发布）
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 适配脚本信息。
class AdapterScript {
  const AdapterScript({
    required this.content,
    required this.isRemote,
    this.updatedAt,
  });

  /// 上游脚本原文（未包 IIFE，注入时再包）。
  final String content;

  /// true 表示用的是应用内下载的最新版，false 表示内置副本。
  final bool isRemote;

  /// 下载时间（仅远程版本有值）。
  final String? updatedAt;

  String get sourceLabel => isRemote ? '已更新（在线下载）' : '内置版本';
}

/// 适配脚本仓库。
class JwglAdapterRepository {
  JwglAdapterRepository._();

  static const String bundledAsset = 'assets/js/zqu_upstream.js';
  static const String shimAsset = 'assets/js/shiguang_bridge_shim.js';

  static const String _prefsKeyScript = 'zsy_adapter_script';
  static const String _prefsKeyTime = 'zsy_adapter_updated_at';

  /// 上游脚本地址（依次尝试，前面失败自动换下一个）。
  static const List<String> remoteUrls = [
    'https://raw.githubusercontent.com/ShiGuangSchedule/shiguang_warehouse/main/resources/ZQU/zqu_01.js',
    'https://cdn.jsdelivr.net/gh/ShiGuangSchedule/shiguang_warehouse@main/resources/ZQU/zqu_01.js',
  ];

  static AdapterScript? _cache;

  /// 读取内置脚本原文。
  static Future<String> loadBundled() =>
      rootBundle.loadString(bundledAsset);

  /// 读取桥接层脚本。
  static Future<String> loadShim() => rootBundle.loadString(shimAsset);

  /// 当前生效的脚本：有在线更新的用更新版，否则用内置。
  static Future<AdapterScript> load() async {
    if (_cache != null) return _cache!;

    final sp = await SharedPreferences.getInstance();
    final remote = sp.getString(_prefsKeyScript);
    if (remote != null && remote.trim().isNotEmpty && _looksValid(remote)) {
      return _cache = AdapterScript(
        content: remote,
        isRemote: true,
        updatedAt: sp.getString(_prefsKeyTime),
      );
    }
    return _cache = AdapterScript(content: await loadBundled(), isRemote: false);
  }

  /// 拼出实际注入 WebView 的脚本：桥接 shim + IIFE 包裹的上游脚本。
  static String compose(String shim, String upstream) =>
      '$shim\n(function () {\n$upstream\n})();\n';

  /// 从上游下载最新脚本。成功返回新脚本信息，失败抛异常（保留原脚本）。
  static Future<AdapterScript> checkUpdate() async {
    final body = await _downloadFirstAvailable();
    if (!_looksValid(body)) {
      throw const AdapterException('下载到的内容不像适配脚本，已放弃更新');
    }

    final sp = await SharedPreferences.getInstance();
    final now = DateTime.now().toIso8601String();
    await sp.setString(_prefsKeyScript, body);
    await sp.setString(_prefsKeyTime, now);

    return _cache = AdapterScript(
      content: body,
      isRemote: true,
      updatedAt: now,
    );
  }

  /// 恢复为内置脚本。
  static Future<void> resetToBundled() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_prefsKeyScript);
    await sp.remove(_prefsKeyTime);
    _cache = null;
  }

  /// 简单校验：必须包含官方脚本的关键标识，避免把错误页存成脚本。
  static bool _looksValid(String s) {
    if (s.length < 2000) return false;
    return s.contains('xsgrkbcx!') && s.contains('runImportFlow');
  }

  static Future<String> _downloadFirstAvailable() async {
    Object? lastError;
    for (final url in remoteUrls) {
      try {
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 15);
        final req = await client.getUrl(Uri.parse(url));
        req.headers.set(HttpHeaders.userAgentHeader, 'ZQUmobile/掌上砚园');
        final resp = await req.close();
        if (resp.statusCode != 200) {
          lastError = AdapterException('HTTP ${resp.statusCode}');
          client.close(force: true);
          continue;
        }
        final body = await resp.transform(utf8.decoder).join();
        client.close(force: true);
        if (body.trim().isNotEmpty) return body;
        lastError = const AdapterException('返回内容为空');
      } catch (e) {
        lastError = e;
      }
    }
    throw AdapterException('从上游下载脚本失败：${lastError ?? '未知错误'}');
  }
}

/// 适配脚本相关异常。
class AdapterException implements Exception {
  const AdapterException(this.message);

  final String message;

  @override
  String toString() => message;
}
