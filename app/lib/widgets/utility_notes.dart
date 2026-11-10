/// 水电相关页面的统一说明文案与提示卡片。
///
/// 「查询水电」与「设置 → 水电余额提醒」必须说同一套话，因此文案只写在
/// 这里：数据来自完美校园，且需要先在完美校园里绑定宿舍、查询过一次，
/// 否则本应用查不到任何余额。
library;

import 'package:flutter/material.dart';

import '../models/utility.dart';

/// 查询的前置条件：完美校园里已经绑定并查询过。
const String kUtilityBindHint =
    '需要先在「完美校园」里绑定宿舍并查询过一次水电费，这里才能查到余额。';

/// 低余额阈值说明（数值取自 models/utility.dart）。
String get kUtilityThresholdLine =>
    '电 ≤ ${_trim(kLowElectricity)} 度、水 ≤ ${_trim(kLowWater)} 吨视为余额不足，'
    '对应数字会标红。';

/// 提醒机制说明。
const List<String> kUtilityReminderLines = [
  '开启后每整点与半点自动查询一次，只在「充足变为不足」时发通知，不会重复打扰。',
  '提醒依赖应用进程存活，进程被系统清理后无法查询，需要允许自启动。',
];

/// 单独的前置条件提示块（错误页、提醒页顶部使用）。
class UtilityBindHintCard extends StatelessWidget {
  const UtilityBindHintCard({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 16,
            color: scheme.onSecondaryContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              kUtilityBindHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSecondaryContainer,
                height: 1.55,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 完整的说明卡片：前置条件 + 阈值 + 提醒规则，可选跳转到提醒设置。
///
/// [onOpenReminder] 为 null 时不显示跳转行（提醒设置页自身用不到）。
class UtilityNotesCard extends StatelessWidget {
  const UtilityNotesCard({super.key, this.onOpenReminder});

  /// 点击「余额提醒设置」时的回调，由页面负责导航。
  final VoidCallback? onOpenReminder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bodyStyle = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
      height: 1.55,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.info_outline,
                size: 15,
                color: scheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                '说明',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: scheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const UtilityBindHintCard(),
          const SizedBox(height: 10),
          Text('· $kUtilityThresholdLine', style: bodyStyle),
          const SizedBox(height: 2),
          for (final line in kUtilityReminderLines) ...[
            Text('· $line', style: bodyStyle),
            const SizedBox(height: 2),
          ],
          if (onOpenReminder != null) ...[
            const SizedBox(height: 4),
            InkWell(
              onTap: onOpenReminder,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(
                      Icons.notifications_active_outlined,
                      size: 15,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '余额提醒设置',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: scheme.primary,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _trim(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
