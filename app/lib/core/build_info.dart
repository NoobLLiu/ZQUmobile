/// 构建信息：版本号、提交号、构建时间。
///
/// 由 CI 通过 `--dart-define` 注入，本地构建时取默认值。
/// 用途：让界面能直接显示「这是哪一版」，避免装了旧包却察觉不到。
library;

class BuildInfo {
  BuildInfo._();

  /// 语义化版本，如 "1.0.1"。
  static const String version =
      String.fromEnvironment('APP_VERSION', defaultValue: '1.0.0');

  /// 构建号（Android versionCode）。
  static const String buildNumber =
      String.fromEnvironment('APP_BUILD_NUMBER', defaultValue: '1');

  /// Git 提交短哈希。
  static const String gitSha =
      String.fromEnvironment('GIT_SHA', defaultValue: 'local');

  /// 构建时间（UTC），形如 2026-10-29T08:50Z。
  static const String buildTime =
      String.fromEnvironment('BUILD_TIME', defaultValue: '');

  /// 展示用全称，如 "1.0.1 (2) · da31a53"。
  static String get displayVersion {
    final short = gitSha.length > 7 ? gitSha.substring(0, 7) : gitSha;
    return '$version ($buildNumber) · $short';
  }

  /// 是否由 CI 构建。
  static bool get isCi => gitSha != 'local';
}
