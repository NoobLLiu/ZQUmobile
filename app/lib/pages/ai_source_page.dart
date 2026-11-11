/// 配置模型来源。
///
/// 通知转写的 AI 走用户自己的 OpenAI 兼容服务：厂商下拉框参考 CC Switch
/// 的预置做法——选中厂商就自动填好 Base URL 和可参考的模型名称，
/// 只需要补一个 API Key。
///
/// 可以点「测试连接」，测的就是保存后会真正发出的请求。
/// 选好厂商（或填好 Key）后还会自动查一次可用模型与账户余额——各家能力不同，
/// 余额只有 DeepSeek / Kimi 有公开接口。
library;

import 'package:flutter/material.dart';

import '../models/ai_source.dart';
import '../services/ai_account_client.dart';
import '../services/ai_source_repository.dart';
import '../services/deepseek_client.dart';

/// 配置模型来源页。返回 `true` 表示配置已保存，调用方应重新读取。
class AiSourcePage extends StatefulWidget {
  const AiSourcePage({super.key, this.autoProbe = true});

  /// 是否在进入页面 / 切厂商时自动查询模型与余额。
  /// 组件测试里传 false，避免真的发网络请求。
  final bool autoProbe;

  @override
  State<AiSourcePage> createState() => _AiSourcePageState();
}

class _AiSourcePageState extends State<AiSourcePage> {
  final _baseUrlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _modelController = TextEditingController();

  String _providerId = 'deepseek';
  bool _obscureKey = true;

  bool _loading = true;
  bool _testing = false;
  bool? _testOk;
  String _testMessage = '';

  bool _modelsLoading = false;
  List<String> _modelIds = const [];
  String? _modelsError;

  bool _balanceLoading = false;
  String? _balanceText;
  String? _balanceError;
  bool _balanceUnsupported = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final config = await AiSourceRepository.load();
    if (!mounted) return;
    setState(() {
      _providerId = config.providerId;
      _baseUrlController.text = config.baseUrl;
      _apiKeyController.text = config.apiKey;
      _modelController.text = config.model;
      _loading = false;
    });
    // 从没配置过时按默认厂商预填，用户只需补 Key
    if (config.baseUrl.trim().isEmpty && config.model.trim().isEmpty) {
      _applyPreset(_providerId);
    } else {
      _scheduleProbe();
    }
  }

  /// 当前表单对应的配置（未保存也能拿来测连接）。
  AiSourceConfig _currentConfig() => AiSourceConfig(
        providerId: _providerId,
        baseUrl: _baseUrlController.text.trim(),
        apiKey: _apiKeyController.text.trim(),
        model: _modelController.text.trim(),
      );

  void _clearTest() {
    _testOk = null;
    _testMessage = '';
  }

  /// 清掉上一轮查询结果，切换厂商时用。
  void _resetProbe() {
    _modelIds = const [];
    _modelsError = null;
    _balanceText = null;
    _balanceError = null;
    _balanceUnsupported = false;
  }

  /// 选中预置厂商 → 自动填 Base URL 与可参考的模型名称，顺带查一次模型和余额。
  void _applyPreset(String id) {
    final preset = findAiProvider(id);
    if (preset == null) {
      // 「自定义」不预填，让用户从零写
      _baseUrlController.clear();
      _modelController.clear();
    } else {
      _baseUrlController.text = preset.baseUrl;
      _modelController.text = preset.model;
    }
    _clearTest();
    _resetProbe();
    _scheduleProbe();
  }

  // ------------------------------------------------------ 模型列表与余额

  /// 要先把地址和 Key 填上才查。
  bool _canProbe(AiSourceConfig config) =>
      config.baseUrl.trim().isNotEmpty && config.apiKey.trim().isNotEmpty;

  /// 等这一帧画完再查，避免在 setState 里直接发请求。
  void _scheduleProbe() {
    if (!widget.autoProbe) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _probeAll();
    });
  }

  Future<void> _probeAll() async {
    await Future.wait([_fetchModels(), _fetchBalance()]);
  }

  AiAccountClient _accountClient(AiSourceConfig config) => AiAccountClient(
        apiKey: config.effectiveApiKey,
        modelsUrl: config.modelsUrl,
        balanceUrl: config.balanceUrl,
        balanceFormat: config.balanceFormat,
      );

  Future<void> _fetchModels() async {
    final config = _currentConfig();
    if (!_canProbe(config)) return;
    setState(() {
      _modelsLoading = true;
      _modelsError = null;
    });
    try {
      final ids = await _accountClient(config).fetchModels();
      if (!mounted) return;
      setState(() {
        _modelsLoading = false;
        _modelIds = ids;
      });
    } on AiException catch (e) {
      if (!mounted) return;
      setState(() {
        _modelsLoading = false;
        _modelIds = const [];
        _modelsError = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _modelsLoading = false;
        _modelIds = const [];
        _modelsError = '获取模型列表失败：$e';
      });
    }
  }

  Future<void> _fetchBalance() async {
    final config = _currentConfig();
    if (!_canProbe(config)) return;
    if (!config.supportsBalance) {
      setState(() {
        _balanceLoading = false;
        _balanceText = null;
        _balanceError = null;
        _balanceUnsupported = true;
      });
      return;
    }
    setState(() {
      _balanceLoading = true;
      _balanceError = null;
      _balanceUnsupported = false;
    });
    try {
      final result = await _accountClient(config).fetchBalance();
      if (!mounted) return;
      setState(() {
        _balanceLoading = false;
        _balanceText = result.text;
      });
    } on AiException catch (e) {
      if (!mounted) return;
      setState(() {
        _balanceLoading = false;
        _balanceText = null;
        _balanceError = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _balanceLoading = false;
        _balanceText = null;
        _balanceError = '查询余额失败：$e';
      });
    }
  }

  Future<void> _testConnection() async {
    if (_testing) return;
    final config = _currentConfig();
    final problem = config.validate();
    if (problem != null) {
      setState(() {
        _testOk = false;
        _testMessage = problem;
      });
      return;
    }

    setState(() {
      _testing = true;
      _testOk = null;
      _testMessage = '';
    });

    try {
      final reply = await DeepSeekClient.fromConfig(config)
          .testConnection(model: config.effectiveModel);
      if (!mounted) return;
      setState(() {
        _testing = false;
        _testOk = true;
        _testMessage =
            '连接成功 · ${config.effectiveModel}\n模型回复：$reply';
      });
      // 连上了就顺手把模型列表和余额也拉一遍
      _scheduleProbe();
    } on AiException catch (e) {
      if (!mounted) return;
      setState(() {
        _testing = false;
        _testOk = false;
        _testMessage = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testing = false;
        _testOk = false;
        _testMessage = '连接测试失败：$e';
      });
    }
  }

  Future<void> _save() async {
    final config = _currentConfig();
    final problem = config.validate();
    if (problem != null) {
      setState(() {
        _testOk = false;
        _testMessage = problem;
      });
      return;
    }
    await AiSourceRepository.save(config);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('模型来源已保存')));
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('配置模型来源')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                _buildCustomCard(),
                const SizedBox(height: 12),
                _buildProbeCard(),
                const SizedBox(height: 16),
                _buildFooterNote(),
              ],
            ),
      // 测试连接与保存常驻底部：自行配置的表单很长，别让用户滚到底才找得到
      bottomNavigationBar: _loading
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_testMessage.isNotEmpty) ...[
                      _buildTestResult(),
                      const SizedBox(height: 8),
                    ],
                    _buildActions(),
                  ],
                ),
              ),
            ),
    );
  }

  // ------------------------------------------------------------ 厂商与连接

  Widget _buildCustomCard() {
    final theme = Theme.of(context);
    final preset = findAiProvider(_providerId);
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle('① 模型厂商'),

          // 厂商下拉：最后一个选项是自定义
          DropdownButtonFormField<String>(
            initialValue: _providerId,
            isExpanded: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
            items: [
              for (final p in kAiProviderPresets)
                DropdownMenuItem<String>(
                  value: p.id,
                  child: Text(p.name, overflow: TextOverflow.ellipsis),
                ),
              const DropdownMenuItem<String>(
                value: kCustomProviderId,
                child: Text('自定义（手动填写）'),
              ),
            ],
            onChanged: (id) {
              if (id == null) return;
              setState(() {
                _providerId = id;
                _applyPreset(id);
              });
            },
          ),
          const SizedBox(height: 10),
          if (preset != null) ...[
            _ProviderInfo(preset: preset),
            const SizedBox(height: 6),
          ],
          Text(
            preset == null
                ? '自定义服务：请手动填写 Base URL 与模型名称。'
                : '已自动填入该厂商的 Base URL 与可参考模型名，都可以再改；'
                    '切换厂商会重新填入。',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline, height: 1.5),
          ),

          const _FieldLabel('Base URL'),
          TextField(
            controller: _baseUrlController,
            enabled: !_testing,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              hintText: 'https://api.deepseek.com',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => setState(_clearTest),
            onSubmitted: (_) => _scheduleProbe(),
          ),
          const SizedBox(height: 4),
          _Hint('会自动补上 /chat/completions；填完整地址也认。'),

          const _FieldLabel('API Key'),
          TextField(
            controller: _apiKeyController,
            enabled: !_testing,
            obscureText: _obscureKey,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              hintText: 'sk-...',
              border: const OutlineInputBorder(),
              isDense: true,
              suffixIcon: IconButton(
                tooltip: _obscureKey ? '显示' : '隐藏',
                icon: Icon(
                  _obscureKey ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  size: 20,
                ),
                onPressed: () => setState(() => _obscureKey = !_obscureKey),
              ),
            ),
            onChanged: (_) => setState(_clearTest),
            onSubmitted: (_) => _scheduleProbe(),
          ),

          const _FieldLabel('模型名称'),
          TextField(
            controller: _modelController,
            enabled: !_testing,
            decoration: const InputDecoration(
              hintText: '如 deepseek-chat / qwen-plus',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => setState(_clearTest),
          ),
          const SizedBox(height: 6),
          _Hint('使用 OpenAI 格式：POST /chat/completions + Bearer 鉴权。'),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ 服务信息

  Widget _buildProbeCard() {
    final theme = Theme.of(context);
    final config = _currentConfig();
    final canProbe = _canProbe(config);

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle('② 服务信息'),
          Row(
            children: [
              Expanded(
                child: Text(
                  '可用模型',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              TextButton.icon(
                onPressed: canProbe && !_modelsLoading
                    ? () => _fetchModels()
                    : null,
                icon: _modelsLoading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.list_alt, size: 18),
                label: const Text('获取模型列表'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          _buildModelsContent(theme, canProbe),
          const Divider(height: 24),
          Row(
            children: [
              Expanded(
                child: Text(
                  '账户余额',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              TextButton.icon(
                onPressed: canProbe && !_balanceLoading
                    ? () => _fetchBalance()
                    : null,
                icon: _balanceLoading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.account_balance_wallet_outlined,
                        size: 18),
                label: const Text('查询余额'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          _buildBalanceContent(theme, canProbe, config),
        ],
      ),
    );
  }

  Widget _buildModelsContent(ThemeData theme, bool canProbe) {
    if (!canProbe) {
      return const _ProbeHint('填好 Base URL 与 API Key 后会自动查询。');
    }
    if (_modelsLoading) return const _ProbeHint('正在获取…');
    if (_modelsError != null) {
      return _ProbeHint(_modelsError!, color: theme.colorScheme.error);
    }
    if (_modelIds.isEmpty) {
      return const _ProbeHint('点「获取模型列表」查询这个 Key 能用的模型。');
    }
    final shown = _modelIds.take(8).join('、');
    final more = _modelIds.length > 8 ? ' 等 ${_modelIds.length} 个' : '';
    return SelectableText(
      '$shown$more',
      style: theme.textTheme.bodySmall?.copyWith(height: 1.6),
    );
  }

  Widget _buildBalanceContent(
    ThemeData theme,
    bool canProbe,
    AiSourceConfig config,
  ) {
    if (!canProbe) {
      return const _ProbeHint('填好 Base URL 与 API Key 后会自动查询。');
    }
    if (_balanceLoading) return const _ProbeHint('正在查询…');
    if (_balanceError != null) {
      return _ProbeHint(_balanceError!, color: theme.colorScheme.error);
    }
    if (_balanceUnsupported) {
      return const _ProbeHint('该厂商没有提供公开的余额接口，请到官网控制台查看。');
    }
    if (_balanceText == null) {
      return const _ProbeHint('点「查询余额」查看这个 Key 的剩余额度。');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _balanceText!,
          style: theme.textTheme.bodyMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        if (config.balanceHint.isNotEmpty) ...[
          const SizedBox(height: 4),
          _ProbeHint(config.balanceHint),
        ],
      ],
    );
  }

  // ------------------------------------------------------------ 操作与结果

  Widget _buildActions() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _testing ? null : _testConnection,
            icon: _testing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.wifi_tethering_outlined, size: 20),
            label: Text(_testing ? '测试中…' : '测试连接'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.icon(
            onPressed: _testing ? null : _save,
            icon: const Icon(Icons.save_outlined, size: 20),
            label: const Text('保存配置'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTestResult() {
    final theme = Theme.of(context);
    final ok = _testOk == true;
    final scheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ok ? scheme.primaryContainer : scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            ok ? Icons.check_circle_outline : Icons.error_outline,
            size: 20,
            color: ok ? scheme.onPrimaryContainer : scheme.onErrorContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _testMessage,
              style: theme.textTheme.bodySmall?.copyWith(
                color: ok ? scheme.onPrimaryContainer : scheme.onErrorContainer,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooterNote() {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline, size: 16, color: theme.colorScheme.outline),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '填写的 API Key 只保存在本机，用于发起转写请求，不会上传到其它地方。'
              '「测试连接」会消耗一次极少量的模型调用额度。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
                height: 1.6,
              ),
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
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
      padding: const EdgeInsets.only(bottom: 12),
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
      padding: const EdgeInsets.only(top: 14, bottom: 8),
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
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: Theme.of(context).colorScheme.outline),
      ),
    );
  }
}

/// 服务信息区的一行说明，支持用错误色强调。
class _ProbeHint extends StatelessWidget {
  const _ProbeHint(this.text, {this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        color: color ?? theme.colorScheme.outline,
        height: 1.6,
      ),
    );
  }
}

/// 预置厂商的说明：官网（可长按复制）+ 特殊提示。
class _ProviderInfo extends StatelessWidget {
  const _ProviderInfo({required this.preset});

  final AiProviderPreset preset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.language, size: 15, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Text('获取 API Key：',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline)),
              Expanded(
                child: SelectableText(
                  preset.keySite,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          if (preset.note.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              preset.note,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline, height: 1.5),
            ),
          ],
        ],
      ),
    );
  }
}
