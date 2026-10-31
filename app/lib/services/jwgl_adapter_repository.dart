/// 教务适配脚本的加载。
///
/// 脚本以**文件形式内置在项目里**（assets/js/zqu_upstream.js），
/// 随应用一起发布，不依赖网络、不在运行时下载或改写。
/// 这样每次导入的行为都是确定的，不会出现「下载到半截脚本」的情况。
///
/// 文件组成：
///   assets/js/zqu_upstream.js          —— shiguang_warehouse 上游 zqu_01.js 原文
///   assets/js/shiguang_bridge_shim.js  —— 把官方的 bridge 调用映射到本 App
///   assets/js/webvpn_captcha_solver.js —— WebVPN 滑块验证码自动求解
///   assets/js/auto_login.js            —— 代填账号密码 / 点登录 / 推进到教务主页
///
/// 更新适配脚本的方式：替换这些文件后重新构建发版。
library;

import 'package:flutter/services.dart';

/// 适配脚本加载器。
class JwglAdapterRepository {
  JwglAdapterRepository._();

  static const String bundledAsset = 'assets/js/zqu_upstream.js';
  static const String shimAsset = 'assets/js/shiguang_bridge_shim.js';

  /// WebVPN 滑块验证码自动求解脚本。
  static const String captchaSolverAsset = 'assets/js/webvpn_captcha_solver.js';

  /// 自动登录编排脚本（代填账号密码 + 点登录 + 推进到教务主页）。
  static const String autoLoginAsset = 'assets/js/auto_login.js';

  static String? _upstreamCache;
  static String? _shimCache;
  static String? _captchaSolverCache;
  static String? _autoLoginCache;

  /// 读取内置的上游适配脚本原文。
  static Future<String> loadUpstream() async =>
      _upstreamCache ??= await rootBundle.loadString(bundledAsset);

  /// 读取桥接层脚本。
  static Future<String> loadShim() async =>
      _shimCache ??= await rootBundle.loadString(shimAsset);

  /// 读取 WebVPN 滑块验证码求解脚本。
  ///
  /// 脚本自带幂等与轮询逻辑，页面每次加载完成后注入一次即可：
  /// 它会自动等待滑块弹窗出现，完成识别、拖动与重试。
  static Future<String> loadCaptchaSolver() async =>
      _captchaSolverCache ??= await rootBundle.loadString(captchaSolverAsset);

  /// 读取自动登录编排脚本。
  ///
  /// 每次页面加载完成后注入一次：脚本按页面形态（WebVPN 登录页 /
  /// 教务登录页 / 其他页）自行决定该填什么、点哪个按钮。
  static Future<String> loadAutoLogin() async =>
      _autoLoginCache ??= await rootBundle.loadString(autoLoginAsset);

  /// 拼出实际注入 WebView 的脚本：桥接 shim + 用 IIFE 包裹的上游脚本。
  ///
  /// 包 IIFE 是为了隔离作用域 —— 上游脚本顶层有 const 声明，
  /// 重复点「执行导入」时直接注入会报「Identifier has already been declared」。
  static String compose(String shim, String upstream) =>
      '$shim\n(function () {\n$upstream\n})();\n';

  /// 一次性拿到可直接注入的完整脚本。
  static Future<String> loadInjectable() async {
    final shim = await loadShim();
    final upstream = await loadUpstream();
    return compose(shim, upstream);
  }
}
