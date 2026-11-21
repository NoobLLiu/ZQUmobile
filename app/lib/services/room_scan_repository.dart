/// 空教室扫描数据的本地存储（SharedPreferences，存 JSON）。
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/empty_classroom.dart';

/// 扫描数据仓库。
class RoomScanRepository {
  RoomScanRepository._();

  static const _prefsKey = 'zsy_room_scan_json';

  static RoomScanData? _cache;

  /// 读取本地缓存的扫描数据；没有则返回 null。
  static Future<RoomScanData?> load() async {
    final cached = _cache;
    if (cached != null) return cached;
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final data = RoomScanData.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      if (data.lessons.isEmpty) return null;
      _cache = data;
      return data;
    } catch (_) {
      // 缓存损坏时忽略，等下次扫描覆盖
      return null;
    }
  }

  /// 保存扫描结果到本地。
  static Future<void> save(RoomScanData data) async {
    _cache = data;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_prefsKey, jsonEncode(data.toJson()));
  }

  /// 清空扫描数据。
  static Future<void> clear() async {
    _cache = null;
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_prefsKey);
  }
}
