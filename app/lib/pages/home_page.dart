/// 功能页：按分类展示功能入口。
library;

import 'package:flutter/material.dart';

/// 一个可从功能页进入的功能。
class HomeFeature {
  const HomeFeature({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.route,
    this.tag,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  /// 目标路由。
  final String route;

  /// 标题右侧的小标签（如「AI」）。
  final String? tag;
}

/// 功能页的一个功能分类。
class HomeSection {
  const HomeSection({required this.title, required this.features});

  final String title;
  final List<HomeFeature> features;
}

/// 功能页。
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  /// 功能分类。文案改动直接改这里。
  static const List<HomeSection> sections = [
    HomeSection(
      title: '学习功能',
      features: [
        HomeFeature(
          title: '我的课表',
          subtitle: '快捷查看本学期课表',
          icon: Icons.calendar_month_outlined,
          route: '/timetable',
        ),
        HomeFeature(
          title: '教务系统',
          subtitle: '快速访问并自动登录教务系统',
          icon: Icons.school_outlined,
          route: '/jwgl',
        ),
      ],
    ),
    HomeSection(
      title: '班委工作',
      features: [
        HomeFeature(
          title: '通知转写',
          tag: 'AI',
          subtitle: '一键转写学院下发的通知，快捷发布班群',
          icon: Icons.edit_note_outlined,
          route: '/notice',
        ),
      ],
    ),
    HomeSection(
      title: '校园生活',
      features: [
        HomeFeature(
          title: '水电余额',
          subtitle: '快速查询宿舍水电余量，可设置充值提醒',
          icon: Icons.water_drop_outlined,
          route: '/utility',
        ),
        HomeFeature(
          title: '快递站状态',
          subtitle: '看看现在快递站关门没，决定是否拿快递',
          icon: Icons.local_shipping_outlined,
          route: '/express',
        ),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '掌上砚园',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ),
      body: CustomScrollView(
        slivers: [
          for (final section in sections) ...[
            SliverToBoxAdapter(child: _SectionTitle(section.title)),
            SliverToBoxAdapter(child: _SectionCard(features: section.features)),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}

/// 分类标题。
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      child: Text(
        text,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

/// 一个分类下的功能卡片（行之间用细线分隔）。
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.features});

  final List<HomeFeature> features;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        color: theme.colorScheme.surfaceContainerLow,
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (var i = 0; i < features.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  thickness: 1,
                  indent: 68,
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
                ),
              _FeatureRow(feature: features[i]),
            ],
          ],
        ),
      ),
    );
  }
}

/// 单个功能行。
class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.feature});

  final HomeFeature feature;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tag = feature.tag;

    return InkWell(
      onTap: () => Navigator.of(context).pushNamed(feature.route),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(feature.icon, size: 22, color: scheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        feature.title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                      ),
                      if (tag != null) ...[
                        const SizedBox(width: 6),
                        _TagChip(text: tag),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    feature.subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 20, color: scheme.outline),
          ],
        ),
      ),
    );
  }
}

/// 标题后的高亮小标签。
class _TagChip extends StatelessWidget {
  const _TagChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          height: 1.4,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
          color: scheme.onPrimary,
        ),
      ),
    );
  }
}
