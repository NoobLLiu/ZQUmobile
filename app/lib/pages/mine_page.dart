/// 「我的」页面：账号信息、课表设置、关于。
library;

import 'package:flutter/material.dart';

import '../models/timetable.dart';
import '../services/timetable_repository.dart';

/// 我的页面。
class MinePage extends StatefulWidget {
  const MinePage({super.key});

  @override
  State<MinePage> createState() => MinePageState();
}

/// 我的页状态（对外暴露以便外部在登录返回后刷新）。
class MinePageState extends State<MinePage> {
  Timetable? _tt;
  bool _loggedIn = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tt = await TimetableRepository.load();
    final loggedIn = await TimetableRepository.isLoggedIn();
    if (!mounted) return;
    setState(() {
      _tt = tt;
      _loggedIn = loggedIn;
    });
  }

  /// 供外部在登录页返回后调用。
  void reload() => _load();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          // 用户卡片
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor:
                          theme.colorScheme.primary.withValues(alpha: 0.15),
                      child: Icon(Icons.person_outline,
                          color: theme.colorScheme.primary, size: 28),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _tt?.termName.isNotEmpty == true
                                ? _tt!.termName
                                : '肇庆学院同学',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _tt == null
                                ? '尚未导入课表'
                                : '已导入 ${_tt!.courses.length} 门课程 · ${_tt!.totalWeeks} 周',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: theme.colorScheme.outline),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const _SectionTitle('教务账号'),
          _Tile(
            icon: Icons.login_outlined,
            title: '登录教务系统',
            subtitle: _loggedIn ? '已登录，可重新导入课表' : '未登录',
            onTap: () => Navigator.of(context).pushNamed('/jwgl'),
          ),

          const _SectionTitle('课表数据'),
          _Tile(
            icon: Icons.calendar_month_outlined,
            title: '查看我的课表',
            subtitle: _tt == null ? '暂无课表数据' : '共 ${_tt!.totalWeeks} 周',
            onTap: () => Navigator.of(context).pushNamed('/timetable'),
          ),
          _Tile(
            icon: Icons.delete_outline,
            title: '清空课表缓存',
            subtitle: '删除本地已保存的课表数据',
            onTap: () => _confirmClear(context),
          ),

          const _SectionTitle('关于'),
          const _Tile(
            icon: Icons.info_outline,
            title: '关于掌上砚园',
            subtitle: '版本 1.0.0',
          ),
          _Tile(
            icon: Icons.description_outlined,
            title: '开源许可',
            subtitle: '查看本项目使用的开源项目',
            onTap: () => _showLicenses(context),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空课表缓存'),
        content: const Text('将删除本地保存的课表数据，下次可重新从教务系统导入。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('确定清空')),
        ],
      ),
    );
    if (ok != true) return;
    await TimetableRepository.clear();
    await _load();
    if (!mounted) return;
    messenger.showSnackBar(const SnackBar(content: Text('已清空课表缓存')));
  }

  void _showLicenses(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: '掌上砚园',
      applicationVersion: '1.0.0',
      applicationIcon: const Icon(Icons.school_outlined, size: 40),
      children: const [
        Text(
          '肇庆学院校园助手，提供教务课表导入与查看功能。\n\n'
          '本项目参考并使用了以下开源项目：\n'
          '· ShiGuangSchedule/shiguangschedule —— 课表网格布局与课程卡片视觉（Apache-2.0）\n'
          '· 拾光课程表官方适配脚本 zqu_01.js —— 肇庆学院教务对接逻辑（Apache-2.0）',
        ),
      ],
    );
  }
}

/// 分组标题。
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
        child: Text(
          text,
          style: Theme.of(context)
              .textTheme
              .labelLarge
              ?.copyWith(color: Theme.of(context).colorScheme.primary),
        ),
      );
}

/// 设置项。
class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: onTap == null ? null : const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
