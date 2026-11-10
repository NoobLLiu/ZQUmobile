/// 通知转写的模型来源配置。
///
/// 两种来源：
/// 1. 免费模型（作者提供）—— 沿用内置 Key 的 DeepSeek 官方接口；
/// 2. 自行配置 —— 用户填自己的 OpenAI 兼容服务（Base URL / API Key / 模型名）。
///
/// 预置厂商清单参考 CC Switch 的「Provider Preset」：选中后自动填好地址，
/// 只需要补一个 Key。所有厂商都走 OpenAI 格式的 `/chat/completions`。
library;

import 'dart:convert';

import '../core/ai_credentials.dart';

/// 一个可选的模型（免费来源下用）。
class AiModelOption {
  const AiModelOption(this.id, this.label, this.hint);

  final String id;
  final String label;
  final String hint;
}

/// 作者提供的免费模型：够用就好，不把整个目录摊给用户。
const List<AiModelOption> kAiModels = [
  AiModelOption('deepseek-flash', 'DeepSeek V4.1 Flash', '默认，速度快，日常通知够用'),
  AiModelOption('deepseek-v4-pro', 'DeepSeek V4 Pro', '更稳，长通知 / 复杂补充要求时用'),
];

const String kDefaultModelId = 'deepseek-flash';

/// 模型来源。
enum AiSourceMode {
  free,
  custom;

  bool get isFree => this == AiSourceMode.free;
}

/// 余额接口的返回格式。各家字段名不一样，只能按厂商分别解析。
enum AiBalanceFormat {
  /// 官方没有公开的余额接口。
  none,

  /// DeepSeek：`balance_infos[]`，含 currency / total_balance / granted_balance。
  deepseek,

  /// 月之暗面：`data.available_balance` / voucher_balance / cash_balance（元）。
  moonshot,

  /// 硅基流动：`data.totalBalance` / balance / chargeBalance（元）。
  siliconflow,

  /// OpenRouter：`data.total_credits` 与 `data.total_usage`（美元）。
  openrouter,
}

/// 「自定义」在厂商下拉框里排最后。
const String kCustomProviderId = 'custom';

/// 一个预置的 OpenAI 兼容厂商。
class AiProviderPreset {
  const AiProviderPreset({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.model,
    required this.keySite,
    this.note = '',
    this.balanceUrl,
    this.balanceFormat = AiBalanceFormat.none,
    this.balanceHint = '',
  });

  final String id;
  final String name;

  /// OpenAI 兼容的 Base URL（不含 `/chat/completions`）。
  final String baseUrl;

  /// 可参考的模型名称，选中后自动填入，用户可以改。
  final String model;

  /// 申请 API Key 的官网。
  final String keySite;

  /// 补充提示（例如豆包要填接入点 ID）。
  final String note;

  /// 余额查询的完整地址；null 表示官方没有提供公开接口。
  final String? balanceUrl;

  /// 余额返回体的解析方式。
  final AiBalanceFormat balanceFormat;

  /// 余额相关的补充说明（例如 OpenRouter 要 management key）。
  final String balanceHint;

  /// 是否支持查询余额。
  bool get supportsBalance => balanceUrl != null && balanceFormat != AiBalanceFormat.none;
}

/// 常用厂商。最后一个选项是「自定义」，由界面单独追加。
const List<AiProviderPreset> kAiProviderPresets = [
  AiProviderPreset(
    id: 'deepseek',
    name: 'DeepSeek 官方',
    baseUrl: 'https://api.deepseek.com',
    model: 'deepseek-chat',
    keySite: 'platform.deepseek.com',
    note: '也支持 https://api.deepseek.com/v1',
    balanceUrl: 'https://api.deepseek.com/user/balance',
    balanceFormat: AiBalanceFormat.deepseek,
  ),
  AiProviderPreset(
    id: 'dashscope',
    name: '阿里云百炼（通义千问）',
    baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    model: 'qwen-plus',
    keySite: 'bailian.console.aliyun.com',
    note: '必须带 /compatible-mode/v1',
  ),
  AiProviderPreset(
    id: 'zhipu',
    name: '智谱 GLM',
    baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
    model: 'glm-4.6',
    keySite: 'open.bigmodel.cn',
  ),
  AiProviderPreset(
    id: 'moonshot',
    name: '月之暗面 Kimi',
    baseUrl: 'https://api.moonshot.cn/v1',
    model: 'moonshot-v1-8k',
    keySite: 'platform.moonshot.cn',
    balanceUrl: 'https://api.moonshot.cn/v1/users/me/balance',
    balanceFormat: AiBalanceFormat.moonshot,
  ),
  AiProviderPreset(
    id: 'siliconflow',
    name: '硅基流动 SiliconFlow',
    baseUrl: 'https://api.siliconflow.cn/v1',
    model: 'Qwen/Qwen2.5-7B-Instruct',
    keySite: 'cloud.siliconflow.cn',
    note: '聚合多家模型，有免费额度，模型名要写完整路径',
    balanceUrl: 'https://api.siliconflow.cn/v1/user/info',
    balanceFormat: AiBalanceFormat.siliconflow,
  ),
  AiProviderPreset(
    id: 'volcengine',
    name: '火山方舟（豆包）',
    baseUrl: 'https://ark.cn-beijing.volces.com/api/v3',
    model: 'ep-2024xxxxxx-xxxxx',
    keySite: 'console.volcengine.com/ark',
    note: '模型名填推理接入点 ID（ep- 开头），不是模型名',
  ),
  AiProviderPreset(
    id: 'minimax',
    name: 'MiniMax',
    baseUrl: 'https://api.minimaxi.com/v1',
    model: 'MiniMax-M2',
    keySite: 'platform.minimaxi.com',
  ),
  AiProviderPreset(
    id: 'hunyuan',
    name: '腾讯混元',
    baseUrl: 'https://api.hunyuan.cloud.tencent.com/v1',
    model: 'hunyuan-turbo',
    keySite: 'cloud.tencent.com/product/hunyuan',
  ),
  AiProviderPreset(
    id: 'openrouter',
    name: 'OpenRouter',
    baseUrl: 'https://openrouter.ai/api/v1',
    model: 'openai/gpt-4o-mini',
    keySite: 'openrouter.ai/keys',
    note: '聚合平台，模型名要带厂商前缀',
    balanceUrl: 'https://openrouter.ai/api/v1/credits',
    balanceFormat: AiBalanceFormat.openrouter,
    balanceHint: '额度接口需要 management key，普通 Key 可能返回 403',
  ),
  AiProviderPreset(
    id: 'openai',
    name: 'OpenAI',
    baseUrl: 'https://api.openai.com/v1',
    model: 'gpt-4o-mini',
    keySite: 'platform.openai.com/api-keys',
  ),
];

/// 按 id 找预置厂商；自定义或未知 id 返回 null。
AiProviderPreset? findAiProvider(String id) {
  for (final p in kAiProviderPresets) {
    if (p.id == id) return p;
  }
  return null;
}

/// 把用户填的 Base URL 规整成 `/chat/completions` 地址。
///
/// 用户可能填 `https://api.deepseek.com`、`.../v1`、带尾斜杠，
/// 也可能直接把完整的 `.../chat/completions` 贴进来，都要能直接用。
String normalizeChatUrl(String raw) {
  var s = raw.trim();
  while (s.endsWith('/')) {
    s = s.substring(0, s.length - 1);
  }
  if (s.isEmpty) return '';
  if (s.endsWith('/chat/completions')) return s;
  return '$s/chat/completions';
}

/// 是否要发送 DeepSeek 专属的 `thinking` 字段。
///
/// 只有内置免费来源支持；第三方 OpenAI 兼容服务收到这个字段可能直接 400。
bool shouldSendThinking(bool supportsThinking, bool deepThinking) =>
    supportsThinking && !deepThinking;

/// 一份来源配置。
class AiSourceConfig {
  const AiSourceConfig({
    this.mode = AiSourceMode.free,
    this.providerId = 'deepseek',
    this.baseUrl = '',
    this.apiKey = '',
    this.model = '',
    this.freeModelIndex = 0,
  });

  final AiSourceMode mode;

  /// 当前选中的厂商 id；`custom` 表示列表最后的「自定义」。
  final String providerId;

  final String baseUrl;
  final String apiKey;
  final String model;

  /// 免费来源下选中的模型下标。
  final int freeModelIndex;

  bool get isFree => mode == AiSourceMode.free;

  bool get isCustomPreset => providerId == kCustomProviderId;

  /// 展示用的厂商名。
  String get providerName =>
      findAiProvider(providerId)?.name ?? '自定义服务';

  /// 实际请求的地址。
  String get chatUrl =>
      isFree ? kDeepSeekEndpoint : normalizeChatUrl(baseUrl);

  /// OpenAI 标准的模型列表地址：把 `/chat/completions` 换成 `/models`。
  String get modelsUrl {
    const suffix = '/chat/completions';
    final chat = normalizeChatUrl(chatUrl);
    final root = chat.endsWith(suffix)
        ? chat.substring(0, chat.length - suffix.length)
        : chat;
    return root.isEmpty ? '' : '$root/models';
  }

  /// 余额查询地址；null 表示这个厂商没有公开接口。
  String? get balanceUrl {
    if (isFree) return 'https://api.deepseek.com/user/balance';
    return findAiProvider(providerId)?.balanceUrl;
  }

  AiBalanceFormat get balanceFormat {
    if (isFree) return AiBalanceFormat.deepseek;
    return findAiProvider(providerId)?.balanceFormat ?? AiBalanceFormat.none;
  }

  /// 余额说明（如 OpenRouter 要 management key）。
  String get balanceHint {
    if (isFree) return '';
    return findAiProvider(providerId)?.balanceHint ?? '';
  }

  bool get supportsBalance =>
      balanceUrl != null && balanceFormat != AiBalanceFormat.none;

  /// 实际使用的 Key（免费来源取内置 Key）。
  String get effectiveApiKey =>
      isFree ? deepSeekApiKey() : apiKey.trim();

  /// 实际使用的模型名。
  String get effectiveModel {
    if (isFree) {
      final i = freeModelIndex.clamp(0, kAiModels.length - 1);
      return kAiModels[i].id;
    }
    return model.trim();
  }

  /// 是否支持 `thinking` 字段（仅内置来源）。
  bool get supportsThinking => isFree;

  /// 自行配置时的表单校验，返回可直接展示的中文错误；通过返回 null。
  String? validateCustom() {
    final url = baseUrl.trim();
    if (url.isEmpty) return '请填写 Base URL';
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      return 'Base URL 要以 http:// 或 https:// 开头';
    }
    if (url.contains(' ')) return 'Base URL 里不能有空格';
    if (apiKey.trim().isEmpty) return '请填写 API Key';
    if (model.trim().isEmpty) return '请填写模型名称';
    return null;
  }

  AiSourceConfig copyWith({
    AiSourceMode? mode,
    String? providerId,
    String? baseUrl,
    String? apiKey,
    String? model,
    int? freeModelIndex,
  }) {
    return AiSourceConfig(
      mode: mode ?? this.mode,
      providerId: providerId ?? this.providerId,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
      freeModelIndex: freeModelIndex ?? this.freeModelIndex,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'mode': mode.name,
        'providerId': providerId,
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'model': model,
        'freeModelIndex': freeModelIndex,
      };

  factory AiSourceConfig.fromJson(Map<String, dynamic> json) {
    final modeName = json['mode'];
    return AiSourceConfig(
      mode: modeName == AiSourceMode.custom.name
          ? AiSourceMode.custom
          : AiSourceMode.free,
      providerId: (json['providerId'] as String?) ?? 'deepseek',
      baseUrl: (json['baseUrl'] as String?) ?? '',
      apiKey: (json['apiKey'] as String?) ?? '',
      model: (json['model'] as String?) ?? '',
      freeModelIndex: (json['freeModelIndex'] as int?) ?? 0,
    );
  }

  static AiSourceConfig decode(String? raw) {
    if (raw == null || raw.isEmpty) return const AiSourceConfig();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return AiSourceConfig.fromJson(decoded);
      }
    } catch (_) {
      /* 损坏则回退默认值 */
    }
    return const AiSourceConfig();
  }

  String encode() => jsonEncode(toJson());
}
