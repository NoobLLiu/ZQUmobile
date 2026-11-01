/// 水电余额的统一获取策略：看板页与水电费查询页共用同一套刷新逻辑。
///
/// 缓存分档与水电页进入逻辑一致：
///   - 缓存 10 分钟内：直接展示缓存，不发起请求；
///   - 缓存 10 分钟 ~ 12 小时：先展示缓存，调用方应后台刷新；
///   - 无缓存或超过 12 小时：调用方应立即刷新。
library;

import '../models/utility.dart';
import 'utility_cache_repository.dart';
import 'utility_service.dart';

/// 一次水电查询的快照。
class UtilitySnapshot {
  const UtilitySnapshot({
    this.rooms,
    this.fetchedAt,
    this.error,
    this.shouldRefresh = false,
  });

  /// 当前可展示的房间数据；null 表示无可用数据（未查到）。
  final List<UtilityRoom>? rooms;

  /// 数据的获取时间。
  final DateTime? fetchedAt;

  /// 刷新失败原因（可直接展示给用户）。
  final String? error;

  /// load() 返回时为 true 表示调用方应继续发起网络刷新。
  final bool shouldRefresh;

  /// 是否在展示「刷新失败后回退的缓存」。
  bool get stale => error != null;
}

/// 统一的水电数据入口。
class UtilityDataProvider {
  UtilityDataProvider._();

  /// 缓存新鲜期：该时间内直接用缓存，不发起请求。
  static const Duration freshWindow = Duration(minutes: 10);

  /// 缓存有效期：超过则视为过期，需立即刷新。
  static const Duration cacheLifetime = Duration(hours: 12);

  /// 网络获取函数（测试可替换）。
  static Future<List<UtilityRoom>> Function(String studentId) fetcher =
      UtilityService.fetchRooms;

  /// 进入页面时读取：按缓存年龄分档，决定直接展示还是需要刷新。
  ///
  /// 缓存属于其他学号时视为无缓存。
  static Future<UtilitySnapshot> load(String studentId) async {
    final cache = await UtilityCacheRepository.load();
    if (cache != null &&
        cache.studentId == studentId &&
        cache.rooms.isNotEmpty) {
      if (cache.age < freshWindow) {
        return UtilitySnapshot(rooms: cache.rooms, fetchedAt: cache.fetchedAt);
      }
      if (cache.age < cacheLifetime) {
        return UtilitySnapshot(
          rooms: cache.rooms,
          fetchedAt: cache.fetchedAt,
          shouldRefresh: true,
        );
      }
    }
    // 无缓存或已过期：需要立即刷新。
    return const UtilitySnapshot(shouldRefresh: true);
  }

  /// 从网络刷新；失败时回退本地缓存（若有）并带上失败原因。
  static Future<UtilitySnapshot> refresh(String studentId) async {
    try {
      final rooms = await fetcher(studentId);
      await UtilityCacheRepository.save(studentId, rooms);
      return UtilitySnapshot(rooms: rooms, fetchedAt: DateTime.now());
    } catch (e) {
      final message = e is UtilityException ? e.message : '网络异常';
      final cache = await UtilityCacheRepository.load();
      if (cache != null &&
          cache.studentId == studentId &&
          cache.rooms.isNotEmpty) {
        return UtilitySnapshot(
          rooms: cache.rooms,
          fetchedAt: cache.fetchedAt,
          error: message,
        );
      }
      return UtilitySnapshot(error: message);
    }
  }
}
