/// 教务系统登录页（内嵌 WebView）。
///
/// 页面结构参照拾光课表的 WebViewScreen（Apache-2.0）：
/// - 顶部只有标题 + 更多菜单（刷新 / 输入网址），不放常驻按钮遮挡网页；
/// - 底部一条操作栏：左侧引导文字，右侧「执行导入」按钮；
/// - 加载进度以细进度条浮在 WebView 顶部。
///
/// 取数逻辑**直接使用 shiguang_warehouse 上游的 ZQU 适配脚本原文**
/// （assets/js/zqu_upstream.js），本 App 只提供一个桥接 shim
/// （assets/js/shiguang_bridge_shim.js）把它的 showAlert / saveImportedCourses
/// 等调用映射到 Flutter。
///
/// 官方脚本按「课程 → 学期配置 → 作息时间 → 完成」分四次回传，
/// 这里逐段累积，收到 done 后一次性组装并落库，任何一段都不会丢。
///
/// WebVPN 的滑块验证码由注入的求解脚本（assets/js/webvpn_captcha_solver.js）
/// 自动完成：识别缺口位置并合成拖动，失败自动换图重试，超过次数交还用户。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/profile.dart';
import '../models/timetable.dart';
import '../services/jwgl_adapter_repository.dart';
import '../services/profile_repository.dart';
import '../services/jwgl_service.dart';
import '../services/timetable_repository.dart';
import '../widgets/conflict_dialog.dart';

/// 教务系统页面。
///
/// 两种用法：
///   - 纯登录（[allowImport] = false）：从首页「教务系统」进入，
///     只做快捷访问与自动填学号，不提供导入功能；
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

  /// 已购校园网：校内直连教务系统。
  static const String campusUrl = 'https://jwgl.zqu.edu.cn/';

  /// 未购校园网：先经 WebVPN 进入，再从功能页进教务系统。
  static const String webvpnUrl = 'https://webvpn-free.zqu.edu.cn/';

  double _progress = 0;
  bool _loadingPage = true;
  bool _fetching = false;
  String _pageTitle = '教务系统';
  String _status = '请在下方网页中登录教务系统（滑块验证将自动完成）';
  String? _error;

  /// 通用个人信息（学号 / 学期 / 校园网）。
  Profile _profile = const Profile();

  /// 登录须知是否已提示过（每次进入页面提示一次）。
  bool _tipsShown = false;

  /// 注入脚本后等待回传的令牌，用于兜底「点了没反应」。
  int _fetchToken = 0;

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

  Future<void> _init() async {
    // 适配脚本以文件形式内置在项目里，随应用发布，不做运行时下载
    final injectable = await JwglAdapterRepository.loadInjectable();
    final solver = await JwglAdapterRepository.loadCaptchaSolver();
    final profile = await ProfileRepository.load();
    if (!mounted) return;

    // 入口由「是否已购校园网」决定
    final entryUrl = profile.hasCampusNetwork ? campusUrl : webvpnUrl;

    setState(() {
      _injectJs = injectable;
      _captchaSolverJs = solver;
      _profile = profile;
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
            // 每次页面加载完成都尝试填入学号（登录页、WebVPN 页各有一处输入框）
            _autofillStudentId();
            // 同时挂上滑块验证码求解器（脚本自带轮询与幂等，重复注入无害）
            _injectCaptchaSolver();
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

    // 打开页面即提示登录须知
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showLoginTipsIfNeeded();
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

  void _onBridgeMessage(String raw) {
    if (!mounted) return;

    // 滑块求解器的进度回传（独立类型，不进入导入协议的解析）
    final preliminaryType = _peekBridgeType(raw);
    if (preliminaryType == 'captcha') {
      _onCaptchaMessage(raw);
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

  // ---------------------------------------------------- 滑块验证码回传

  /// 只看消息类型，不做完整解析（避免 captcha 消息进入导入协议）。
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
      if (state == 'solved') {
        _error = null;
      } else if (state == 'failed') {
        // 交还用户手动处理，不算导入失败
      }
      _status = message;
    });

    // 非导入模式没有底部状态栏，用 SnackBar 让自动求解结果可见
    if (!widget.allowImport && (state == 'solved' || state == 'failed')) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          duration: const Duration(seconds: 3),
          content: Text(message),
        ));
    }
  }

  // ---------------------------------------------------- 滑块验证码回传结束

  // ---------------------------------------------------- 自动填学号 / 须知

  /// 在页面里自动填入学号（不填密码）。
  ///
  /// 教务（URP）与 WebVPN（深信服）的登录框 id/name 各不相同，
  /// 这里按常见命名逐个试；已填过内容的输入框不覆盖。
  Future<void> _autofillStudentId() async {
    final id = _profile.studentId.trim();
    final c = _controller;
    if (c == null || id.isEmpty) return;

    final js =
        '''
(function (sid) {
  var sels = [
    '#yhm', 'input[name="yhm"]',
    '#username', 'input[name="username"]',
    '#userName', 'input[name="userName"]',
    '#account', 'input[name="account"]',
    '#loginName', 'input[name="loginName"]',
    '#svpn_name', 'input[name="svpn_name"]'
  ];
  for (var i = 0; i < sels.length; i++) {
    var el = null;
    try { el = document.querySelector(sels[i]); } catch (e) { el = null; }
    if (!el || el.disabled || el.readOnly) continue;
    if (el.value) return 'skip';
    el.focus();
    el.value = sid;
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
    el.blur();
    return 'ok';
  }
  return 'none';
})(${jsonEncode(id)});
''';
    try {
      await c.runJavaScript(js);
    } catch (_) {
      /* 页面还没就绪时忽略，下次加载会再试 */
    }
  }

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

  /// 打开页面时提示登录须知（每次进入提示一次）。
  Future<void> _showLoginTipsIfNeeded() async {
    if (_tipsShown || !mounted) return;
    _tipsShown = true;

    final where = _profile.hasCampusNetwork ? '教务系统（校内直连）' : 'WebVPN';
    final tips = <String>[
      if (widget.allowImport)
        '1. 请登录至教务系统主页，然后点击下方「执行导入」。'
      else
        '1. 这里可以直接登录并使用教务系统网页，不会导入课表。',
      '2. 本软件不储存密码，仅自动填写学号，请手动输入密码。',
      if (!_profile.hasCampusNetwork)
        '3. WebVPN 的滑块验证会尝试自动完成，失败时可手动拖动。'
      else
        '3. 如遇验证码请手动输入。',
      if (!_profile.hasCampusNetwork)
        '4. 登录 WebVPN 后，请从功能页进入教务系统再登录。',
    ];

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('登录 $where'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final t in tips) ...[
              Text(t),
              if (t != tips.last) const SizedBox(height: 10),
            ],
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
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
                      _fetching ? _status : '登录到教务系统主页后，点击右侧「执行导入」',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: (!_ready || _fetching) ? null : _startImport,
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
