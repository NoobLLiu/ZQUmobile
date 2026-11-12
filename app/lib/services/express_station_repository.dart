/// 快递站数据仓库：出厂内置包 → 本地缓存 → Gitee 热更新 → GitHub 兜底。
///
/// 数据源是 Gitee 仓库里的文件（不是 Release 附件）：
/// `https://gitee.com/NoobLLiu/ZQUmobile/raw/master/data/express_stations.json`
/// 改一次文件即可生效，不需要重建 Release、不用重传 APK；
/// Release 里的 version.json 继续只负责 App 版本更新。
///
/// 任何一步失败都静默回退，页面永远有数据可显示。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/express_station.dart';

/// 本次展示的数据来自哪里。
enum ExpressStationSource {
  /// 出厂内置（编译期快照 / assets 初始包）。
  bundled,

  /// 上次热更新写入的本地缓存。
  cache,

  /// 本次刚从远端拉到的最新数据。
  remote,
}

/// 一次加载的结果。
class ExpressStationLoadResult {
  const ExpressStationLoadResult({
    required this.data,
    required this.source,
    this.error,
  });

  final ExpressStationData data;
  final ExpressStationSource source;

  /// 远端拉取失败的原因（成功或跳过联网时为 null）。
  final String? error;

  /// 是否拿到了比出厂包更新的在线数据。
  bool get gotUpdate => source == ExpressStationSource.remote;
}

/// 可注入的网络取文本函数（组件测试用），返回 null 表示该源不可用。
typedef ExpressStationFetcher = Future<String?> Function(String url);

/// 快递站数据仓库。
class ExpressStationRepository {
  ExpressStationRepository({
    this.seed,
    this.assetPath = kAssetPath,
    this.cacheKey = kCacheKey,
    this.cacheTtl = const Duration(hours: 6),
    this.fetchTimeout = const Duration(seconds: 8),
    this.fetcher,
    this.loadAsset = true,
  });

  /// 页面默认使用的单例，测试里可整体替换。
  static ExpressStationRepository instance = ExpressStationRepository();

  /// 是否允许自动联网热更新；组件测试里关掉，避免真实请求。
  static bool autoFetch = true;

  /// Gitee 仓库内的数据文件（国内可匿名读取，首选）。
  static const String giteeRawUrl =
      'https://gitee.com/NoobLLiu/ZQUmobile/raw/master/data/express_stations.json';

  /// GitHub 仓库内同一份文件，Gitee 不通时兜底。
  static const String githubRawUrl =
      'https://raw.githubusercontent.com/NoobLLiu/ZQUmobile/main/data/express_stations.json';

  /// CI 编译时合入的出厂初始包。
  static const String kAssetPath = 'assets/express_stations.json';

  /// 热更新缓存（存 JSON 结构 + 拉取时间）。
  static const String kCacheKey = 'zsy_express_stations';

  /// 内置快照覆盖（测试用）；null 时用编译期生成的 [kBundledExpressStationData]。
  final ExpressStationData? seed;

  final String assetPath;
  final String cacheKey;
  final Duration cacheTtl;
  final Duration fetchTimeout;
  final ExpressStationFetcher? fetcher;

  /// 是否读取 assets 初始包；组件测试里关掉，避免 fake async 下卡在资源通道。
  final bool loadAsset;

  /// 同步可得的出厂数据，保证页面首帧不空、组件测试不用等网络。
  ExpressStationData get bundled => seed ?? kBundledExpressStationData;

  /// 加载可展示的数据。
  ///
  /// [forceRefresh] 为「手动更新数据」按钮用：忽略缓存新鲜度立即联网，
  /// 但仍受 [autoFetch] 约束（测试环境不会真的发请求）。
  Future<ExpressStationLoadResult> load({bool forceRefresh = false}) async {
    var current = bundled;
    var source = ExpressStationSource.bundled;

    final cached = await _readCache();
    if (cached != null && cached.data.revision > current.revision) {
      current = cached.data;
      source = ExpressStationSource.cache;
    }

    // assets 初始包与编译期快照内容一致；万一两者不同步，以 revision 更高的为准。
    final asset = await _loadAsset();
    if (asset != null && asset.revision > current.revision) {
      current = asset;
    }

    String? error;
    final shouldFetch = autoFetch && (forceRefresh || _isStale(cached?.fetchedAt));
    if (shouldFetch) {
      try {
        final remote = await _fetchRemote();
        if (remote == null) {
          error = '未获取到在线数据，已使用本地数据';
        } else if (remote.revision > current.revision) {
          await _writeCache(remote);
          current = remote;
          source = ExpressStationSource.remote;
        } else {
          // 远端不比本地新，刷新一下时间戳，避免每次进页都请求。
          await _writeCache(current);
        }
      } catch (_) {
        error = '更新失败，已使用本地数据';
      }
    }

    return ExpressStationLoadResult(
      data: current,
      source: source,
      error: error,
    );
  }

  /// 清掉热更新缓存（回到出厂数据）。
  Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(cacheKey);
    } catch (_) {}
  }

  Future<({ExpressStationData data, int fetchedAt})?> _readCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(cacheKey);
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final body = decoded['data'];
      if (body is! Map) return null;
      final data = ExpressStationData.fromJson(Map<String, dynamic>.from(body));
      if (!data.isValid) return null;
      return (
        data: data,
        fetchedAt: (decoded['fetchedAt'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  Future<ExpressStationData?> _loadAsset() async {
    if (!loadAsset) return null;
    try {
      final raw = await rootBundle.loadString(assetPath);
      final data = ExpressStationData.parse(raw);
      return data.isValid ? data : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCache(ExpressStationData data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        cacheKey,
        jsonEncode({
          'fetchedAt': DateTime.now().millisecondsSinceEpoch,
          'data': data.toJson(),
        }),
      );
    } catch (_) {}
  }

  bool _isStale(int? fetchedAt) {
    if (fetchedAt == null || fetchedAt <= 0) return true;
    return DateTime.now().millisecondsSinceEpoch - fetchedAt >
        cacheTtl.inMilliseconds;
  }

  Future<ExpressStationData?> _fetchRemote() async {
    final getter = fetcher ?? _httpGet;
    // Gitee raw 会 302 到带签名的 CDN，加时间戳顺便破 CDN 缓存。
    final bust = DateTime.now().millisecondsSinceEpoch;
    for (final url in [giteeRawUrl, githubRawUrl]) {
      try {
        final body = await getter('$url?t=$bust');
        if (body == null || body.trim().isEmpty) continue;
        final data = ExpressStationData.parse(body);
        if (data.isValid) return data;
      } catch (_) {
        // 换下一个源。
      }
    }
    return null;
  }

  Future<String?> _httpGet(String url) async {
    final client = HttpClient()..connectionTimeout = fetchTimeout;
    try {
      final request = await client
          .getUrl(Uri.parse(url))
          .timeout(fetchTimeout);
      request.followRedirects = true;
      request.maxRedirects = 5;
      request.headers.set(HttpHeaders.userAgentHeader, 'ZhangShangYanYuan');
      final response = await request.close().timeout(fetchTimeout);
      if (response.statusCode != HttpStatus.ok) return null;
      return await utf8.decoder.bind(response).join().timeout(fetchTimeout);
    } finally {
      client.close();
    }
  }
}
