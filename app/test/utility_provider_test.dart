/// UtilityDataProvider（看板页与水电页共用的水电获取策略）单测。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zhangshang_yanyuan/models/utility.dart';
import 'package:zhangshang_yanyuan/services/utility_cache_repository.dart';
import 'package:zhangshang_yanyuan/services/utility_provider.dart';
import 'package:zhangshang_yanyuan/services/utility_service.dart';

const _room = UtilityRoom(roomName: '12栋 507', electricity: 23.6, water: 8.2);

String _cacheJson(DateTime at) => jsonEncode({
  'studentId': '202301010101',
  'fetchedAt': at.millisecondsSinceEpoch,
  'rooms': [_room.toJson()],
});

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // 默认 fetcher 成功返回，用例里按需覆盖
    UtilityDataProvider.fetcher = (studentId) async => [_room];
  });

  tearDown(() {
    UtilityDataProvider.fetcher = UtilityService.fetchRooms;
  });

  test('load：新鲜缓存直接使用，不刷新', () async {
    SharedPreferences.setMockInitialValues({
      'zsy_utility_cache': _cacheJson(DateTime.now()),
    });

    final snap = await UtilityDataProvider.load('202301010101');

    expect(snap.rooms, isNotNull);
    expect(snap.rooms!.first.roomName, '12栋 507');
    expect(snap.shouldRefresh, isFalse);
    expect(snap.error, isNull);
  });

  test('load：10 分钟 ~ 12 小时的缓存先展示并建议后台刷新', () async {
    SharedPreferences.setMockInitialValues({
      'zsy_utility_cache': _cacheJson(
        DateTime.now().subtract(const Duration(hours: 1)),
      ),
    });

    final snap = await UtilityDataProvider.load('202301010101');

    expect(snap.rooms, isNotNull);
    expect(snap.shouldRefresh, isTrue);
  });

  test('load：超过 12 小时的缓存需立即刷新', () async {
    SharedPreferences.setMockInitialValues({
      'zsy_utility_cache': _cacheJson(
        DateTime.now().subtract(const Duration(hours: 13)),
      ),
    });

    final snap = await UtilityDataProvider.load('202301010101');

    expect(snap.rooms, isNull);
    expect(snap.shouldRefresh, isTrue);
  });

  test('load：缓存属于其他学号视为无缓存', () async {
    SharedPreferences.setMockInitialValues({
      'zsy_utility_cache': _cacheJson(DateTime.now()),
    });

    final snap = await UtilityDataProvider.load('999999999999');

    expect(snap.rooms, isNull);
    expect(snap.shouldRefresh, isTrue);
  });

  test('refresh：成功并写入缓存', () async {
    var called = false;
    UtilityDataProvider.fetcher = (studentId) async {
      expect(studentId, '202301010101');
      called = true;
      return [_room];
    };

    final snap = await UtilityDataProvider.refresh('202301010101');

    expect(called, isTrue);
    expect(snap.rooms, isNotNull);
    expect(snap.error, isNull);
    final cache = await UtilityCacheRepository.load();
    expect(cache, isNotNull);
    expect(cache!.rooms.first.electricity, 23.6);
  });

  test('refresh：失败回退本地缓存并带出失败原因', () async {
    SharedPreferences.setMockInitialValues({
      'zsy_utility_cache': _cacheJson(
        DateTime.now().subtract(const Duration(hours: 13)),
      ),
    });
    UtilityDataProvider.fetcher =
        (studentId) async => throw UtilityException('连接超时，请稍后重试');

    final snap = await UtilityDataProvider.refresh('202301010101');

    expect(snap.rooms, isNotNull);
    expect(snap.stale, isTrue);
    expect(snap.error, '连接超时，请稍后重试');
  });

  test('refresh：失败且无缓存时 rooms 为 null（未查到）', () async {
    UtilityDataProvider.fetcher =
        (studentId) async => throw UtilityException('该学号未绑定宿舍房间');

    final snap = await UtilityDataProvider.refresh('202301010101');

    expect(snap.rooms, isNull);
    expect(snap.error, '该学号未绑定宿舍房间');
  });
}
