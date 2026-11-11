/// 通知转写的模型来源配置。
///
/// 用户填自己的 OpenAI 兼容服务（Base URL / API Key / 模型名），
/// 预置厂商清单选中后自动填好地址与参考模型名，只需要补一个 Key。
/// 所有厂商都走 OpenAI 格式的 `/chat/completions`。
library;

import 'dart:convert';

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

  /// 补充提示（例如两套 Key 不能混用）。
  final String note;

  /// 余额查询的完整地址；null 表示官方没有提供公开接口。
  final String? balanceUrl;

  /// 余额返回体的解析方式。
  final AiBalanceFormat balanceFormat;

  /// 余额相关的补充说明。
  final String balanceHint;

  /// 是否支持查询余额。
  bool get supportsBalance => balanceUrl != null && balanceFormat != AiBalanceFormat.none;
}

/// 预置厂商（2026-11 按各家官网最新信息核对）。最后一个选项是
/// 「自定义」，由界面单独追加。
const List<AiProviderPreset> kAiProviderPresets = [
  AiProviderPreset(
    id: 'deepseek',
    name: 'DeepSeek 官方',
    baseUrl: 'https://api.deepseek.com',
    model: 'deepseek-flash',
    keySite: 'platform.deepseek.com',
    note: '也支持 https://api.deepseek.com/v1；'
        '长文 / 复杂任务可改用 deepseek-v4-pro',
    balanceUrl: 'https://api.deepseek.com/user/balance',
    balanceFormat: AiBalanceFormat.deepseek,
  ),
  AiProviderPreset(
    id: 'zhipu',
    name: '智谱 GLM',
    baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
    model: 'glm-5.3',
    keySite: 'open.bigmodel.cn',
    note: '追求速度可改用轻量版 glm-5.3-flash',
  ),
  AiProviderPreset(
    id: 'moonshot',
    name: '月之暗面 Kimi',
    baseUrl: 'https://api.moonshot.cn/v1',
    model: 'kimi-k3.1-pro',
    keySite: 'platform.kimi.com',
    note: '高速版 kimi-k3.1-pro-highspeed；上一代 kimi-k3（K2 系列已下线）',
    balanceUrl: 'https://api.moonshot.cn/v1/users/me/balance',
    balanceFormat: AiBalanceFormat.moonshot,
  ),
  AiProviderPreset(
    id: 'mimo',
    name: '小米 MiMo（按量计费）',
    baseUrl: 'https://api.xiaomimimo.com/v1',
    model: 'mimo-v2.6-flash',
    keySite: 'platform.xiaomimimo.com',
    note: 'Key 为 sk- 开头；旗舰 mimo-v2.6-pro，另有 mimo-v2.6-pro-ultraspeed',
  ),
  AiProviderPreset(
    id: 'mimo-tokenplan',
    name: '小米 MiMo TokenPlan',
    baseUrl: 'https://token-plan-cn.xiaomimimo.com/v1',
    model: 'mimo-v2.6-flash',
    keySite: 'platform.xiaomimimo.com（TokenPlan 管理页）',
    note: 'Key 为 tp- 开头，与按量计费的 Key 不通用；'
        '国内集群地址，另有新加坡 token-plan-sgp / 欧洲 token-plan-ams',
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
/// 只有 DeepSeek 官方认识这个字段；其它 OpenAI 兼容服务收到可能直接 400。
bool shouldSendThinking(bool supportsThinking, bool deepThinking) =>
    supportsThinking && !deepThinking;

/// 一份来源配置。
class AiSourceConfig {
  const AiSourceConfig({
    this.providerId = 'deepseek',
    this.baseUrl = '',
    this.apiKey = '',
    this.model = '',
  });

  /// 当前选中的厂商 id；`custom` 表示列表最后的「自定义」。
  final String providerId;

  final String baseUrl;
  final String apiKey;
  final String model;

  bool get isCustomPreset => providerId == kCustomProviderId;

  /// 展示用的厂商名。
  String get providerName =>
      findAiProvider(providerId)?.name ?? '自定义服务';

  /// 实际请求的地址。
  String get chatUrl => normalizeChatUrl(baseUrl);

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
  String? get balanceUrl => findAiProvider(providerId)?.balanceUrl;

  AiBalanceFormat get balanceFormat =>
      findAiProvider(providerId)?.balanceFormat ?? AiBalanceFormat.none;

  /// 余额说明。
  String get balanceHint => findAiProvider(providerId)?.balanceHint ?? '';

  bool get supportsBalance =>
      balanceUrl != null && balanceFormat != AiBalanceFormat.none;

  /// 实际使用的 Key。
  String get effectiveApiKey => apiKey.trim();

  /// 实际使用的模型名。
  String get effectiveModel => model.trim();

  /// 是否支持 `thinking` 字段（仅 DeepSeek 官方）。
  bool get supportsThinking => providerId == 'deepseek';

  /// 表单校验，返回可直接展示的中文错误；通过返回 null。
  String? validate() {
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
    String? providerId,
    String? baseUrl,
    String? apiKey,
    String? model,
  }) {
    return AiSourceConfig(
      providerId: providerId ?? this.providerId,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'providerId': providerId,
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'model': model,
      };

  factory AiSourceConfig.fromJson(Map<String, dynamic> json) {
    // 旧版本存过 mode / freeModelIndex，读进来直接忽略。
    return AiSourceConfig(
      providerId: (json['providerId'] as String?) ?? 'deepseek',
      baseUrl: (json['baseUrl'] as String?) ?? '',
      apiKey: (json['apiKey'] as String?) ?? '',
      model: (json['model'] as String?) ?? '',
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
