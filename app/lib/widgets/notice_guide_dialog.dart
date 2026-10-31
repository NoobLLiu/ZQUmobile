/// 通知转写的「使用示例」弹窗。
///
/// 首次进入页面自动弹一次，之后从标题栏的 `?` 再打开。
/// 图是把「班委群收到的」与「复制到班级群的结果」并排放的示意图，
/// 文字说明只讲三件事：粘原文 → 选几项 → 复制结果。
library;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 是否已经看过示例（看过就不再自动弹）。
const String kNoticeGuideSeenKey = 'zsy_notice_guide_seen';

/// 示例原文：点「填入示例」时填进输入框，省得用户自己编。
const String kNoticeSampleOriginal = '各位带班下午好，现有一则关于“挑战杯”赛事的通知\n'
    '①电子版材料提交截止时间延长至10月24日21点前。\n'
    '②负责人需在10月17日18点前填写报名表单。\n'
    '请各位带班及时转发到新生群，收到请回复，谢谢[玫瑰][玫瑰]';

/// 示例对应的选项，让「填入示例」一键还原成示例里的样子。
const int kNoticeSampleSourceMode = 2; // 自定义来源
const String kNoticeSampleSource = '辅导员';
const int kNoticeSampleGreeting = 3; // 下午好[太阳]
const int kNoticeSampleTarget = 0; // 法学5班的同学们

/// 弹出使用示例。
///
/// [onFillSample] 不为空时，底部会多一个「填入示例」按钮。
Future<void> showNoticeGuideDialog(
  BuildContext context, {
  VoidCallback? onFillSample,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _NoticeGuideDialog(onFillSample: onFillSample),
  );
}

/// 读一次「是否看过示例」，读不到就当没看过。
Future<bool> hasSeenNoticeGuide() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(kNoticeGuideSeenKey) ?? false;
  } catch (_) {
    return false;
  }
}

/// 标记为已看过；失败不影响功能。
Future<void> markNoticeGuideSeen() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kNoticeGuideSeenKey, true);
  } catch (_) {
    // 存不了就算了，大不了下次再弹一遍
  }
}

class _NoticeGuideDialog extends StatelessWidget {
  const _NoticeGuideDialog({this.onFillSample});

  final VoidCallback? onFillSample;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 480,
          maxHeight: media.size.height * 0.86,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题栏
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 4),
              child: Row(
                children: [
                  Icon(Icons.help_outline,
                      size: 20, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text('使用示例',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: Image.asset(
                          'assets/images/notice_example.png',
                          fit: BoxFit.contain,
                          semanticLabel: '通知转写前后对照示例图',
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const _Step(
                      index: '1',
                      text: '把班委群里的通知原文粘进「① 原通知」；有补充通知就点「添加」。',
                    ),
                    const _Step(
                      index: '2',
                      text: '选标题行来源、问好时间、问好对象；要改截止时间就选「修改」并填新时间。',
                    ),
                    const _Step(
                      index: '3',
                      text: '点「开始转写」，结果逐字出现；点「复制」整段粘到班级群。',
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: theme.colorScheme.primary.withValues(alpha: 0.08),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.tips_and_updates_outlined,
                              size: 18, color: theme.colorScheme.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '时间、地点、表单要求逐字保留，AI 只改称谓、问候和'
                              '“请转发”这类话术。行首两个空格是排版的一部分，别弄丢。',
                              style: theme.textTheme.bodySmall?.copyWith(
                                height: 1.6,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // 底部按钮
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (onFillSample != null)
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        onFillSample!();
                      },
                      child: const Text('填入示例'),
                    ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('知道了'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 一条编号步骤。
class _Step extends StatelessWidget {
  const _Step({required this.index, required this.text});

  final String index;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            margin: const EdgeInsets.only(top: 2),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Text(
              index,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(height: 1.6),
            ),
          ),
        ],
      ),
    );
  }
}
