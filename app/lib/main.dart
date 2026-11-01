/// 掌上砚园 —— 肇庆学院校园助手。
///
/// 主框架：底部导航「看板」「功能页」「我的」，
/// 看板为默认首页，汇聚今日课程与生活数据。
library;

import 'package:flutter/material.dart';

import 'pages/attachment_schedule_page.dart';
import 'pages/dashboard_page.dart';
import 'pages/express_station_page.dart';
import 'pages/home_page.dart';
import 'pages/jwgl_login_page.dart';
import 'pages/mine_page.dart';
import 'pages/notice_rewrite_page.dart';
import 'pages/timetable_page.dart';
import 'pages/utility_page.dart';
import 'services/profile_repository.dart';
import 'widgets/profile_dialog.dart';

void main() {
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

/// 底部导航外壳：看板 / 功能页 / 我的。
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  final _dashKey = GlobalKey<DashboardPageState>();

  final _mineKey = GlobalKey<MinePageState>();

  @override
  void initState() {
    super.initState();
    // 首帧后检查个人信息，首次使用或资料不完整时引导填写
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureProfile());
  }

  Future<void> _ensureProfile() async {
    final profile = await ProfileRepository.load();
    if (!mounted || profile.isComplete) return;

    final filled = await showProfileDialog(
      context,
      initial: profile,
      allowCancel: false,
    );
    if (filled == null) return;
    await ProfileRepository.save(filled);
    if (!mounted) return;
    _mineKey.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          DashboardPage(key: _dashKey),
          const HomePage(),
          MinePage(key: _mineKey),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) {
          setState(() => _index = i);
          // 切到「看板」时刷新（导入课表、水电数据可能已变）
          if (i == 0) _dashKey.currentState?.reload();
          // 切到「我的」时刷新（登录返回后课表、资料可能已变）
          if (i == 2) _mineKey.currentState?.reload();
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: '看板',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view),
            label: '功能页',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: '我的',
          ),
        ],
      ),
    );
  }
}
