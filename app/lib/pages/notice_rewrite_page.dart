/// 通知转写页。
///
/// 班委把辅导员/老师发到年级班委群的通知粘进来，页内按「规则 + 选项」拼出提示词，
/// 交给 DeepSeek 改写成面向全班同学的通知：称谓换掉、"请转发"类话术改成"现发布"、
/// 排版补上行首缩进，实质信息（时间、地点、链接、命名规则）一个字不动。
///
/// 这套规则与「班委通知转写」skill 完全一致（见 services/notice_rewrite_prompt.dart），
/// 只是把原来跑在微信小程序里的一次性工具，搬进了天天会打开的 App。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/deepseek_client.dart';
import '../services/notice_rewrite_prompt.dart';

/// 通知转写页。
class NoticeRewritePage extends StatefulWidget {
  const NoticeRewritePage({super.key});

  @override
  State<NoticeRewritePage> createState() => _NoticeRewritePageState();
}

/// 一条补充通知的编辑态。
class _ExtraItem {
  _ExtraItem() : controller = TextEditingController();

  final TextEditingController controller;
  int modeIndex = 0;
}

class _NoticeRewritePageState extends State<NoticeRewritePage> {
  final _originalController = TextEditingController();
  final _sourceController = TextEditingController();
  final _deadlineController = TextEditingController();
  final _scrollController = ScrollController();

  final List<_ExtraItem> _extras = [];

  int _sourceModeIndex = 2; // 默认「自定义来源」
  int _greetingIndex = 0; // 默认「自动」
  int _targetIndex = 2; // 默认「各位同学」
  int _deadlineModeIndex = 0; // 默认「不修改」
  int _modelIndex = 0;

  bool _deepThinking = false;
  bool _generating = false;
  String _result = '';
  String? _error;

  DeepSeekClient? _client;
  int _lastFlush = 0;

  @override
  void initState() {
    super.initState();
    _originalController.addListener(_onInputChanged);
    _sourceController.addListener(_onInputChanged);
    _deadlineController.addListener(_onInputChanged);
  }

  @override
  void dispose() {
    _client?.cancel();
    _originalController.dispose();
    _sourceController.dispose();
    _deadlineController.dispose();
    for (final item in _extras) {
      item.controller.dispose();
    }
    _scrollController.dispose();
    super.dispose();
  }

  void _onInputChanged() {
    if (mounted) setState(() {});
  }

  /// 当前生效的问候语：选了「自动」就按时段表取。
  String get _greeting {
    final chosen = kGreetingOptions[_greetingIndex];
    return chosen.value.isEmpty ? autoGreeting(DateTime.now()) : chosen.value;
  }

  String get _salutation => kGreetingTargets[_targetIndex].salutation;

  String get _greetingPreview => buildGreetingLine(_salutation, _greeting);

  // ---------------------------------------------------------------- 操作

  void _addExtra() {
    setState(() => _extras.add(_ExtraItem()..controller.addListener(_onInputChanged)));
  }

  void _removeExtra(int index) {
    setState(() {
      final item = _extras.removeAt(index);
      item.controller.dispose();
    });
  }

  Future<void> _copyResult() async {
    if (_result.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _result));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已复制，可直接粘贴到班级群')));
  }

  /// 提交前的校验，全在前端做完，避免白花一次额度。
  String? _validate() {
    if (_originalController.text.trim().isEmpty) return '请先粘贴原通知';
    if (kSourceModes[_sourceModeIndex].key == 'custom' &&
        _sourceController.text.trim().isEmpty) {
      return '请填写消息来源（如：辅导员），标题行需要它';
    }
    if (_deadlineModeIndex == 1 && _deadlineController.text.trim().isEmpty) {
      return '请填写新的截止时间，或改选“不修改”';
    }
    if (_extras.any((it) => it.controller.text.trim().isEmpty)) {
      return '补充通知内容为空，请填写内容或点“删除”移除该条';
    }
    return null;
  }

  Future<void> _startRewrite() async {
    if (_generating) return;

    final problem = _validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    final userMessage = buildUserMessage(
      sourceModeIndex: _sourceModeIndex,
      source: _sourceController.text,
      target: _salutation,
      deadlineModeIndex: _deadlineModeIndex,
      newDeadline: _deadlineController.text,
      extras: [
        for (final it in _extras)
          NoticeExtra(text: it.controller.text, modeIndex: it.modeIndex),
      ],
      greeting: _greeting,
      original: _originalController.text.trim(),
    );

    final client = DeepSeekClient();
    _client = client;
    var acc = '';
    _lastFlush = 0;

    setState(() {
      _generating = true;
      _result = '';
      _error = null;
    });

    try {
      await for (final delta in client.streamChat(
        model: kAiModels[_modelIndex].id,
        systemPrompt: kNoticeSystemPrompt,
        userMessage: userMessage,
        deepThinking: _deepThinking,
      )) {
        acc += delta;
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - _lastFlush > 120) {
          _lastFlush = now;
          if (mounted) setState(() => _result = acc);
        }
      }
      if (!mounted) return;
      setState(() {
        _result = acc;
        _generating = false;
        if (acc.trim().isEmpty) _error = 'AI 没有返回内容，请重新转写一次';
      });
      if (acc.trim().isNotEmpty) _scrollToResult();
    } on AiException catch (e) {
      if (!mounted) return;
      setState(() {
        _result = acc;
        _generating = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _result = acc;
        _generating = false;
        _error = '转写失败：$e';
      });
    } finally {
      _client = null;
    }
  }

  void _stop() {
    _client?.cancel();
    if (!mounted) return;
    setState(() => _generating = false);
  }

  void _scrollToResult() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOut,
      );
    });
  }

  // ---------------------------------------------------------------- 构建

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('通知转写'),
        actions: [
          IconButton(
            tooltip: '清空',
            onPressed: _generating
                ? null
                : () => setState(() {
                      _originalController.clear();
                      _sourceController.clear();
                      _deadlineController.clear();
                      for (final it in _extras) {
                        it.controller.dispose();
                      }
                      _extras.clear();
                      _result = '';
                      _error = null;
                    }),
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _buildHero(theme),
          const SizedBox(height: 12),
          _buildOriginalCard(theme),
          const SizedBox(height: 12),
          _buildOptionsCard(theme),
          const SizedBox(height: 16),
          _buildActions(theme),
          if (_error != null) ...[
            const SizedBox(height: 12),
            _buildError(theme, _error!),
          ],
          if (_result.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildResultCard(theme),
          ],
          const SizedBox(height: 16),
          _buildDemoNotice(theme),
        ],
      ),
    );
  }

  Widget _buildHero(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primary.withValues(alpha: 0.16),
            theme.colorScheme.primary.withValues(alpha: 0.04),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.campaign_outlined,
                  color: theme.colorScheme.primary, size: 22),
              const SizedBox(width: 8),
              Text('通知转写助手',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '粘贴班委群里的通知，AI 按班级群的口吻改写：换称谓、补问候、'
            '把“请转发”改成“现发布”，时间地点链接一字不动。',
            style: theme.textTheme.bodySmall?.copyWith(
              height: 1.6,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOriginalCard(ThemeData theme) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle('① 原通知'),
          TextField(
            controller: _originalController,
            maxLines: 8,
            minLines: 6,
            maxLength: 5000,
            textInputAction: TextInputAction.newline,
            decoration: const InputDecoration(
              hintText: '把老师/辅导员发到班委群的通知原文粘贴到这里…',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text('补充通知',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const Spacer(),
              TextButton.icon(
                onPressed: _generating ? null : _addExtra,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('添加'),
              ),
            ],
          ),
          Text(
            '可选。没有就留空；有补充时点“添加”，每条单独填写并选择处理方式。',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
          if (_extras.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('暂无补充通知',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline)),
            ),
          for (var i = 0; i < _extras.length; i++) _buildExtraItem(theme, i),
        ],
      ),
    );
  }

  Widget _buildExtraItem(ThemeData theme, int index) {
    final item = _extras[index];
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('补充通知 ${index + 1}',
                  style: theme.textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const Spacer(),
              TextButton(
                onPressed: _generating ? null : () => _removeExtra(index),
                child: const Text('删除'),
              ),
            ],
          ),
          TextField(
            controller: item.controller,
            maxLines: 4,
            minLines: 2,
            maxLength: 1000,
            decoration: const InputDecoration(
              hintText: '如：材料提交截止时间改为10月26日21点前，其他内容不变',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          _ChipRow<int>(
            values: [for (var i = 0; i < kExtraModes.length; i++) i],
            selected: item.modeIndex,
            labelOf: (i) => kExtraModes[i].label,
            onSelected: _generating
                ? null
                : (i) => setState(() => item.modeIndex = i),
          ),
          const SizedBox(height: 4),
          Text(kExtraModes[item.modeIndex].hint,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline)),
        ],
      ),
    );
  }

  Widget _buildOptionsCard(ThemeData theme) {
    final sourceMode = kSourceModes[_sourceModeIndex];
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle('② 转写选项'),

          _FieldLabel('消息来源（标题行写法）'),
          _ChipRow<int>(
            values: [for (var i = 0; i < kSourceModes.length; i++) i],
            selected: _sourceModeIndex,
            labelOf: (i) => kSourceModes[i].label,
            onSelected: _generating
                ? null
                : (i) => setState(() => _sourceModeIndex = i),
          ),
          _Hint(sourceMode.hint),
          if (sourceMode.key == 'custom') ...[
            const SizedBox(height: 8),
            TextField(
              controller: _sourceController,
              enabled: !_generating,
              decoration: const InputDecoration(
                isDense: true,
                hintText: '如：辅导员 / 教务处 / 政法学院',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            _ChipRow<String>(
              values: kSourceChips,
              selected: _sourceController.text.trim(),
              labelOf: (v) => v,
              onSelected: _generating
                  ? null
                  : (v) => setState(() => _sourceController.text = v),
            ),
          ],

          _FieldLabel('问好时间'),
          _ChipRow<int>(
            values: [for (var i = 0; i < kGreetingOptions.length; i++) i],
            selected: _greetingIndex,
            labelOf: (i) => kGreetingOptions[i].label,
            onSelected: _generating
                ? null
                : (i) => setState(() => _greetingIndex = i),
          ),

          _FieldLabel('问好对象'),
          _ChipRow<int>(
            values: [for (var i = 0; i < kGreetingTargets.length; i++) i],
            selected: _targetIndex,
            labelOf: (i) => kGreetingTargets[i].label,
            onSelected: _generating
                ? null
                : (i) => setState(() => _targetIndex = i),
          ),
          _Hint('整句问候：$_greetingPreview'),

          _FieldLabel('截止时间'),
          _ChipRow<int>(
            values: [for (var i = 0; i < kDeadlineModes.length; i++) i],
            selected: _deadlineModeIndex,
            labelOf: (i) => kDeadlineModes[i].label,
            onSelected: _generating
                ? null
                : (i) => setState(() => _deadlineModeIndex = i),
          ),
          _Hint(kDeadlineModes[_deadlineModeIndex].hint),
          if (_deadlineModeIndex == 1) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _deadlineController,
              enabled: !_generating,
              decoration: const InputDecoration(
                isDense: true,
                hintText: '新的截止时间，如 10月26日21点',
                border: OutlineInputBorder(),
              ),
            ),
          ],

          _FieldLabel('AI 模型'),
          _ChipRow<int>(
            values: [for (var i = 0; i < kAiModels.length; i++) i],
            selected: _modelIndex,
            labelOf: (i) => kAiModels[i].label,
            onSelected: _generating ? null : (i) => setState(() => _modelIndex = i),
          ),
          _Hint(kAiModels[_modelIndex].hint),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('深度思考',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(
                        '先推理再动笔，更慢更贵；通知结构简单时关掉更快。',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.outline),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _deepThinking,
                  onChanged: _generating
                      ? null
                      : (v) => setState(() => _deepThinking = v),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(ThemeData theme) {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: _generating ? null : _startRewrite,
            icon: _generating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome, size: 20),
            label: Text(_generating ? '正在转写…' : '开始转写'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        if (_generating) ...[
          const SizedBox(width: 12),
          OutlinedButton(
            onPressed: _stop,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
            ),
            child: const Text('停止'),
          ),
        ],
      ],
    );
  }

  Widget _buildError(ThemeData theme, String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline,
              size: 20, color: theme.colorScheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onErrorContainer),
            ),
          ),
          TextButton(
            onPressed: _generating ? null : _startRewrite,
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard(ThemeData theme) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _SectionTitle('③ 转写结果'),
              const Spacer(),
              TextButton.icon(
                onPressed: _copyResult,
                icon: const Icon(Icons.copy_all_outlined, size: 18),
                label: const Text('复制'),
              ),
            ],
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: SelectableText(
              _result,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.75),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _generating
                ? 'AI 正在输出…'
                : '行首空格是排版的一部分，整段复制后粘贴到班级群即可。',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ),
    );
  }

  Widget _buildDemoNotice(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline,
              size: 16, color: theme.colorScheme.outline),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '作品提交阶段，为了方便演示，这里直接使用了参赛组自己的 API Key，'
              '正常情况下会让用户填自己的 API Key。',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline, height: 1.6),
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ 小组件

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .titleSmall
            ?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        text,
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.outline),
      ),
    );
  }
}

/// 一排可选中的小标签。
class _ChipRow<T> extends StatelessWidget {
  const _ChipRow({
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
  });

  final List<T> values;
  final T selected;
  final String Function(T value) labelOf;
  final void Function(T value)? onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final v in values)
          ChoiceChip(
            label: Text(labelOf(v)),
            selected: v == selected,
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            labelStyle: Theme.of(context).textTheme.bodySmall,
            onSelected: onSelected == null ? null : (_) => onSelected!(v),
          ),
      ],
    );
  }
}
