/// 关于掌上砚园：版本与构建信息、检测更新、开源许可。
library;

import 'package:flutter/material.dart';

import '../core/build_info.dart';
import '../widgets/update_flow.dart';

/// 关于页。
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  /// 开源许可用 Flutter 自带的整页 LicensePage。
  static void _openLicenses(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LicensePage(
          applicationName: '掌上砚园',
          applicationVersion: BuildInfo.displayVersion,
          applicationIcon: const Icon(Icons.school_outlined, size: 40),
          applicationLegalese: '肇庆学院校园助手',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('关于掌上砚园')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
        children: [
          Center(
            child: Column(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(
                    Icons.school_outlined,
                    size: 34,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '掌上砚园',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '肇庆学院校园助手',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.outline,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Card(
            color: scheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                children: [
                  _kv(context, '版本', BuildInfo.version),
                  _kv(context, '构建号', BuildInfo.buildNumber),
                  _kv(context, '提交', BuildInfo.gitSha),
                  if (BuildInfo.buildTime.isNotEmpty)
                    _kv(context, '构建时间', BuildInfo.buildTime),
                  _kv(
                    context,
                    '来源',
                    BuildInfo.isCi ? 'CI 云端构建' : '本地构建',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            color: scheme.surfaceContainerLow,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _action(
                  context,
                  icon: Icons.system_update_outlined,
                  title: '检测更新',
                  onTap: (ctx) => checkForUpdate(ctx),
                ),
                Divider(
                  height: 0.5,
                  thickness: 0.5,
                  indent: 52,
                  color: scheme.outlineVariant.withValues(alpha: 0.5),
                ),
                _action(
                  context,
                  icon: Icons.description_outlined,
                  title: '开源许可',
                  onTap: _openLicenses,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '提供教务课表导入与查看、通知转写、宿舍水电查询与余额提醒等功能。'
            '账号与密码仅保存在本机，不会上传到任何服务器。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.outline,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  /// 一行「标签 + 值」，值可长按复制。
  Widget _kv(BuildContext context, String k, String v) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 68,
            child: Text(
              k,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              v,
              style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  /// 一行可点击的操作，样式与设置页的行一致。
  Widget _action(
    BuildContext context, {
    required IconData icon,
    required String title,
    required void Function(BuildContext) onTap,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => onTap(context),
      child: SizedBox(
        height: 52,
        child: Row(
          children: [
            const SizedBox(width: 16),
            Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 16),
            Expanded(
              child: Text(title, style: theme.textTheme.bodyLarge),
            ),
            Icon(Icons.chevron_right, size: 20, color: theme.colorScheme.outline),
            const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }
}
