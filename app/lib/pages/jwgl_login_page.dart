/// 教务系统登录页（内嵌 WebView）。
///
/// 页面结构参照拾光课表的 WebViewScreen（Apache-2.0）：
/// - 顶部只有标题 + 更多菜单（刷新 / 输入网址），不放任何常驻按钮，避免遮挡网页；
/// - 底部一条操作栏：左侧引导文字，右侧「执行导入」按钮；
/// - 加载进度以细进度条浮在 WebView 顶部。
///
/// 登录流程：用户在网页里自己完成登录（图形验证码、SSO、WebVPN 滑块全部人工），
/// 登录后点「执行导入」，App 注入 assets/js/zqu_adapter.js 取整学期课表。
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
  String? _adapterJs;

  /// 默认打开教务系统首页（校内可直连；校外可在菜单里改成 WebVPN 地址）。
  static const String defaultUrl = 'https://jwgl.zqu.edu.cn/';
  static const String _prefsKeyUrl = 'zsy_jwgl_entry_url';

  double _progress = 0;
  bool _loadingPage = true;
  bool _fetching = false;
  String _pageTitle = '教务系统';
  String _status = '请在下方网页中登录教务系统（验证码需自行输入）';
  String? _error;

  /// 注入脚本后等待回传的计时器，用于兜底“点了没反应”。
  int _fetchToken = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final js = await DefaultAssetBundle.of(context)
        .loadString('assets/js/zqu_adapter.js');
    final sp = await SharedPreferences.getInstance();
    final entryUrl = sp.getString(_prefsKeyUrl) ?? defaultUrl;
    if (!mounted) return;
    setState(() => _adapterJs = js);

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
            // 页面标题同步到 AppBar，便于用户确认自己在哪一层
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
      // 通道名必须与 assets/js/zqu_adapter.js 里的 window.zsyBridge 一致
      ..addJavaScriptChannel(
        'zsyBridge',
        onMessageReceived: (message) => _onBridgeMessage(message.message),
      )
      ..loadRequest(Uri.parse(entryUrl));

    if (!mounted) return;
    setState(() => _controller = controller);
  }

  // ------------------------------------------------------------------ 回传处理

  void _onBridgeMessage(String raw) {
    if (!mounted) return;
    try {
      final msg = parseBridgeMessage(raw);
      if (msg.isProgress) {
        setState(() {
          _status = msg.message ?? _status;
          _error = null;
        });
        return;
      }
      if (msg.isSuccess) {
        _saveResult(msg.result!);
      } else {
        setState(() {
          _fetching = false;
          _error = msg.error ?? '导入失败';
          _status = '导入失败';
        });
      }
    } on JwglException catch (e) {
      setState(() {
        _fetching = false;
        _error = e.message;
        _status = '导入失败';
      });
    }
  }

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

  /// 点「执行导入」：注入适配脚本。
  Future<void> _startImport() async {
    final controller = _controller;
    final js = _adapterJs;
    if (controller == null || js == null || _fetching) return;

    final token = ++_fetchToken;
    setState(() {
      _fetching = true;
      _error = null;
      _status = '正在导入，请稍候 ...';
    });

    try {
      await controller.runJavaScript(js);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fetching = false;
        _error = '脚本注入失败：$e';
        _status = '导入失败';
      });
      return;
    }

    // 兜底：15 秒内没有任何回传，说明脚本没跑起来（例如页面还没登录）
    await Future.delayed(const Duration(seconds: 15));
    if (!mounted || token != _fetchToken || !_fetching) return;
    setState(() {
      _fetching = false;
      _error = '没有收到教务系统的响应。\n请确认：① 已登录教务系统；'
          '② 当前停留在教务系统内的页面（不是 WebVPN 首页）。';
      _status = '导入超时';
    });
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
          // 失败提示（成功时完全隐藏，不占空间）
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
                // 进度条浮在网页顶部，不挤压内容
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
      // 底部操作栏：左侧引导 + 右侧导入（照拾光的 BottomAppBar 布局）
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
              onPressed: _fetching ? null : _startImport,
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
