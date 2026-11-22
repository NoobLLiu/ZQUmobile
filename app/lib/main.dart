/// 掌上砚园 —— 肇庆学院校园助手。
///
/// 主框架：底部导航「看板」「功能」「设置」，
/// 看板为默认首页，汇聚今日课程与生活数据。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import 'core/build_info.dart';
import 'pages/attachment_schedule_page.dart';
import 'pages/dashboard_page.dart';
import 'pages/empty_classroom_page.dart';
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
import 'widgets/app_bar_title.dart';
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
    // MiuixSystemTheme 跟随系统明暗；MiuixThemeController 进一步启用 Monet
    // 动态取色（Android 读壁纸，其他平台回退固定种子），Material 主题随之联动。
    return MiuixSystemTheme(
      child: MiuixThemeController(
        colorSchemeMode: MiuixColorSchemeMode.monetSystem,
        child: Builder(
          builder: (context) {
            final miuixTheme = MiuixTheme.of(context);
            return MaterialApp(
              title: '掌上砚园',
              debugShowCheckedModeBanner: false,
              theme: _buildTheme(
                miuixTheme.brightness,
                miuixTheme.colors.primary,
              ),
              home: const RootShell(),
              routes: {
                '/timetable': (ctx) => const TimetablePage(),
                '/jwgl': (ctx) => const JwglLoginPage(),
                '/utility': (ctx) => const UtilityPage(),
                '/notice': (ctx) => const NoticeRewritePage(),
                '/express': (ctx) => const ExpressStationPage(),
                '/attachment': (ctx) => const AttachmentSchedulePage(),
                '/empty-rooms': (ctx) => const EmptyClassroomPage(),
              },
            );
          },
        ),
      ),
    );
  }

  /// 种子色来自 Monet 当前主题，深浅模式由系统亮度决定。
  static ThemeData _buildTheme(Brightness brightness, Color seed) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
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
    );
  }
}

/// 底部导航外壳：看板 / 功能 / 设置。
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> with WidgetsBindingObserver {
  /// 只给悬浮玻璃底栏使用；每个 RootShell 实例独占，销毁时释放快照。
  final _backdrop = MiuixLayerBackdrop();

  static const _titles = ['看板', '功能', '设置'];

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
    _backdrop.dispose();
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
    // 输入法弹起时临时收掉底部留白，避免玻璃胶囊浮在键盘上方。
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final keyboardOpen = bottomInset > 0;

    return Scaffold(
      // 内容延伸到胶囊下方，玻璃才能采样到页面背景。
      extendBody: true,
      appBar: AppBar(title: AppBarBrandTitle(_titles[_index])),
      body: MiuixLayerBackdropCapture(
        backdrop: _backdrop,
        child: ColoredBox(
          color: MiuixTheme.of(context).colors.surface,
          child: IndexedStack(
            index: _index,
            children: [
              DashboardPage(key: _dashKey),
              const HomePage(),
              const SettingsPage(),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            left: 12,
            top: 12,
            right: 12,
            bottom: keyboardOpen ? 0 : 12,
          ),
          // 不要套 Center/Expanded：Scaffold 给底栏松约束，撑高后胶囊会离开底部。
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: MiuixGlassNavigationBar(
              backdrop: _backdrop,
              selectedIndex: _index,
              onSelect: (i) {
                setState(() => _index = i);
                // 切到「看板」时刷新（导入课表、水电数据可能已变）
                if (i == 0) _dashKey.currentState?.reload();
              },
              items: const [
                MiuixGlassNavigationItem(
                  icon: Icon(Icons.today_outlined),
                  label: '看板',
                ),
                MiuixGlassNavigationItem(
                  icon: Icon(Icons.widgets_outlined),
                  label: '功能',
                ),
                MiuixGlassNavigationItem(
                  icon: Icon(Icons.settings_outlined),
                  label: '设置',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
