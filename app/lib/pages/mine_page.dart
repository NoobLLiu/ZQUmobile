/// 「我的」页面：账号信息、课表设置、关于。
library;

import 'package:flutter/material.dart';

import '../core/build_info.dart';
import '../models/profile.dart';
import '../models/timetable.dart';
import '../services/profile_repository.dart';
import '../services/timetable_repository.dart';
import '../services/utility_reminder.dart';
import '../widgets/profile_dialog.dart';

/// 我的页面。
class MinePage extends StatefulWidget {
  const MinePage({super.key});

  @override
  State<MinePage> createState() => MinePageState();
}

/// 我的页状态（对外暴露以便外部在登录返回后刷新）。
class MinePageState extends State<MinePage> {
  Timetable? _tt;

  /// 通用个人信息（学号 / 学期 / 是否已购校园网）。
  Profile _profile = const Profile();

  /// 水电余额提醒开关。
  bool _reminderOn = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tt = await TimetableRepository.load();
    final profile = await ProfileRepository.load();
    final reminderOn = await UtilityReminder.isEnabled();
    if (!mounted) return;
    setState(() {
      _tt = tt;
      _profile = profile;
      _reminderOn = reminderOn;
    });
  }

  /// 修改个人信息。
  Future<void> _editProfile(BuildContext context) async {
    final updated = await showProfileDialog(context, initial: _profile);
    if (updated == null) return;
    await ProfileRepository.save(updated);
    if (!mounted) return;
    setState(() => _profile = updated);
  }

  /// 供外部在登录页返回后调用。
  void reload() => _load();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const _SectionTitle('课表数据'),
          _Tile(
            icon: Icons.delete_outline,
            title: '清空课表缓存',
            subtitle: _tt == null ? '暂无课表数据' : '已导入 ${_tt!.courses.length} 门课',
            onTap: () => _confirmClear(context),
          ),

          const _SectionTitle('个人资料'),
          _Tile(
            icon: Icons.badge_outlined,
            title: '学号',
            subtitle: _profile.studentId.isEmpty ? '未填写' : _profile.studentId,
          ),
          _Tile(
            icon: Icons.event_available_outlined,
            title: '学期',
            subtitle: _profile.term,
          ),
          _Tile(
            icon: Icons.wifi_outlined,
            title: '校园网',
            subtitle: _profile.hasCampusNetwork ? '已购（校内直连）' : '未购',
          ),
          _Tile(
            icon: Icons.key_outlined,
            title: '登录密码',
            subtitle: _profile.isComplete
                ? '教务 / WebVPN 密码已保存，登录时自动代填'
                : '未保存完整，打开登录页无法自动登录',
          ),
          _Tile(
            icon: Icons.edit_outlined,
            title: '修改个人信息',
            subtitle: '学号、两套密码、学期、是否已购校园网',
            onTap: () => _editProfile(context),
          ),

          const _SectionTitle('水电提醒'),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_active_outlined),
            title: const Text('水电余额提醒'),
            subtitle: Text(_reminderOn
                ? '已开启 · 每整点/半点自动查询，余额不足时通知'
                : '关闭 · 开启后每整点/半点自动查询，余额不足时通知'),
            value: _reminderOn,
            onChanged: (v) => _toggleReminder(context, v),
          ),
          _Tile(
            icon: Icons.settings_backup_restore_outlined,
            title: '自启动与后台设置指引',
            subtitle: '提醒依赖应用后台存活，各机型需手动开启',
            onTap: () => _showAutostartGuide(context),
          ),

          const _SectionTitle('关于'),
          _Tile(
            icon: Icons.info_outline,
            title: '关于掌上砚园',
            subtitle: '版本 ${BuildInfo.displayVersion}',
            onTap: () => _showAbout(context),
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

  /// 开/关水电余额提醒。
  Future<void> _toggleReminder(BuildContext context, bool value) async {
    final messenger = ScaffoldMessenger.of(context);
    if (value) {
      final profile = await ProfileRepository.load();
      if (!mounted) return;
      if (profile.studentId.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('请先在「修改个人信息」里填写学号')),
        );
        return;
      }
      final granted = await UtilityReminder.requestNotificationPermission();
      await UtilityReminder.enable();
      if (!mounted) return;
      setState(() => _reminderOn = true);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            granted
                ? '已开启提醒，正在查询一次当前余额'
                : '已开启提醒，但未授予通知权限，通知将无法弹出',
          ),
        ),
      );
    } else {
      await UtilityReminder.disable();
      if (!mounted) return;
      setState(() => _reminderOn = false);
    }
  }

  /// 自启动与后台设置指引（各厂商没有统一 API，只能列路径让用户手动开）。
  void _showAutostartGuide(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.settings_suggest_outlined, size: 36),
        title: const Text('自启动与后台设置'),
        content: const SingleChildScrollView(
          child: Text(
            '水电提醒依赖应用进程存活，进程被清理后将无法查询和提醒。'
            '请在系统设置中手动开启：\n\n'
            '· 小米：设置 → 应用设置 → 应用管理 → 掌上砚园 → 自启动\n'
            '· 华为 / 荣耀：设置 → 应用 → 应用启动管理 → 掌上砚园 → '
            '改为手动管理并允许自启动、关联启动、后台活动\n'
            '· OPPO / 一加：设置 → 应用 → 应用管理 → 掌上砚园 → '
            '允许自启动与关联启动\n'
            '· vivo：设置 → 应用 → 权限管理 → 掌上砚园 → 允许后台高耗电\n'
            '· 原生 / 其他：一般无需设置\n\n'
            '另外建议在最近任务里下拉锁定本应用，避免被一键清理。',
            style: TextStyle(fontSize: 13, height: 1.6),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('知道了'),
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

  /// 关于：显示版本、提交号与构建时间，便于确认当前装的是哪一版。
  void _showAbout(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.school_outlined, size: 40),
        title: const Text('掌上砚园'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('肇庆学院校园助手，提供教务课表导入与查看功能。'),
            const SizedBox(height: 16),
            _kv(ctx, '版本', BuildInfo.version),
            _kv(ctx, '构建号', BuildInfo.buildNumber),
            _kv(ctx, '提交', BuildInfo.gitSha),
            if (BuildInfo.buildTime.isNotEmpty)
              _kv(ctx, '构建时间', BuildInfo.buildTime),
            _kv(ctx, '来源', BuildInfo.isCi ? 'CI 云端构建' : '本地构建'),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  Widget _kv(BuildContext ctx, String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 64,
              child: Text(k,
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(ctx).colorScheme.outline,
                  )),
            ),
            Expanded(
              child: SelectableText(v, style: const TextStyle(fontSize: 13)),
            ),
          ],
        ),
      );

  void _showLicenses(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: '掌上砚园',
      applicationVersion: BuildInfo.displayVersion,
      applicationIcon: const Icon(Icons.school_outlined, size: 40),
      applicationLegalese: '肇庆学院校园助手',
      children: const [
        Text(
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
