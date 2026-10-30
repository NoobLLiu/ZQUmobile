/// 水电查询结果的本地缓存。
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/utility.dart';

/// 一份带时间戳的水电缓存。
class UtilityCache {
  const UtilityCache({
    required this.studentId,
    required this.rooms,
    required this.fetchedAt,
  });

  /// 缓存归属的学号（换学号后缓存作废）。
  final String studentId;

  final List<UtilityRoom> rooms;

  final DateTime fetchedAt;

  /// 缓存年龄。
  Duration get age => DateTime.now().difference(fetchedAt);

  Map<String, dynamic> toJson() => {
    'studentId': studentId,
    'fetchedAt': fetchedAt.millisecondsSinceEpoch,
    'rooms': [for (final r in rooms) r.toJson()],
  };

  factory UtilityCache.fromJson(Map<String, dynamic> j) => UtilityCache(
    studentId: (j['studentId'] ?? '').toString(),
    fetchedAt: DateTime.fromMillisecondsSinceEpoch(
      (j['fetchedAt'] as num?)?.toInt() ?? 0,
    ),
    rooms: [
      if (j['rooms'] is List)
        for (final r in j['rooms'] as List)
          if (r is Map) UtilityRoom.fromJson(Map<String, dynamic>.from(r)),
    ],
  );
}

/// 水电缓存仓库（只存本机）。
class UtilityCacheRepository {
  UtilityCacheRepository._();

  static const String _prefsKey = 'zsy_utility_cache';

  /// 读取缓存；从未保存过、数据损坏或为空时返回 null。
  static Future<UtilityCache?> load() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final cache = UtilityCache.fromJson(decoded);
        if (cache.rooms.isNotEmpty) return cache;
      }
    } catch (_) {
      /* 损坏则视为无缓存 */
    }
    return null;
  }

  /// 以当前时间保存一份缓存。
  static Future<void> save(String studentId, List<UtilityRoom> rooms) async {
    final sp = await SharedPreferences.getInstance();
    final cache = UtilityCache(
      studentId: studentId,
      rooms: rooms,
      fetchedAt: DateTime.now(),
    );
    await sp.setString(_prefsKey, jsonEncode(cache.toJson()));
  }
}
