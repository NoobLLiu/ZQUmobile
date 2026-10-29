/// 首页：功能入口宫格。
library;

import 'package:flutter/material.dart';

import '../services/timetable_repository.dart';

/// 一个可从首页进入的功能。
class HomeFeature {
  const HomeFeature({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.route,
    this.enabled = true,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  /// 目标路由。
  final String route;

  /// 是否已开放（未开放的功能置灰并提示）。
  final bool enabled;
}

/// 首页。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => HomePageState();
}

/// 首页状态（对外暴露以便外部在登录返回后刷新）。
class HomePageState extends State<HomePage> {
  bool _loggedIn = false;
  bool _hasTimetable = false;

  @override
  void initState() {
    super.initState();
    _refreshState();
  }

  Future<void> _refreshState() async {
    final loggedIn = await TimetableRepository.isLoggedIn();
    final tt = await TimetableRepository.load();
    if (!mounted) return;
    setState(() {
      _loggedIn = loggedIn;
      _hasTimetable = tt != null;
    });
  }

  /// 供外部在登录页返回后调用。
  void reload() => _refreshState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final features = <HomeFeature>[
      const HomeFeature(
        title: '我的课表',
        subtitle: '周视图课程表，支持学期切换',
        icon: Icons.calendar_month_outlined,
        route: '/timetable',
      ),
      const HomeFeature(
        title: '教务系统',
        subtitle: '登录肇庆学院教务系统，导入课表数据',
        icon: Icons.school_outlined,
        route: '/jwgl',
      ),
      HomeFeature(
        title: '成绩查询',
        subtitle: '即将上线',
        icon: Icons.assignment_outlined,
        route: '/soon',
        enabled: false,
      ),
      HomeFeature(
        title: '空教室查询',
        subtitle: '即将上线',
        icon: Icons.chair_outlined,
        route: '/soon',
        enabled: false,
      ),
    ];

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // 顶部欢迎区
          SliverAppBar(
            pinned: true,
            expandedHeight: 168,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              title: const Text('掌上砚园',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      theme.colorScheme.primary,
                      theme.colorScheme.primary.withValues(alpha: 0.75),
                    ],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 60, 20, 0),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '肇庆学院校园助手',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _hasTimetable ? '课表已就绪' : '尚未导入课表',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.white.withValues(alpha: 0.75),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // 功能宫格
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('全部功能',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.35,
                    children: [
                      for (final f in features) _FeatureCard(feature: f),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // 登录状态提示
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            sliver: SliverToBoxAdapter(
              child: Card(
                child: ListTile(
                  leading: Icon(
                    _loggedIn ? Icons.verified_outlined : Icons.info_outline,
                    color: _loggedIn
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outline,
                  ),
                  title: Text(_loggedIn ? '教务系统已登录' : '教务系统未登录'),
                  subtitle: Text(
                    _loggedIn
                        ? '进入「教务系统」可重新导入课表'
                        : '进入「教务系统」完成登录后可导入课表',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).pushNamed('/jwgl');
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 功能卡片。
class _FeatureCard extends StatelessWidget {
  const _FeatureCard({required this.feature});

  final HomeFeature feature;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = feature.enabled;

    return Card(
      color: enabled
          ? theme.colorScheme.surfaceContainerLow
          : theme.colorScheme.surfaceContainerLowest,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: enabled
            ? () => Navigator.of(context).pushNamed(feature.route)
            : () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('${feature.title} 功能开发中')),
                );
              },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: enabled
                      ? theme.colorScheme.primary.withValues(alpha: 0.12)
                      : theme.colorScheme.outline.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  feature.icon,
                  size: 22,
                  color: enabled
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outline,
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    feature.title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: enabled
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.outline,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    feature.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
