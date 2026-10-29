/// 个人信息的本地存储。
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/profile.dart';

/// 个人信息仓库（只存本机，不上传）。
class ProfileRepository {
  ProfileRepository._();

  static const String _prefsKey = 'zsy_profile';

  /// 读取个人信息；从未保存过时返回默认值（isComplete 为 false）。
  ///
  /// 不做静态缓存：个人信息随时可能被修改，每次读一遍 SharedPreferences
  /// 才能保证界面看到的是最新值。
  static Future<Profile> load() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return const Profile();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return Profile.fromJson(decoded);
    } catch (_) {
      /* 损坏则回退默认值 */
    }
    return const Profile();
  }

  /// 保存个人信息。
  static Future<void> save(Profile profile) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_prefsKey, jsonEncode(profile.toJson()));
  }
}
