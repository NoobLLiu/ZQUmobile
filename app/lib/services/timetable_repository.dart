/// 课表本地存储（SharedPreferences，存 JSON）。
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/timetable.dart';

/// 课表仓库：负责读写本地缓存的课表。
class TimetableRepository {
  TimetableRepository._();

  static const _prefsKey = 'zsy_timetable_json';
  static const _prefsKeyLogin = 'zsy_jwgl_logged_in';

  static Timetable? _cache;

  /// 读取本地缓存的课表；没有则返回 null。
  static Future<Timetable?> load() async {
    if (_cache != null) return _cache;
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final tt = Timetable.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      _cache = tt;
      return tt;
    } catch (_) {
      // 缓存损坏时忽略，等下次抓取覆盖
      return null;
    }
  }

  /// 保存课表到本地。
  static Future<void> save(Timetable tt) async {
    _cache = tt;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_prefsKey, jsonEncode(tt.toJson()));
  }

  /// 清空课表缓存。
  static Future<void> clear() async {
    _cache = null;
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_prefsKey);
  }

  /// 记录是否已登录教务系统（仅用于界面提示，不存密码）。
  static Future<void> setLoggedIn(bool value) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_prefsKeyLogin, value);
  }

  /// 是否已登录过教务系统。
  static Future<bool> isLoggedIn() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getBool(_prefsKeyLogin) ?? false;
  }
}
