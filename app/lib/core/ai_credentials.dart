/// 演示期内置的 DeepSeek 凭据。
///
/// 这里是**参赛作品提交阶段**的特殊约定：为了让人打开就能用，
/// App 直接内置了参赛组自己的 API Key，用户无需填写。
/// 正式上线时应当改成由用户在设置里填自己的 Key，见页脚的说明文案。
///
/// 存储方式：不写明文，按 [kMask] 异或后存成字节表，运行时还原。
/// —— 这不是加密，只是避免 Key 以明文形式出现在源码 / 反编译字符串里，
///    也避免被人 grep 一行就抄走。
library;

/// 异或掩码（改这个值必须同步重新生成下面的字节表）。
const int _kMask = 91;

const List<int> _kMaskedKey = <int>[
  0x28, 0x30, 0x76, 0x63, 0x6c, 0x6b, 0x39, 0x62, 0x6f, 0x69, 0x6f, 0x3a,
  0x6a, 0x68, 0x6e, 0x6f, 0x63, 0x69, 0x6c, 0x63, 0x6d, 0x3f, 0x39, 0x6f,
  0x63, 0x6c, 0x3e, 0x3d, 0x6a, 0x62, 0x6e, 0x6c, 0x68, 0x3d, 0x6a,
];

/// DeepSeek 官方接口地址。
const String kDeepSeekEndpoint = 'https://api.deepseek.com/chat/completions';

/// 模型列表接口（仅用于自检，App 内不调用）。
const String kDeepSeekModelsEndpoint = 'https://api.deepseek.com/models';

/// 还原内置 Key。
String deepSeekApiKey() =>
    String.fromCharCodes(_kMaskedKey.map((b) => b ^ _kMask));
