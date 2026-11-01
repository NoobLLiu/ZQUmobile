/// 附属日程的本地存储（只存本机，SharedPreferences）。
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/attachment_schedule.dart';

/// 附属日程仓库。
class AttachmentScheduleRepository {
  AttachmentScheduleRepository._();

  static const String _prefsKey = 'zsy_attachment_schedules';

  /// 读取全部日程（按开始时间排序）；没有数据或损坏时返回空列表。
  static Future<List<AttachmentSchedule>> load() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final list = [
        for (final item in decoded)
          if (item is Map)
            AttachmentSchedule.fromJson(Map<String, dynamic>.from(item)),
      ]..sort((a, b) {
          final byTime = AttachmentSchedule.toMinute(a.start)
              .compareTo(AttachmentSchedule.toMinute(b.start));
          if (byTime != 0) return byTime;
          return a.type.index.compareTo(b.type.index);
        });
      return list;
    } catch (_) {
      return const [];
    }
  }

  static Future<void> _save(List<AttachmentSchedule> list) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
      _prefsKey,
      jsonEncode([for (final s in list) s.toJson()]),
    );
  }

  /// 新增一条（生成 id 后落库）。
  static Future<AttachmentSchedule> add(AttachmentSchedule schedule) async {
    final list = [...await load()];
    final withId = schedule.id.isEmpty
        ? schedule.copyWith(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
          )
        : schedule;
    list.add(withId);
    await _save(list);
    return withId;
  }

  /// 按 id 更新；找不到则忽略。
  static Future<void> update(AttachmentSchedule schedule) async {
    final list = [...await load()];
    final index = list.indexWhere((s) => s.id == schedule.id);
    if (index < 0) return;
    list[index] = schedule;
    await _save(list);
  }

  /// 切换启用状态。
  static Future<void> setEnabled(String id, bool enabled) async {
    final list = [...await load()];
    final index = list.indexWhere((s) => s.id == id);
    if (index < 0) return;
    list[index] = list[index].copyWith(enabled: enabled);
    await _save(list);
  }

  /// 按 id 删除。
  static Future<void> remove(String id) async {
    final list = [...await load()];
    list.removeWhere((s) => s.id == id);
    await _save(list);
  }
}
