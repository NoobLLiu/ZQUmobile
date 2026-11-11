/// 掌上砚园 —— 肇庆学院校园助手。
///
/// 主框架：底部导航「看板」「功能页」「设置」，
/// 看板为默认首页，汇聚今日课程与生活数据。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'core/build_info.dart';
import 'pages/attachment_schedule_page.dart';
import 'pages/dashboard_page.dart';
import 'pages/express_station_page.dart';
import 'pages/home_page.dart';
import 'pages/jwgl_login_page.dart';
import 'pages/notice_rewrite_page.dart';
import 'pages/profile_page.dart';
import 'pages/settings_page.dart';
import 'pages/timetable_page.dart';
import 'pages/utility_page.dart';
import 'services/profile_repository.dart';
import 'services/utility_reminder.dart';
import 'widgets/update_flow.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 若用户开启了水电余额提醒，恢复整点/半点的定时查询。
  // 桌面端/异常环境没有通知插件实现也不影响启动，故静默吞错。
  unawaited(() async {
    try {
      await UtilityReminder.startIfEnabled();
    } catch (_) {}
  }());
  runApp(const ZhangShangZhaoYuanApp());
}

/// App 根。
class ZhangShangZhaoYuanApp extends StatelessWidget {
  const ZhangShangZhaoYuanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '掌上砚园',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      home: const RootShell(),
      routes: {
        '/timetable': (ctx) => const TimetablePage(),
        '/jwgl': (ctx) => const JwglLoginPage(),
        '/utility': (ctx) => const UtilityPage(),
        '/notice': (ctx) => const NoticeRewritePage(),
        '/express': (ctx) => const ExpressStationPage(),
        '/attachment': (ctx) => const AttachmentSchedulePage(),
      },
    );
  }

  /// 主题色沿用拾光课表的默认蓝（0xFF73CAF8）。
  static ThemeData _buildTheme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF73CAF8),
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      fontFamily: 'Microsoft YaHei',
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: scheme.surface,
        surfaceTintColor: scheme.surfaceTint,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: scheme.primaryContainer,
        labelTextStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}

/// 底部导航外壳：看板 / 功能页 / 设置。
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> with WidgetsBindingObserver {
  int _index = 0;

  final _dashKey = GlobalKey<DashboardPageState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 首帧后检查个人信息，首次使用或资料不完整时引导填写
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureProfile();
      // 无感自动检测更新：等界面稳定后再查，只在新版本时弹窗打扰。
      // 本地构建（无 CI 注入版本号）跳过，避免每次误报有新版本。
      if (BuildInfo.isCi) {
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) checkForUpdate(context, silent: true);
        });
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 回到前台：补上后台冻结期间错过的水电检查，并重新对齐定时器。
    if (state == AppLifecycleState.resumed) {
      unawaited(() async {
        try {
          await UtilityReminder.onAppResumed();
        } catch (_) {}
      }());
    }
  }

  /// 首次启动或资料不完整时，进入整页的资料完善流程（不允许返回）。
  Future<void> _ensureProfile() async {
    final profile = await ProfileRepository.load();
    if (!mounted || profile.isComplete) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ProfilePage(initial: profile, allowCancel: false),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          DashboardPage(key: _dashKey),
          const HomePage(),
          const SettingsPage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) {
          setState(() => _index = i);
          // 切到「看板」时刷新（导入课表、水电数据可能已变）
          if (i == 0) _dashKey.currentState?.reload();
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            selectedIcon: Icon(Icons.today),
            label: '看板',
          ),
          NavigationDestination(
            icon: Icon(Icons.widgets_outlined),
            selectedIcon: Icon(Icons.widgets),
            label: '功能页',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '设置',
          ),
        ],
      ),
    );
  }
}
