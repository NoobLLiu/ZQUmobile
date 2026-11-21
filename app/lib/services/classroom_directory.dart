/// 教室目录：来自教务部「课室平面」的一教/二教教室清单（内置资源）。
///
/// 资源文件 assets/data/classrooms.json 只保留 category=教室 的房间
/// （普通/多媒体/语音/考研自习），办公室与功能室不参与空教室判定。
library;

import 'dart:convert';

import 'package:flutter/services.dart';

/// 一间教室。
class Classroom {
  const Classroom({
    required this.building,
    required this.number,
    required this.floor,
    required this.type,
  });

  /// 楼栋编号：1=第一教学楼，2=第二教学楼。
  final int building;

  /// 房间编号，如 "101"。
  final String number;

  /// 楼层。
  final int floor;

  /// 教室类型（普通教室 / 多媒体教室 / 语音教室 / 考研自习教室）。
  final String type;

  /// 楼栋显示名。
  String get buildingName => building == 1 ? '第一教学楼' : '第二教学楼';

  /// 显示名，如 "1-101"。
  String get shortLabel => '$building-$number';
}

/// 教室目录。
class ClassroomDirectory {
  ClassroomDirectory._(this.rooms)
      : _keys = {
          for (final r in rooms) '${r.building}-${r.number}': r,
        };

  final List<Classroom> rooms;
  final Map<String, Classroom> _keys;

  static const String assetPath = 'assets/data/classrooms.json';

  static ClassroomDirectory? _cache;

  /// 从内置资源加载（带进程级缓存）。
  static Future<ClassroomDirectory> load() async {
    final cached = _cache;
    if (cached != null) return cached;
    final raw = await rootBundle.loadString(assetPath);
    final dir = fromJsonString(raw);
    _cache = dir;
    return dir;
  }

  /// 便于测试与复用的解析入口。
  static ClassroomDirectory fromJsonString(String raw) {
    final rooms = <Classroom>[];
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final buildings = (decoded['buildings'] as List?) ?? const [];
      for (final b in buildings) {
        final map = b as Map<String, dynamic>;
        final building = (map['code'] as num?)?.toInt() ?? 0;
        final roomList = (map['rooms'] as List?) ?? const [];
        for (final r in roomList) {
          final room = r as Map<String, dynamic>;
          rooms.add(Classroom(
            building: building,
            number: (room['n'] ?? '').toString(),
            floor: (room['f'] as num?)?.toInt() ?? 0,
            type: (room['t'] ?? '普通教室').toString(),
          ));
        }
      }
    } catch (_) {
      // 资源损坏时返回空目录，页面会显示无可用教室
    }
    rooms.sort((a, b) {
      final byBuilding = a.building.compareTo(b.building);
      if (byBuilding != 0) return byBuilding;
      final byFloor = a.floor.compareTo(b.floor);
      if (byFloor != 0) return byFloor;
      return a.number.compareTo(b.number);
    });
    return ClassroomDirectory._(rooms);
  }

  /// 按楼栋 + 房间号查教室；不存在返回 null。
  Classroom? lookup(int building, String number) => _keys['$building-$number'];

  /// 是否是目录内的教室。
  bool contains(int building, String number) =>
      _keys.containsKey('$building-$number');
}
