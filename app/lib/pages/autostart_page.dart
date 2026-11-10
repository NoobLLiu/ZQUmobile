/// 自启动与后台权限指引页。
///
/// 各厂商没有统一 API，只能列出路径让用户手动开。
library;

import 'package:flutter/material.dart';

/// 分组说明 + 机型路径。
class AutostartPage extends StatelessWidget {
  const AutostartPage({super.key});

  static const List<(String, String)> _vendors = [
    ('小米 / Redmi', '设置 → 应用设置 → 应用管理 → 掌上砚园 → 自启动'),
    ('华为 / 荣耀', '设置 → 应用 → 应用启动管理 → 掌上砚园 → 改为手动管理，'
        '并允许自启动、关联启动、后台活动'),
    ('OPPO / 一加', '设置 → 应用 → 应用管理 → 掌上砚园 → 允许自启动与关联启动'),
    ('vivo / iQOO', '设置 → 应用 → 权限管理 → 掌上砚园 → 允许后台高耗电'),
    ('原生 Android', '一般无需设置；若仍被清理，在电池优化里把本应用设为不受限制'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final body = theme.textTheme.bodyMedium?.copyWith(height: 1.6);

    return Scaffold(
      appBar: AppBar(title: const Text('自启动与后台权限')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.secondaryContainer.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '水电提醒依赖应用进程存活。进程被系统清理或从最近任务划掉后，'
              '将无法查询和提醒，需要在本机系统设置里放开后台权限。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSecondaryContainer,
                height: 1.55,
              ),
            ),
          ),
          const SizedBox(height: 16),
          for (final (vendor, path) in _vendors) ...[
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              color: scheme.surfaceContainerLow,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vendor,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      path,
                      style: body?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            '另外建议在最近任务里下拉锁定本应用，避免被一键清理。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.outline,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
