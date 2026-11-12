/// 快递站数据文件 / 出厂初始包 / 热更新仓库的测试。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zhangshang_yanyuan/generated/express_stations_bundled.dart';
import 'package:zhangshang_yanyuan/models/express_station.dart';
import 'package:zhangshang_yanyuan/pages/express_station_page.dart';
import 'package:zhangshang_yanyuan/services/express_station_repository.dart';

Map<String, dynamic> _remoteJson({int revision = 2, String notice = '在线说明'}) {
  final json = kBundledExpressStationData.toJson();
  json['revision'] = revision;
  json['updatedAt'] = '2026-12-01';
  json['notice'] = notice;
  return json;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ExpressStationRepository.autoFetch = true;
    ExpressStationRepository.instance =
        ExpressStationRepository(loadAsset: false);
  });

  tearDown(() {
    ExpressStationRepository.autoFetch = true;
    ExpressStationRepository.instance = ExpressStationRepository();
  });

  group('数据文件', () {
    test('源数据 / assets 初始包 / 内置快照三者一致', () {
      final source = File('../data/express_stations.json').readAsStringSync();
      final asset = File('assets/express_stations.json').readAsStringSync();
      expect(asset, source);
      expect(kBundledExpressStationJson, source);
      final parsed = ExpressStationData.parse(source);
      expect(parsed.isValid, isTrue);
      expect(parsed.schemaVersion, kExpressStationSchemaVersion);
      expect(parsed.revision, greaterThanOrEqualTo(1));
    });

    test('位置、备注、按星期时间、说明文字都从 JSON 解析', () {
      final data = kBundledExpressStationData;
      expect(
        data.notice,
        '此模块时间仅作功能演示，部分内容待修正，部分数据待补充。',
      );
      final east = data.groups.firstWhere((g) => g.name == '东门');
      expect(east.location, '主校区东门');
      expect(east.note, isNotEmpty);
      expect(east.gateHours!.format(), '07:00-23:00');
      final kfc = east.stations.firstWhere((s) => s.name == '肯德基旁驿站');
      expect(kfc.hours!.format(), '10:00-21:00');
      expect(kfc.weekdayHours[5]!.format(), '11:00-20:50');
      expect(kfc.note, isNotEmpty);
      final south = data.groups.firstWhere((g) => g.name == '南门');
      expect(south.stations.single.hasData, isFalse);
      expect(south.stations.single.note, isNotEmpty);
    });

    test('序列化可往返，非法数据与未来 schema 会被拒绝', () {
      final data = kBundledExpressStationData;
      final roundTrip = ExpressStationData.parse(data.encode());
      expect(roundTrip.revision, data.revision);
      expect(roundTrip.groups.length, data.groups.length);
      expect(roundTrip.groups.first.stations.first.name, '京东快递站');
      expect(() => ExpressStationData.parse('oops'), throwsFormatException);
      final future = ExpressStationData.fromJson({
        'schemaVersion': 99,
        'revision': 999,
        'groups': [
          {
            'name': 'x',
            'stations': [
              {'name': 'y'}
            ]
          }
        ],
      });
      expect(future.isValid, isFalse);
    });
  });

  group('热更新仓库', () {
    test('远端 revision 更高时替换并写入缓存', () async {
      final repo = ExpressStationRepository(
        loadAsset: false,
        fetcher: (url) async => jsonEncode(_remoteJson(revision: 5)),
      );
      final result = await repo.load(forceRefresh: true);
      expect(result.gotUpdate, isTrue);
      expect(result.source, ExpressStationSource.remote);
      expect(result.data.revision, 5);
      expect(result.data.notice, '在线说明');

      // 缓存新鲜时不再联网，直接用缓存。
      final offline = ExpressStationRepository(
        loadAsset: false,
        fetcher: (url) async => throw StateError('缓存新鲜时不该联网'),
      );
      final cached = await offline.load();
      expect(cached.source, ExpressStationSource.cache);
      expect(cached.data.revision, 5);
    });

    test('远端不可用或数据更旧时回退出厂数据', () async {
      final failed = await ExpressStationRepository(
        loadAsset: false,
        fetcher: (url) async => null,
      ).load(forceRefresh: true);
      expect(failed.error, isNotNull);
      expect(failed.data.revision, kBundledExpressStationData.revision);

      SharedPreferences.setMockInitialValues({});
      final older = await ExpressStationRepository(
        loadAsset: false,
        fetcher: (url) async =>
            jsonEncode(_remoteJson(revision: 0, notice: '旧数据')),
      ).load(forceRefresh: true);
      expect(older.gotUpdate, isFalse);
      expect(older.data.notice, kBundledExpressStationData.notice);
    });

    test('关闭 autoFetch 时完全不联网', () async {
      ExpressStationRepository.autoFetch = false;
      var calls = 0;
      final repo = ExpressStationRepository(
        loadAsset: false,
        fetcher: (url) async {
          calls++;
          return jsonEncode(_remoteJson());
        },
      );
      final result = await repo.load(forceRefresh: true);
      expect(calls, 0);
      expect(result.data.revision, kBundledExpressStationData.revision);
    });
  });

  group('页面热更新', () {
    testWidgets('进页静默热更新会替换说明文字与数据版本', (tester) async {
      // 底部说明在长列表末尾，必须放大视口让它被 ListView 构建出来。
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final json = _remoteJson(revision: 3, notice: '热更新后的说明');
      final repo = ExpressStationRepository(
        loadAsset: false,
        fetcher: (url) async => jsonEncode(json),
      );
      await tester.pumpWidget(MaterialApp(
        home: ExpressStationPage(
          clock: () => DateTime(2026, 10, 28, 15),
          repository: repo,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('热更新后的说明'), findsOneWidget);
      expect(find.textContaining('r3'), findsOneWidget);
      expect(find.textContaining('在线更新'), findsOneWidget);
    });

    testWidgets('点卡片能看到位置与备注详情', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repo = ExpressStationRepository(
        loadAsset: false,
        fetcher: (url) async => null,
      );
      await tester.pumpWidget(
        MaterialApp(home: ExpressStationPage(repository: repo)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('南门车库驿站'));
      await tester.pumpAndSettle();

      expect(find.text('分组位置'), findsOneWidget);
      expect(find.text('主校区南门'), findsOneWidget);
      expect(
        find.text('营业时间与具体位置待补充，欢迎反馈。'),
        findsOneWidget,
      );
    });
  });
}
