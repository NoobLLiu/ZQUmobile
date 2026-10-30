/// 个人信息填写弹窗。
///
/// 首次启动或资料不完整时弹出；也可在「我的 → 个人资料」里再次打开修改。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/profile.dart';

/// 弹出个人信息编辑框。
///
/// 返回填写好的 [Profile]；用户取消时返回 null。
/// [allowCancel] 为 false 时（首次引导）不允许取消。
Future<Profile?> showProfileDialog(
  BuildContext context, {
  required Profile initial,
  bool allowCancel = true,
}) {
  return showDialog<Profile>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ProfileDialog(initial: initial, allowCancel: allowCancel),
  );
}

class _ProfileDialog extends StatefulWidget {
  const _ProfileDialog({required this.initial, required this.allowCancel});

  final Profile initial;
  final bool allowCancel;

  @override
  State<_ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<_ProfileDialog> {
  late final TextEditingController _idCtrl;
  late String _term;
  late bool _hasCampus;

  String? _error;

  @override
  void initState() {
    super.initState();
    _idCtrl = TextEditingController(text: widget.initial.studentId);
    _term = kTermOptions.contains(widget.initial.term)
        ? widget.initial.term
        : kDefaultTerm;
    _hasCampus = widget.initial.hasCampusNetwork;
    _idCtrl.addListener(() => setState(() => _error = null));
  }

  @override
  void dispose() {
    _idCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final id = _idCtrl.text.trim();
    if (!isValidStudentId(id)) {
      setState(() => _error = '学号需为 12 位数字');
      return;
    }
    Navigator.of(context).pop(Profile(
      studentId: id,
      term: _term,
      hasCampusNetwork: _hasCampus,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('个人信息'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '仅保存在本机，用于登录时自动填写学号，不会上传。',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _idCtrl,
              keyboardType: TextInputType.number,
              maxLength: 12,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: '学号',
                hintText: '12 位数字',
                counterText: '${_idCtrl.text.length}/12',
                errorText: _error,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            Text('学期', style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            RadioGroup<String>(
              groupValue: _term,
              onChanged: (v) => setState(() => _term = v ?? _term),
              child: Column(
                children: [
                  for (final t in kTermOptions)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: ShapeDecoration(
                        color: _term == t
                            ? theme.colorScheme.primary.withValues(alpha: 0.08)
                            : null,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(
                            color: _term == t
                                ? theme.colorScheme.primary
                                : theme.colorScheme.outlineVariant,
                            width: _term == t ? 1.5 : 1,
                          ),
                        ),
                      ),
                      child: Material(
                        // ListTile 的背景/水波纹画在最近的 Material 上，
                        // 需要自己的 Material，避免被外层带背景色的
                        // DecoratedBox 遮挡（否则触发调试断言）。
                        type: MaterialType.transparency,
                        child: RadioListTile<String>(
                          value: t,
                          dense: true,
                          title: Text(t),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            Text('校园网', style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment<bool>(value: true, label: Text('已购校园网')),
                ButtonSegment<bool>(value: false, label: Text('未购校园网')),
              ],
              selected: {_hasCampus},
              onSelectionChanged: (s) => setState(() => _hasCampus = s.first),
            ),
          ],
        ),
      ),
      actions: [
        if (widget.allowCancel)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
        FilledButton(onPressed: _submit, child: const Text('保存')),
      ],
    );
  }
}
