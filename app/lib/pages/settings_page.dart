/// 「设置」页：账号、课表、提醒、AI 服务、关于五个分组。
///
/// 每一行都进入独立页面（不再用弹窗），页面内的文案尽量不重复描述状态。
library;

import 'package:flutter/material.dart';

import 'about_page.dart';
import 'ai_source_page.dart';
import 'clear_timetable_page.dart';
import 'profile_page.dart';
import 'term_page.dart';
import 'utility_alert_page.dart';
import '../widgets/app_bar_title.dart';

/// 设置页。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const AppBarBrandTitle('设置')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _Group(
            title: '账号',
            items: [
              _Item(
                icon: Icons.person_outline,
                title: '编辑个人信息',
                page: (_) => const ProfilePage(),
              ),
            ],
          ),
          _Group(
            title: '课表',
            items: [
              _Item(
                icon: Icons.event_available_outlined,
                title: '学期与开学日期',
                page: (_) => const TermPage(),
              ),
              _Item(
                icon: Icons.delete_outline,
                title: '清空课表缓存',
                danger: true,
                page: (_) => const ClearTimetablePage(),
              ),
            ],
          ),
          _Group(
            title: '提醒',
            items: [
              _Item(
                icon: Icons.notifications_active_outlined,
                title: '水电余额提醒',
                page: (_) => const UtilityAlertPage(),
              ),
            ],
          ),
          _Group(
            title: 'AI 服务',
            items: [
              _Item(
                icon: Icons.auto_awesome_outlined,
                title: '模型来源',
                // 与通知转写页右上角进入的是同一个页面
                page: (_) => const AiSourcePage(),
              ),
            ],
          ),
          _Group(
            title: '关于',
            items: [
              _Item(
                icon: Icons.info_outline,
                title: '关于掌上砚园',
                // 版本信息、检测更新、开源许可都收在关于页里
                page: (_) => const AboutPage(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 一个分组：小标题 + 卡片内的若干行。
class _Group extends StatelessWidget {
  const _Group({required this.title, required this.items});

  final String title;
  final List<_Item> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
          child: Text(
            title,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.outline,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Card(
            color: scheme.surfaceContainerLow,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 0.5,
                      thickness: 0.5,
                      indent: 52,
                      color: scheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  _Row(item: items[i]),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 一行设置项。
class _Row extends StatelessWidget {
  const _Row({required this.item});

  final _Item item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = item.danger ? scheme.error : scheme.onSurface;
    final iconColor = item.danger ? scheme.error : scheme.onSurfaceVariant;

    return InkWell(
      onTap: () {
        Navigator.of(context)
            .push(MaterialPageRoute<void>(builder: item.page));
      },
      child: SizedBox(
        height: 52,
        child: Row(
          children: [
            const SizedBox(width: 16),
            Icon(item.icon, size: 20, color: iconColor),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyLarge?.copyWith(color: color),
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: scheme.outline),
            const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }
}

/// 一行设置项的数据。
class _Item {
  const _Item({
    required this.icon,
    required this.title,
    required this.page,
    this.danger = false,
  });

  final IconData icon;
  final String title;

  /// 目标页面。
  final WidgetBuilder page;

  /// 危险操作标红。
  final bool danger;
}
