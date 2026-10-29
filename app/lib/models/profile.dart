/// 通用个人信息：学号、学期、是否已购校园网。
///
/// 这些信息只存在本机，用于：
///   - 教务登录页自动填写学号（不保存密码）；
///   - 按「是否已购校园网」决定走校内直连还是 WebVPN；
///   - 作为导入/显示课表时的默认学期。
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
  });

  /// 学号（12 位数字）。
  final String studentId;

  /// 学期，形如 2026-2027-1。
  final String term;

  /// 是否已购校园网。true 走校内直连，false 走 WebVPN。
  final bool hasCampusNetwork;

  /// 资料是否完整（学号合法且学期非空）。
  bool get isComplete => isValidStudentId(studentId) && term.isNotEmpty;

  Profile copyWith({
    String? studentId,
    String? term,
    bool? hasCampusNetwork,
  }) =>
      Profile(
        studentId: studentId ?? this.studentId,
        term: term ?? this.term,
        hasCampusNetwork: hasCampusNetwork ?? this.hasCampusNetwork,
      );

  Map<String, dynamic> toJson() => {
        'studentId': studentId,
        'term': term,
        'hasCampusNetwork': hasCampusNetwork,
      };

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        studentId: (j['studentId'] ?? '').toString(),
        term: (j['term'] ?? kDefaultTerm).toString(),
        hasCampusNetwork: j['hasCampusNetwork'] == true,
      );
}
