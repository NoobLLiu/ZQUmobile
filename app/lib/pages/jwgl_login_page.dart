/// 教务系统登录页（内嵌 WebView）。
///
/// 与拾光课表同款做法：App 内嵌 WebView 打开教务登录页，用户自行完成登录
/// （含图形验证码、SSO 跳转、WebVPN 滑块，全部人工完成），
/// 登录成功后注入 ZQU 适配脚本取课表数据。
///
/// 按需求，**不实现验证码自动填写**：验证码由用户手动输入。
library;

import 'package:flutter/material.dart';
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

  int _progress = 0;
  bool _fetching = false;
  String _status = '请使用学号与信息门户密码登录（验证码需手动填写）';
  String? _error;

  /// 教务登录入口：校外走 WebVPN，校内可直连。
  static const String webvpnUrl = 'https://webvpn-free.zqu.edu.cn/login';
  static const String jwglUrl = 'https://jwgl.zqu.edu.cn/';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final js = await DefaultAssetBundle.of(context).loadString('assets/js/zqu_adapter.js');
    if (!mounted) return;
    setState(() => _adapterJs = js);

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFFFFFFF))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) {
            if (mounted) setState(() => _progress = p);
          },
          onWebResourceError: (err) {
            // 忽略子资源错误，只提示主文档加载失败
            if (err.isForMainFrame ?? false) {
              setState(() => _error = '页面加载失败：${err.description}');
            }
          },
          onPageFinished: (url) {
            if (mounted) setState(() => _error = null);
          },
        ),
      )
      ..addJavaScriptChannel(
        'zsyBridge',
        onMessageReceived: (message) {
          _handleBridgeMessage(message.message);
        },
      )
      ..loadRequest(Uri.parse(webvpnUrl));

    setState(() => _controller = controller);
  }

  /// 收到适配脚本的回传结果。
  void _handleBridgeMessage(String raw) {
    if (!mounted) return;
    try {
      final result = parseFetchPayload(raw);
      _saveResult(result);
    } on JwglException catch (e) {
      setState(() {
        _error = e.message;
        _fetching = false;
        _status = '抓取失败';
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

  /// 注入取数脚本。
  Future<void> _startFetch() async {
    final controller = _controller;
    final js = _adapterJs;
    if (controller == null || js == null) return;

    setState(() {
      _fetching = true;
      _error = null;
      _status = '正在读取课表 ...';
    });

    try {
      await controller.runJavaScript(js);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fetching = false;
        _error = '脚本注入失败：$e';
        _status = '抓取失败';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return Scaffold(
      appBar: AppBar(
        title: const Text('教务系统登录'),
        actions: [
          IconButton(
            onPressed: _fetching ? null : _startFetch,
            icon: _fetching
                ? const SizedBox(
                    width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.cloud_download_outlined),
            tooltip: '导入课表',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(3),
          child: LinearProgressIndicator(value: _progress / 100),
        ),
      ),
      body: Column(
        children: [
          // 状态提示条
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(_status,
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
                  if (_error != null)
                    TextButton(
                      onPressed: _startFetch,
                      child: const Text('重试'),
                    ),
                ],
              ),
            ),
          ),
          if (_error != null)
            Material(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Icon(Icons.error_outline,
                        size: 18, color: Theme.of(context).colorScheme.onErrorContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.onErrorContainer),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // 底部操作栏
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: controller == null
                              ? null
                              : () => controller.loadRequest(Uri.parse(jwglUrl)),
                          icon: const Icon(Icons.school_outlined),
                          label: const Text('校内直连'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: controller == null
                              ? null
                              : () => controller.loadRequest(Uri.parse(webvpnUrl)),
                          icon: const Icon(Icons.vpn_lock_outlined),
                          label: const Text('校外 WebVPN'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _fetching ? null : _startFetch,
                    icon: const Icon(Icons.download_outlined),
                    label: Text(_fetching ? '正在导入 ...' : '已登录？点击导入课表'),
                    style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(46)),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: controller == null
                ? const Center(child: CircularProgressIndicator())
                : WebViewWidget(controller: controller),
          ),
        ],
      ),
    );
  }
}
