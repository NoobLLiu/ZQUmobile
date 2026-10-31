/// 通用个人信息：学号、两套密码、学期、是否已购校园网。
///
/// 这些信息只存在本机，用于：
///   - 自动登录时填写学号与密码（WebVPN / 教务系统各一套）；
///   - 按「是否已购校园网」决定走校内直连还是 WebVPN；
///   - 作为导入/显示课表时的默认学期。
///
/// ⚠️ 密码按产品要求保存在本机（shared_preferences），不做任何上传。
/// 这条设定于 2026-10-31 由「一律不存密码」改为「代填账号密码验证码」。
library;

/// 可选的学期（目前预留 2026-2027 学年两个学期）。
const List<String> kTermOptions = [
  '2026-2027-1',
  '2026-2027-2',
];

/// 默认学期：学年第一学期。
const String kDefaultTerm = '2026-2027-1';

/// 学号校验：12 位纯数字。
bool isValidStudentId(String id) => RegExp(r'^\d{12}$').hasMatch(id.trim());

/// 个人信息。
class Profile {
  const Profile({
    this.studentId = '',
    this.term = kDefaultTerm,
    this.hasCampusNetwork = false,
    this.webvpnPassword = '',
    this.jwglPassword = '',
  });

  /// 学号（12 位数字），同时是 WebVPN 与教务系统的账号。
  final String studentId;

  /// 学期，形如 2026-2027-1。
  final String term;

  /// 是否已购校园网。true 走校内直连，false 走 WebVPN。
  final bool hasCampusNetwork;

  /// WebVPN（统一身份认证）密码，仅本机保存。
  final String webvpnPassword;

  /// 教务系统密码，仅本机保存。
  final String jwglPassword;

  /// 资料是否完整：学号合法、学期非空、两套密码都已填写。
  ///
  /// 密码填齐才能做到「打开登录页即自动登录」，因此纳入完整性判断。
  bool get isComplete =>
      isValidStudentId(studentId) &&
      term.isNotEmpty &&
      jwglPassword.trim().isNotEmpty &&
      webvpnPassword.trim().isNotEmpty;

  /// 是否已保存过密码，用于「我的」页面展示提示。
  bool get hasPasswords =>
      jwglPassword.isNotEmpty || webvpnPassword.isNotEmpty;

  Profile copyWith({
    String? studentId,
    String? term,
    bool? hasCampusNetwork,
    String? webvpnPassword,
    String? jwglPassword,
  }) =>
      Profile(
        studentId: studentId ?? this.studentId,
        term: term ?? this.term,
        hasCampusNetwork: hasCampusNetwork ?? this.hasCampusNetwork,
        webvpnPassword: webvpnPassword ?? this.webvpnPassword,
        jwglPassword: jwglPassword ?? this.jwglPassword,
      );

  Map<String, dynamic> toJson() => {
        'studentId': studentId,
        'term': term,
        'hasCampusNetwork': hasCampusNetwork,
        'webvpnPassword': webvpnPassword,
        'jwglPassword': jwglPassword,
      };

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        studentId: (j['studentId'] ?? '').toString(),
        term: (j['term'] ?? kDefaultTerm).toString(),
        hasCampusNetwork: j['hasCampusNetwork'] == true,
        webvpnPassword: (j['webvpnPassword'] ?? '').toString(),
        jwglPassword: (j['jwglPassword'] ?? '').toString(),
      );
}
