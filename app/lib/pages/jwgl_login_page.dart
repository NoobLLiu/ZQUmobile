/// 教务系统登录页（内嵌 WebView）。
///
/// 页面结构参照拾光课表的 WebViewScreen（Apache-2.0）：
/// - 顶部只有标题 + 更多菜单（刷新 / 输入网址），不放常驻按钮遮挡网页；
/// - 底部一条操作栏：左侧引导文字，右侧「执行导入」按钮；
/// - 加载进度以细进度条浮在 WebView 顶部。
///
/// 打开本页即进入**自动登录**：盖一层「自动登录中」的小弹窗，
/// 由注入的 assets/js/auto_login.js 代填账号密码、点登录、推进到教务主页：
///   WebVPN 登录页（滑块由 webvpn_captcha_solver.js 自动完成）
///   → WebVPN 首页（自动点「教务系统」入口）
///   → 教务系统登录页（账号密码代填；图形验证码在弹窗里输入一次）
///   → 教务系统主页（弹窗收起，提示已登录）。
///
/// 取数逻辑**直接使用 shiguang_warehouse 上游的 ZQU 适配脚本原文**
/// （assets/js/zqu_upstream.js），本 App 只提供一个桥接 shim
/// （assets/js/shiguang_bridge_shim.js）把它的 showAlert / saveImportedCourses
/// 等调用映射到 Flutter。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/profile.dart';
import '../models/timetable.dart';
import '../services/captcha_ocr.dart';
import '../services/captcha_templates.dart';
import '../services/jwgl_adapter_repository.dart';
import '../services/profile_repository.dart';
import '../services/jwgl_service.dart';
import '../services/timetable_repository.dart';
import '../widgets/conflict_dialog.dart';

/// 教务系统页面。
///
/// 两种用法：
///   - 纯登录（[allowImport] = false）：从首页「教务系统」进入，
///     只做快捷访问与自动登录，不提供导入功能；
///   - 导入模式（[allowImport] = true）：从课表页进入，
///     底部提供「执行导入」抓取课表。
class JwglLoginPage extends StatefulWidget {
  const JwglLoginPage({super.key, this.allowImport = false});

  /// 是否显示「执行导入」（抓取课表）。
  /// 首页进入时只登录，不做导入。
  final bool allowImport;

  @override
  State<JwglLoginPage> createState() => _JwglLoginPageState();
}

class _JwglLoginPageState extends State<JwglLoginPage> {
  WebViewController? _controller;

  /// 注入脚本 = 桥接 shim + 上游适配脚本。
  String? _injectJs;

  /// WebVPN 滑块验证码自动求解脚本。
  String? _captchaSolverJs;

  /// 自动登录编排脚本。
  String? _autoLoginJs;

  /// 已购校园网：校内直连教务系统。
  static const String campusUrl = 'https://jwgl.zqu.edu.cn/';

  /// 未购校园网：先经 WebVPN 进入，再从功能页进教务系统。
  ///
  /// 用 `webvpn.zqu.edu.cn`（不是 `webvpn-free`）：缺口是蓝色拼图块，
  /// 可用 HSV 颜色分割精确定位；`webvpn-free` 的缺口颜色随背景变化不可靠。
  /// 且 `jwgl.zqu.edu.cn` 的 302 也跳到这里。
  static const String webvpnUrl = 'https://webvpn.zqu.edu.cn/';

  double _progress = 0;
  bool _loadingPage = true;
  bool _fetching = false;
  String _pageTitle = '教务系统';
  String _status = '正在自动登录 ...';
  String? _error;

  /// 通用个人信息（学号 / 两套密码 / 学期 / 校园网）。
  Profile _profile = const Profile();

  /// 注入脚本后等待回传的令牌，用于兜底「点了没反应」。
  int _fetchToken = 0;

  // ---- 自动登录状态 ----
  /// 「自动登录中」弹窗是否显示。
  bool _autoVisible = true;

  /// 弹窗是否挡住网页（true 时盖一层深色蒙层；false 时只浮一个卡片）。
  bool _autoBlocking = true;

  /// 弹窗里的当前步骤文案。
  String _autoStep = '正在准备登录 ...';

  /// 是否正在等用户输入图形验证码。
  bool _autoCaptcha = false;

  /// 验证码图片（由页面内 canvas 转成 dataURL 回传）。
  Uint8List? _captchaBytes;

  /// 验证码位数（按图片宽度推算），输满即自动提交。
  int _captchaExpected = 0;

  /// 离线识别器的训练样本（登录时用来代填验证码；为空则走手动输入）。
  CaptchaTemplates _templates = CaptchaTemplates();

  /// 本轮登录已用识别结果自动提交过几次（防止瞎猜把账号试到锁定）。
  int _ocrAttempts = 0;

  /// 一次登录流程里最多自动提交几次识别结果。
  static const int _maxOcrAttempts = 2;

  /// 本轮登录里因「识别没把握」自动换图的次数。
  int _ocrRefreshes = 0;

  /// 换图上限：超过就转手动输入（避免无限刷 /yzm 触发接口限流）。
  static const int _maxOcrRefreshes = 4;

  /// 验证码识别的辅助提示（识别没把握时提示已填入的内容）。
  String? _ocrHint;

  /// 待确认的验证码：登录成功时把它当作带标签样本收进模板。
  Uint8List? _pendingCaptchaBytes;
  String _pendingCaptchaText = '';

  /// 教务登录已提交：提交后页面跳走即视为成功（失败只弹窗、不跳转）。
  bool _submittedJwgl = false;

  final TextEditingController _captchaCtrl = TextEditingController();
  Timer? _autoSlowTimer;

  // ---- 官方脚本分段落库的累积区 ----
  List<Course>? _accCourses;
  List<TimeSlot>? _accSlots;
  int _accTotalWeeks = 0;
  String _accStartDate = '';
  String _accTermName = '';

  /// 「执行导入」是否可用（拿到脚本后才可用）。
  bool get _ready => _controller != null && _injectJs != null;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _autoSlowTimer?.cancel();
    _captchaCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    // 适配脚本以文件形式内置在项目里，随应用发布，不做运行时下载
    final injectable = await JwglAdapterRepository.loadInjectable();
    final solver = await JwglAdapterRepository.loadCaptchaSolver();
    final autoLogin = await JwglAdapterRepository.loadAutoLogin();
    final profile = await ProfileRepository.load();
    // 训练页攒下的字形样本：有就代填验证码，没有就完全走手动
    final templates = await CaptchaTemplateRepository.load();
    if (!mounted) return;

    // 入口由「是否已购校园网」决定
    final entryUrl = profile.hasCampusNetwork ? campusUrl : webvpnUrl;

    setState(() {
      _injectJs = injectable;
      _captchaSolverJs = solver;
      _autoLoginJs = autoLogin;
      _profile = profile;
      _templates = templates;
    });

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFFFFFFF))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) {
            if (!mounted) return;
            setState(() {
              _progress = p / 100;
              _loadingPage = p < 100;
            });
          },
          onPageStarted: (url) {
            if (!mounted) return;
            setState(() {
              _loadingPage = true;
              _error = null;
            });
          },
          onPageFinished: (url) {
            if (!mounted) return;
            setState(() => _loadingPage = false);
            _controller?.getTitle().then((t) {
              if (!mounted || t == null || t.isEmpty) return;
              setState(() => _pageTitle = t);
            });
            // 每次页面加载完成：挂滑块求解器，再跑一遍自动登录编排
            _injectCaptchaSolver();
            _startAutoLogin();
          },
          onWebResourceError: (err) {
            if (!mounted) return;
            if (err.isForMainFrame ?? false) {
              setState(() => _error = '页面打开失败：${err.description}');
            }
          },
        ),
      )
      // 通道名必须与 shim 里的 window.zsyBridge 一致
      ..addJavaScriptChannel(
        'zsyBridge',
        onMessageReceived: (message) => _onBridgeMessage(message.message),
      )
      ..loadRequest(Uri.parse(entryUrl));

    if (!mounted) return;
    setState(() => _controller = controller);

    // 兜底：45 秒还没跑完就不要一直挡着网页
    _autoSlowTimer = Timer(const Duration(seconds: 45), () {
      if (!mounted || !_autoVisible) return;
      setState(() {
        _autoBlocking = false;
        _autoStep = '自动登录耗时较长，可直接在页面上操作';
      });
    });
  }

  // ------------------------------------------------------------------ 回传处理

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _fetching = false;
      _error = message;
      _status = '导入失败';
    });
  }

  /// 只看消息类型，避免不同类型的回传进入导入协议解析。
  String? _peekBridgeType(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return (decoded['type'] ?? '').toString();
      }
    } on FormatException {
      /* 忽略 */
    }
    return null;
  }

  void _onBridgeMessage(String raw) {
    if (!mounted) return;

    final type = _peekBridgeType(raw);
    if (type == 'captcha') {
      _onCaptchaMessage(raw);
      return;
    }
    if (type == 'autologin') {
      _onAutoMessage(raw);
      return;
    }

    final JwglBridgeMessage msg;
    try {
      msg = parseBridgeMessage(raw);
    } on JwglException catch (e) {
      _fail(e.message);
      return;
    }

    if (msg.isProgress) {
      setState(() {
        _status = msg.message ?? _status;
        _error = null;
      });
      return;
    }

    if (msg.isFailed) {
      _fail(msg.error ?? '导入失败');
      return;
    }

    // 脚本需要输入（选学期 / 确认开学日期），自动应答后回填结果
    if (msg.type == 'request') {
      _handleRequest(msg);
      return;
    }

    // 官方脚本分段回传
    final j = msg.json;
    switch (msg.type) {
      case 'term':
        _accTermName = (j?['termName'] ?? '').toString();
        if (_accTermName.isNotEmpty) {
          setState(() => _status = '已选择学期：$_accTermName');
        }
        return;

      case 'courses':
        final list = ((j?['courses'] as List?) ?? [])
            .whereType<Map<String, dynamic>>()
            .map(Course.fromJson)
            .toList();
        if (list.isEmpty) {
          _fail('未获取到课表数据，请确认该学期已选课。');
          return;
        }
        _accCourses = list;
        setState(() => _status = '已获取 ${list.length} 门课程，正在读取学期信息 ...');
        return;

      case 'config':
        final cfg = (j?['config'] as Map<String, dynamic>?) ?? const {};
        _accTotalWeeks = (cfg['semesterTotalWeeks'] as num?)?.toInt() ?? 0;
        _accStartDate = (cfg['semesterStartDate'] ?? '').toString();
        setState(() => _status = '正在写入作息时间 ...');
        return;

      case 'slots':
        final list = ((j?['slots'] as List?) ?? [])
            .whereType<Map<String, dynamic>>()
            .map(TimeSlot.fromJson)
            .toList();
        if (list.isNotEmpty) _accSlots = list;
        return;

      case 'done':
        _finalize();
        return;

      case 'result':
        // 旧格式一次性结果，兼容保留
        if (msg.isSuccess) {
          _saveResult(msg.result!);
        }
        return;
    }
  }

  // ---------------------------------------------------- 自动登录回传

  void _onAutoMessage(String raw) {
    Map<String, dynamic>? j;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) j = decoded;
    } on FormatException {
      return;
    }
    if (j == null) return;

    final state = (j['state'] ?? '').toString();
    final message = (j['message'] ?? '').toString();

    switch (state) {
      case 'progress':
      case 'submitting':
      case 'slider':
      case 'entering-jwgl':
        setState(() {
          if (message.isNotEmpty) _autoStep = message;
          _autoCaptcha = false;
          _status = message.isNotEmpty ? message : _status;
        });
        return;

      case 'submitted':
      case 'jwgl-ok':
        // 教务登录已提交/已通过：之后页面跳走就算成功
        _submittedJwgl = true;
        setState(() {
          _autoStep = message.isNotEmpty ? message : '正在登录教务系统 ...';
          _autoCaptcha = false;
        });
        if (state == 'jwgl-ok') _harvestConfirmedCaptcha();
        return;

      case 'captcha':
        final bytes = _decodeDataUrl(j['image']);
        final expected = (j['expected'] as num?)?.toInt() ?? 0;
        setState(() {
          _autoStep = message.isNotEmpty ? message : '请输入图中验证码';
          _autoCaptcha = true;
          _autoBlocking = true;
          _captchaBytes = bytes;
          _captchaExpected = expected;
          _ocrHint = null;
        });
        // 有训练样本就试一次离线识别；没把握则保留输入框
        if (bytes != null) _tryOcr(bytes, expected);
        return;

      case 'need-help':
        // 需要用户自己点一下入口：放开蒙层，但保留提示卡片
        setState(() {
          _autoStep = message.isNotEmpty ? message : '请在页面上点一下入口';
          _autoBlocking = false;
        });
        return;

      case 'done':
        _finishAutoLogin(message);
        return;

      case 'failed':
        _stopAutoLogin(
          message.isNotEmpty ? message : '自动登录失败，请手动操作',
          showError: true,
        );
        return;
    }
  }

  Uint8List? _decodeDataUrl(Object? value) {
    final s = (value ?? '').toString();
    final i = s.indexOf(',');
    if (i < 0) return null;
    try {
      return base64Decode(s.substring(i + 1));
    } catch (_) {
      return null;
    }
  }

  /// 试一次离线识别。
  ///
  /// 三道闸门，任何一道不过就退回手动输入（避免瞎猜）：
  ///   1. 有训练样本；
  ///   2. 能稳定切出 4~6 个字，且位数与图片宽度推算的一致；
  ///   3. 每个字的置信度与区分度都过关（[CaptchaOcr.minScore] / [CaptchaOcr.minMargin]）。
  void _tryOcr(Uint8List bytes, int expected) {
    if (_templates.isEmpty) return;
    if (_ocrAttempts >= _maxOcrAttempts) {
      setState(() => _ocrHint = '已自动尝试 $_maxOcrAttempts 次，请手动输入');
      return;
    }

    final pred = CaptchaOcr.predict(bytes, _templates);
    final lengthOk = pred != null &&
        (expected <= 0 || pred.text.length == expected);
    if (pred != null && pred.ok && lengthOk) {
      _ocrAttempts++;
      setState(() {
        _autoCaptcha = false;
        _autoStep = '已识别「${pred.text}」，正在登录 ...';
      });
      _submitCaptchaText(pred.text);
      return;
    }

    // 识别没把握：自动换一张再认（用户要求）。每张验证码能认准的概率有限，
    // 换几张里总有一张简单的；换图次数用完才退回手动输入。
    final reason = pred == null
        ? '切字失败'
        : (lengthOk ? (pred.reason ?? '置信度不足') : '位数不符');
    if (_ocrRefreshes < _maxOcrRefreshes) {
      _ocrRefreshes++;
      _refreshCaptcha();
      setState(() {
        _autoStep = '这张不好认（$reason），自动换一张'
            '（$_ocrRefreshes/$_maxOcrRefreshes）...';
      });
      return;
    }

    // 换图次数也用完了：把猜测填进输入框，用户核对一下就能提交
    if (pred != null && lengthOk && !pred.text.contains('?')) {
      _captchaCtrl.text = pred.text;
    }
    setState(() {
      _ocrHint = '连续 $_maxOcrRefreshes 张都没把握（$reason）'
          '${_captchaCtrl.text.isEmpty ? '' : '，已填入猜测值请核对'}';
    });
  }

  /// 滑块求解器的进度回传（来自 webvpn_captcha_solver.js，独立类型）。
  void _onCaptchaMessage(String raw) {
    Map<String, dynamic>? j;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) j = decoded;
    } on FormatException {
      return;
    }
    if (j == null) return;
    final state = (j['state'] ?? '').toString();
    final message = (j['message'] ?? '').toString();
    if (message.isEmpty) return;

    setState(() {
      _status = message;
      // 弹窗在的时候把滑块进度也显示在弹窗里
      if (_autoVisible && !_autoCaptcha) _autoStep = message;
      if (state == 'solved') _error = null;
      if (state == 'failed') {
        // 自动验证失败：放开蒙层，用户可以手动拖动
        _autoBlocking = false;
      }
    });
  }

  void _finishAutoLogin(String message) {
    _autoSlowTimer?.cancel();
    setState(() {
      _autoVisible = false;
      _autoCaptcha = false;
      _ocrHint = null;
      _status = message.isNotEmpty ? message : '已登录教务系统';
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message.isNotEmpty ? message : '已登录教务系统'),
        duration: const Duration(seconds: 3),
      ));
  }

  /// 停止自动登录：收起弹窗，把页面交还用户。
  void _stopAutoLogin(String message, {bool showError = false}) {
    _autoSlowTimer?.cancel();
    _controller?.runJavaScript(
      'window.__zsyAutoLogin && window.__zsyAutoLogin.stop();',
    );
    if (!mounted) return;
    setState(() {
      _autoVisible = false;
      _autoCaptcha = false;
      _ocrHint = null;
      _captchaCtrl.clear();
      if (showError) _error = message;
      _status = message;
    });
  }

  /// 验证码输满位数即自动提交，省掉一次点击。
  void _onCaptchaChanged(String value) {
    if (!_autoCaptcha) return;
    final expect = _captchaExpected;
    if (expect > 0 && value.trim().length >= expect) {
      _submitCaptcha();
    }
  }

  /// 用户手动输入验证码后提交。
  Future<void> _submitCaptcha() async {
    final text = _captchaCtrl.text.trim();
    if (text.isEmpty) return;
    await _submitCaptchaText(text);
  }

  /// 把验证码交给页面回填并提交（手动输入与离线识别共用）。
  Future<void> _submitCaptchaText(String text) async {
    final c = _controller;
    if (c == null) return;
    // 记下「图 + 答案」，登录成功后就能当成带标签样本收录
    _pendingCaptchaBytes = _captchaBytes;
    _pendingCaptchaText = text.trim().toUpperCase();
    setState(() {
      _autoCaptcha = false;
      _ocrHint = null;
      _autoStep = '正在登录教务系统 ...';
    });
    try {
      await c.runJavaScript(
        'window.__zsyAutoLogin && window.__zsyAutoLogin.submitCaptcha('
        '${jsonEncode(text)});',
      );
    } catch (_) {
      /* 页面已跳走时忽略 */
    }
    _captchaCtrl.clear();
  }

  /// 教务回包 status=y 时，把刚才那张验证码连同答案收为训练样本。
  ///
  /// 这是零成本的样本回流：标签由教务自己确认，不会污染模板；
  /// 对校外用户还有额外意义——直连取不到 `/yzm` 时，只能靠这条路攒样本。
  Future<void> _harvestConfirmedCaptcha() async {
    final bytes = _pendingCaptchaBytes;
    final text = _pendingCaptchaText;
    _pendingCaptchaBytes = null;
    _pendingCaptchaText = '';
    if (bytes == null || text.isEmpty) return;

    final seg = CaptchaOcr.segment(bytes);
    if (seg == null || seg.glyphs.length != text.length) return;
    for (var i = 0; i < text.length; i++) {
      _templates.add(text[i], seg.glyphs[i].pixels);
    }
    await CaptchaTemplateRepository.save(_templates);
  }

  /// 换一张验证码。
  Future<void> _refreshCaptcha() async {
    final c = _controller;
    if (c == null) return;
    _captchaCtrl.clear();
    setState(() {
      _autoCaptcha = true;
      _ocrHint = null;
      _autoStep = '正在获取新的验证码 ...';
    });
    try {
      await c.runJavaScript(
        'window.__zsyAutoLogin && window.__zsyAutoLogin.refreshCaptcha();',
      );
    } catch (_) {
      /* 忽略 */
    }
  }

  // ---------------------------------------------------- 自动登录回传结束

  // ---------------------------------------------------- 脚本注入

  /// 注入滑块验证码求解器。
  ///
  /// 脚本只在 WebVPN 登录域起作用：它轮询 #drag-captcha-layer，
  /// 其他页面（教务系统、WebVPN 功能页）上什么都不做。
  Future<void> _injectCaptchaSolver() async {
    final js = _captchaSolverJs;
    final c = _controller;
    if (c == null || js == null) return;
    try {
      await c.runJavaScript(js);
    } catch (_) {
      /* 页面尚未就绪时忽略，下次加载会再试 */
    }
  }

  /// 注入自动登录编排脚本并启动。
  ///
  /// [expect] 告诉脚本「接下来该到哪个系统」：
  ///   - webvpn：当前在外面，先登录 WebVPN，再想办法进教务；
  ///   - jwgl：当前应该就是教务（校内直连，或已提交过教务登录）。
  Future<void> _startAutoLogin() async {
    final js = _autoLoginJs;
    final c = _controller;
    if (c == null || js == null || !_autoVisible) return;

    // 每次页面加载都是新一轮登录：重置识别代填的尝试次数
    _ocrAttempts = 0;
    _ocrRefreshes = 0;

    final profile = _profile;
    final expect = (profile.hasCampusNetwork || _submittedJwgl)
        ? 'jwgl'
        : 'webvpn';
    final cfg = jsonEncode({
      'sid': profile.studentId.trim(),
      'jwglPwd': profile.jwglPassword,
      'webvpnPwd': profile.webvpnPassword,
      'expect': expect,
      'submitted': _submittedJwgl,
    });

    try {
      await c.runJavaScript(js);
      await c.runJavaScript(
        'window.__zsyAutoLogin && window.__zsyAutoLogin.start($cfg);',
      );
    } catch (_) {
      /* 页面尚未就绪时忽略：下次加载会再跑 */
    }
  }

  // ---------------------------------------------------- 脚本请求（自动应答）

  /// 处理脚本发来的用户输入请求：选学期 / 确认开学日期。
  ///
  /// 不再弹窗，直接自动应答：
  ///   - 学期：优先用个人信息里选的学期，其次用脚本给的默认索引；
  ///   - 开学日期：直接采用脚本默认返回的日期（无效时留空，交给落库兜底）。
  Future<void> _handleRequest(JwglBridgeMessage msg) async {
    final j = msg.json ?? const <String, dynamic>{};
    final reqId = (j['requestId'] ?? '').toString();
    final reqType = (j['requestType'] ?? '').toString();
    final payload = (j['payload'] as Map<String, dynamic>?) ?? const {};

    Object? value;

    if (reqType == 'term') {
      final items = ((payload['items'] as List?) ?? [])
          .map((e) => e.toString())
          .toList();
      // 自动选择：优先用个人信息里选的学期，其次用脚本给的默认索引
      var def = (payload['defaultIndex'] as num?)?.toInt() ?? 0;
      final hit = items.indexOf(_profile.term.trim());
      if (hit >= 0) def = hit;
      if (def < 0) def = 0;
      if (items.isNotEmpty && def >= items.length) def = items.length - 1;
      if (items.isNotEmpty) {
        _accTermName = items[def];
        setState(() => _status = '已自动选择学期：$_accTermName');
      }
      value = def;
    } else if (reqType == 'startDate') {
      // 自动确认：直接采用脚本默认返回的开学日期
      final def = (payload['defaultText'] ?? '').toString().trim();
      final valid = RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(def);
      value = valid ? def : '';
      if (valid) {
        setState(() => _status = '已自动确认开学日期：$def');
      }
    }

    await _resolveRequest(reqId, value);
  }

  /// 把用户选择回填给页面里的脚本。
  Future<void> _resolveRequest(String reqId, Object? value) async {
    final c = _controller;
    if (c == null || reqId.isEmpty) return;
    try {
      await c.runJavaScript(
        'window.__zsyResolve(${jsonEncode(reqId)}, ${jsonEncode(value)});',
      );
    } catch (_) {
      /* 页面已跳走时忽略 */
    }
  }

  /// 官方脚本跑完（done）：把累积到的三段数据组装成课表并落库。
  Future<void> _finalize() async {
    var courses = _accCourses;
    if (courses == null || courses.isEmpty) {
      _fail('导入流程结束，但没有收到课程数据。\n请确认已登录教务系统，并停留在教务系统内的页面。');
      return;
    }

    // 同一时段有多门课时，让用户决定保留哪一门
    final conflicts = findCourseConflicts(courses);
    if (conflicts.isNotEmpty && mounted) {
      setState(() => _fetching = true);
      final resolved = await showConflictResolver(context, conflicts, courses);
      if (resolved != null) courses = resolved;
      if (!mounted) return;
    }

    // 总周数：优先用官方脚本给的配置，否则取课程里最大的周次
    var totalWeeks = _accTotalWeeks;
    if (totalWeeks <= 0) {
      for (final c in courses) {
        for (final w in c.weeks) {
          if (w > totalWeeks) totalWeeks = w;
        }
      }
    }
    if (totalWeeks <= 0) totalWeeks = 20;

    // 开学日期：官方脚本没给就退回本周周一，保证周次至少能算
    var startDate = _accStartDate;
    if (startDate.isEmpty) {
      final now = DateTime.now();
      final monday = now.subtract(Duration(days: now.weekday - 1));
      startDate =
          '${monday.year.toString().padLeft(4, '0')}-'
          '${monday.month.toString().padLeft(2, '0')}-'
          '${monday.day.toString().padLeft(2, '0')}';
    }

    final slots =
        _accSlots ?? kPresetTimeSlots.map((e) => TimeSlot.fromJson(e)).toList();

    final tt = Timetable(
      term: '',
      // 学期名取用户在「选择学期」里选中的那一项；
      // 拿不到时退回个人信息里设置的学期（不要用网页标题）
      termName: _accTermName.isNotEmpty ? _accTermName : _profile.term,
      totalWeeks: totalWeeks,
      semesterStartDate: startDate,
      courses: courses,
      timeSlots: slots,
      fetchedAt: DateTime.now().toIso8601String(),
    );

    await TimetableRepository.save(tt);
    await TimetableRepository.setLoggedIn(true);
    if (!mounted) return;

    setState(() {
      _fetching = false;
      _status = '导入成功，共 ${tt.courses.length} 门课程';
      _accCourses = null;
      _accSlots = null;
      _accTotalWeeks = 0;
      _accStartDate = '';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('课表导入成功，共 ${tt.courses.length} 门课程')),
    );
    Navigator.of(context).pop(true);
  }

  /// 兼容旧格式：一次性结果直接落库。
  Future<void> _saveResult(JwglFetchResult result) async {
    final slots = result.timeSlots.isNotEmpty
        ? result.timeSlots
        : kPresetTimeSlots.map((e) => Map<String, dynamic>.from(e)).toList();

    final tt = Timetable(
      term: result.term,
      termName: result.termName,
      totalWeeks: result.totalWeeks > 0 ? result.totalWeeks : 20,
      semesterStartDate: result.semesterStartDate,
      courses: result.courses.map(Course.fromJson).toList(),
      timeSlots: slots.map(TimeSlot.fromJson).toList(),
      fetchedAt: DateTime.now().toIso8601String(),
    );

    await TimetableRepository.save(tt);
    await TimetableRepository.setLoggedIn(true);
    if (!mounted) return;

    setState(() {
      _fetching = false;
      _status = '导入成功，共 ${tt.courses.length} 门课程';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('课表导入成功，共 ${tt.courses.length} 门课程')),
    );
    Navigator.of(context).pop(true);
  }

  // ------------------------------------------------------------------ 导入

  /// 点「执行导入」：注入桥接 shim + 上游适配脚本。
  Future<void> _startImport() async {
    final controller = _controller;
    final js = _injectJs;
    if (controller == null || js == null || _fetching) return;

    // 手动导入说明用户要自己接管，先停掉自动登录编排
    if (_autoVisible) _stopAutoLogin('已切换为手动操作');

    final token = ++_fetchToken;
    _accCourses = null;
    _accSlots = null;
    _accTotalWeeks = 0;
    _accStartDate = '';
    _accTermName = '';

    setState(() {
      _fetching = true;
      _error = null;
      _status = '正在导入，请稍候 ...';
    });

    try {
      await controller.runJavaScript(js);
    } catch (e) {
      if (!mounted) return;
      _fail('脚本注入失败：$e');
      return;
    }

    // 兜底：20 秒内没有任何回传，说明脚本没跑起来
    await Future.delayed(const Duration(seconds: 20));
    if (!mounted || token != _fetchToken || !_fetching) return;
    _fail(
      '没有收到教务系统的响应。\n请确认：① 已登录教务系统；'
      '② 当前停留在教务系统内的页面（不是 WebVPN 首页）。',
    );
  }

  Future<void> _reload() => _controller?.reload() ?? Future.value();

  /// 菜单里的「输入网址」：用于在校内直连与 WebVPN 之间切换。
  Future<void> _editUrl() async {
    final controller = _controller;
    if (controller == null) return;

    final current = await controller.currentUrl();
    final fallback = _profile.hasCampusNetwork ? campusUrl : webvpnUrl;
    final input = TextEditingController(
      text: (current == null || current == 'about:blank') ? fallback : current,
    );

    if (!mounted) return;
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('输入网址'),
        content: TextField(
          controller: input,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            hintText: 'https://jwgl.zqu.edu.cn/',
            helperText: '校外可填 https://webvpn.zqu.edu.cn/',
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(input.text),
            child: const Text('打开'),
          ),
        ],
      ),
    );

    final trimmed = (url ?? '').trim();
    if (trimmed.isEmpty) return;
    final full = trimmed.startsWith('http') ? trimmed : 'https://$trimmed';
    await controller.loadRequest(Uri.parse(full));
  }

  // ------------------------------------------------------------------ UI

  /// 「自动登录中」弹窗：小卡片 + 转圈，正常状态下盖住下面的网页。
  Widget _buildAutoOverlay(ThemeData theme) {
    return Positioned.fill(
      child: Stack(
        children: [
          // 蒙层：遮挡时吃掉点击，不遮挡时透传
          Positioned.fill(
            child: _autoBlocking
                ? const ColoredBox(color: Color(0x99000000))
                : IgnorePointer(
                    child: const ColoredBox(color: Color(0x22000000)),
                  ),
          ),
          Align(
            alignment: _autoBlocking
                ? Alignment.center
                : Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Material(
                elevation: 8,
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: 300,
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.2),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '自动登录中',
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _autoStep,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                      if (_autoCaptcha) ...[
                        const SizedBox(height: 12),
                        GestureDetector(
                          onTap: _refreshCaptcha,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: theme.colorScheme.outlineVariant,
                              ),
                            ),
                            child: _captchaBytes == null
                                ? SizedBox(
                                    height: 40,
                                    width: 180,
                                    child: Center(
                                      child: Text(
                                        '点此重新获取验证码',
                                        style: theme.textTheme.bodySmall,
                                      ),
                                    ),
                                  )
                                : Image.memory(
                                    _captchaBytes!,
                                    height: 44,
                                    fit: BoxFit.contain,
                                    gaplessPlayback: true,
                                  ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (_ocrHint != null) ...[
                          Text(
                            _ocrHint!,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontSize: 11.5,
                            ),
                          ),
                          const SizedBox(height: 6),
                        ],
                        TextField(
                          controller: _captchaCtrl,
                          autofocus: true,
                          maxLength: _captchaExpected > 0 ? _captchaExpected : 8,
                          textCapitalization: TextCapitalization.characters,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 18,
                            letterSpacing: 4,
                            fontWeight: FontWeight.w600,
                          ),
                          decoration: const InputDecoration(
                            isDense: true,
                            counterText: '',
                            hintText: '输入验证码',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: _onCaptchaChanged,
                          onSubmitted: (_) => _submitCaptcha(),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _submitCaptcha,
                            child: const Text('继续'),
                          ),
                        ),
                      ],
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => _stopAutoLogin('已切换为手动操作'),
                            child: const Text('改为手动'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_pageTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'reload') _reload();
              if (v == 'url') _editUrl();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'reload',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.refresh),
                  title: Text('刷新页面'),
                ),
              ),
              PopupMenuItem(
                value: 'url',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.link),
                  title: Text('输入网址'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (_error != null)
            Material(
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 18,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setState(() => _error = null),
                      icon: Icon(
                        Icons.close,
                        size: 18,
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: Stack(
              children: [
                if (controller == null)
                  const Center(child: CircularProgressIndicator())
                else
                  WebViewWidget(controller: controller),
                if (_loadingPage)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: LinearProgressIndicator(
                      value: _progress > 0 ? _progress : null,
                      minHeight: 2,
                      backgroundColor: Colors.transparent,
                    ),
                  ),
                if (_autoVisible) _buildAutoOverlay(theme),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: !widget.allowImport
          ? null
          : BottomAppBar(
              height: 72,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _fetching
                          ? _status
                          : (_autoVisible
                              ? _autoStep
                              : '登录到教务系统主页后，点击右侧「执行导入」'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    // 自动登录还盖着网页时不允许导入（此时还在登录页，抓不到数据）
                    onPressed: (!_ready || _fetching || (_autoVisible && _autoBlocking))
                        ? null
                        : _startImport,
                    child: _fetching
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('执行导入'),
                  ),
                ],
              ),
            ),
    );
  }
}
