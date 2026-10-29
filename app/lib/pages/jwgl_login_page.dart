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
/// 按需求，**不实现验证码自动填写**。
library;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/timetable.dart';
import '../services/jwgl_service.dart';
import '../services/timetable_repository.dart';

/// 教务登录与课表抓取页。
class JwglLoginPage extends StatefulWidget {
  const JwglLoginPage({super.key});

  @override
  State<JwglLoginPage> createState() => _JwglLoginPageState();
}

class _JwglLoginPageState extends State<JwglLoginPage> {
  WebViewController? _controller;

  /// 注入脚本 = 桥接 shim + 上游适配脚本。
  String? _injectJs;

  /// 默认打开教务系统首页（校内可直连；校外可在菜单里改成 WebVPN 地址）。
  static const String defaultUrl = 'https://jwgl.zqu.edu.cn/';
  static const String _prefsKeyUrl = 'zsy_jwgl_entry_url';

  double _progress = 0;
  bool _loadingPage = true;
  bool _fetching = false;
  String _pageTitle = '教务系统';
  String _status = '请在下方网页中登录教务系统（验证码需自行输入）';
  String? _error;

  /// 注入脚本后等待回传的令牌，用于兜底「点了没反应」。
  int _fetchToken = 0;

  // ---- 官方脚本分段落库的累积区 ----
  List<Course>? _accCourses;
  List<TimeSlot>? _accSlots;
  int _accTotalWeeks = 0;
  String _accStartDate = '';

  /// 「执行导入」是否可用（拿到脚本后才可用）。
  bool get _ready => _controller != null && _injectJs != null;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final bundle = DefaultAssetBundle.of(context);
    final shim = await bundle.loadString('assets/js/shiguang_bridge_shim.js');
    final upstream = await bundle.loadString('assets/js/zqu_upstream.js');
    final sp = await SharedPreferences.getInstance();
    final entryUrl = sp.getString(_prefsKeyUrl) ?? defaultUrl;
    if (!mounted) return;

    setState(() => _injectJs = '$shim\n$upstream');

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

    // 官方脚本分段回传
    final j = msg.json;
    switch (msg.type) {
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

  /// 官方脚本跑完（done）：把累积到的三段数据组装成课表并落库。
  Future<void> _finalize() async {
    final courses = _accCourses;
    if (courses == null || courses.isEmpty) {
      _fail('导入流程结束，但没有收到课程数据。\n请确认已登录教务系统，并停留在教务系统内的页面。');
      return;
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
      startDate = '${monday.year.toString().padLeft(4, '0')}-'
          '${monday.month.toString().padLeft(2, '0')}-'
          '${monday.day.toString().padLeft(2, '0')}';
    }

    final slots = _accSlots ??
        kPresetTimeSlots.map((e) => TimeSlot.fromJson(e)).toList();

    final tt = Timetable(
      term: '',
      termName: _pageTitle,
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
    _fail('没有收到教务系统的响应。\n请确认：① 已登录教务系统；'
        '② 当前停留在教务系统内的页面（不是 WebVPN 首页）。');
  }

  Future<void> _reload() => _controller?.reload() ?? Future.value();

  /// 菜单里的「输入网址」：用于在校内直连与 WebVPN 之间切换。
  Future<void> _editUrl() async {
    final controller = _controller;
    if (controller == null) return;

    final current = await controller.currentUrl();
    final input = TextEditingController(
      text: (current == null || current == 'about:blank') ? defaultUrl : current,
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

    final sp = await SharedPreferences.getInstance();
    await sp.setString(_prefsKeyUrl, full);
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
                    Icon(Icons.error_outline,
                        size: 18, color: theme.colorScheme.onErrorContainer),
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
                      icon: Icon(Icons.close,
                          size: 18, color: theme.colorScheme.onErrorContainer),
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
      bottomNavigationBar: BottomAppBar(
        height: 72,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _fetching ? _status : '登录完成后，点击右侧导入课表',
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
