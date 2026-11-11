/// 应用内更新：从 Gitee latest Release 的 version.json 检测新版本，
/// 下载本机 ABI 对应的 APK 并调起安装。
///
/// 数据源：`https://gitee.com/NoobLLiu/ZQUmobile/releases/download/latest/version.json`
/// （Gitee 同步脚本会把下载直链改写成 Gitee 地址，字段见 CI 的 version.json 生成段）。
///
/// 隐私约定：**不申请「查看已安装应用列表」（QUERY_ALL_PACKAGES）**——
/// 版本对比只用 CI 注入的 BuildInfo.buildNumber，安装只用隐式
/// ACTION_VIEW intent + FileProvider，全程不查询其他应用。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import '../core/build_info.dart';

/// version.json 里一个 APK 产物。
class UpdateAsset {
  const UpdateAsset({
    required this.abi,
    required this.name,
    required this.size,
    required this.sha256,
    required this.url,
  });

  factory UpdateAsset.fromJson(Map<String, dynamic> json) => UpdateAsset(
        abi: json['abi'] as String? ?? 'unknown',
        name: json['name'] as String,
        size: (json['size'] as num?)?.toInt() ?? 0,
        sha256: json['sha256'] as String? ?? '',
        url: json['url'] as String,
      );

  final String abi;
  final String name;
  final int size;
  final String sha256;
  final String url;

  Map<String, dynamic> toJson() => {
        'abi': abi,
        'name': name,
        'size': size,
        'sha256': sha256,
        'url': url,
      };
}

/// version.json 解析结果：最新版本信息。
class UpdateMeta {
  const UpdateMeta({
    required this.version,
    required this.versionCode,
    required this.fullVersion,
    required this.buildTime,
    required this.releaseNotes,
    required this.assets,
  });

  factory UpdateMeta.fromJson(Map<String, dynamic> json) => UpdateMeta(
        version: json['version'] as String? ?? '',
        versionCode: (json['versionCode'] as num?)?.toInt() ?? 0,
        fullVersion: json['fullVersion'] as String? ?? '',
        buildTime: json['buildTime'] as String? ?? '',
        releaseNotes: json['releaseNotes'] as String? ?? '',
        assets: [
          for (final a in (json['assets'] as List<dynamic>? ?? []))
            UpdateAsset.fromJson(a as Map<String, dynamic>),
        ],
      );

  /// 从 JSON 字符串解析，格式非法抛 FormatException。
  factory UpdateMeta.parse(String source) =>
      UpdateMeta.fromJson(jsonDecode(source) as Map<String, dynamic>);

  final String version;
  final int versionCode;
  final String fullVersion;
  final String buildTime;
  final String releaseNotes;
  final List<UpdateAsset> assets;

  /// 是否比本地 versionCode 更新。
  ///
  /// 用 CI 注入的基准 buildNumber 对比（per-ABI split APK 会被 Flutter
  /// 自动加 1000*N 偏移，系统的 packageInfo.versionCode 不可直接比）。
  bool isNewerThan(int currentCode) => versionCode > currentCode;

  Map<String, dynamic> toJson() => {
        'version': version,
        'versionCode': versionCode,
        'fullVersion': fullVersion,
        'buildTime': buildTime,
        'releaseNotes': releaseNotes,
        'assets': [for (final a in assets) a.toJson()],
      };
}

/// 应用内更新服务。
class UpdateService {
  UpdateService._();

  /// Gitee 直链（国内可用，首选）。
  static const String giteeMetaUrl =
      'https://gitee.com/NoobLLiu/ZQUmobile/releases/download/latest/version.json';

  /// GitHub 兜底（Gitee 同步未跑或被墙时）。
  static const String githubMetaUrl =
      'https://github.com/NoobLLiu/ZQUmobile/releases/download/latest/version.json';

  static const MethodChannel _channel = MethodChannel('zsy/updater');

  /// 本地基准 versionCode（本地构建无 CI 注入时按 0，视为最旧）。
  static int get localVersionCode => int.tryParse(BuildInfo.buildNumber) ?? 0;

  /// 拉取最新版本清单；先 Gitee 后 GitHub，都失败返回 null。
  static Future<UpdateMeta?> check({Duration timeout = const Duration(seconds: 15)}) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      for (final url in [giteeMetaUrl, githubMetaUrl]) {
        try {
          final req = await client.getUrl(Uri.parse(url)).timeout(timeout);
          final resp = await req.close().timeout(timeout);
          if (resp.statusCode != 200) continue;
          final body = await utf8.decoder.bind(resp).join().timeout(timeout);
          return UpdateMeta.parse(body);
        } catch (_) {
          // 换下一个源。
        }
      }
      return null;
    } finally {
      client.close();
    }
  }

  /// 本机支持的 ABI 列表（最优先在前），取不到返回 [arm64-v8a]。
  static Future<List<String>> deviceAbis() async {
    try {
      final abi = await _channel.invokeMethod<String>('deviceAbi');
      return [if (abi != null && abi.isNotEmpty) abi, 'arm64-v8a', 'armeabi-v7a'];
    } catch (_) {
      return ['arm64-v8a', 'armeabi-v7a'];
    }
  }

  /// 按设备 ABI 优先级挑一个 APK。
  static UpdateAsset? pickAsset(List<UpdateAsset> assets, List<String> abis) {
    for (final abi in abis) {
      for (final a in assets) {
        if (a.abi == abi) return a;
      }
    }
    return assets.isEmpty ? null : assets.first;
  }

  /// 下载 APK，返回本地路径。
  ///
  /// 已存在同名且 sha256 一致的缓存文件时直接复用（装「未知来源」权限
  /// 中途跳设置页回来后不用重新下载）。
  /// 进度经 [onProgress] 回调（received / total，total 可能为 0 表示未知）。
  /// [cancelDownload] 会让下载抛出。
  static Future<String> downloadApk(
    UpdateAsset asset, {
    void Function(int received, int total)? onProgress,
  }) async {
    final dirPath = await _channel.invokeMethod<String>('prepareDownload');
    if (dirPath == null || dirPath.isEmpty) {
      throw const UpdateException('无法准备下载目录');
    }
    final dir = Directory(dirPath);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final file = File('${dir.path}/${asset.name}');

    // 命中缓存（大小 + sha256 都对得上）就不重复下载。
    if (file.existsSync() && file.lengthSync() == asset.size && asset.size > 0) {
      final cached = await _sha256Of(file);
      if (cached == asset.sha256) return file.path;
      file.deleteSync();
    }

    final client = HttpClient();
    _activeClient = client;
    try {
      final req = await client.getUrl(Uri.parse(asset.url));
      final resp = await req.close();
      if (resp.statusCode != 200) {
        throw UpdateException('下载失败（HTTP ${resp.statusCode}）');
      }
      final total = resp.contentLength > 0 ? resp.contentLength : asset.size;
      var received = 0;
      final fileSink = file.openWrite();
      final hasher = _Hasher();
      try {
        await for (final chunk in resp) {
          received += chunk.length;
          fileSink.add(chunk);
          hasher.add(chunk);
          if (onProgress != null) onProgress(received, total);
        }
        await fileSink.flush();
        await fileSink.close();
      } catch (e) {
        await fileSink.close().catchError((_) {});
        if (file.existsSync()) file.deleteSync();
        rethrow;
      }
      if (asset.size > 0 && received != asset.size) {
        throw const UpdateException('下载不完整，请重试');
      }
      if (asset.sha256.isNotEmpty && hasher.hex != asset.sha256) {
        throw const UpdateException('安装包校验失败，请重试');
      }
      return file.path;
    } finally {
      _activeClient = null;
      client.close();
    }
  }

  /// 中断进行中的下载（下一次回调/await 处抛出）。
  static void cancelDownload() {
    _activeClient?.close(force: true);
    _activeClient = null;
  }

  static HttpClient? _activeClient;

  /// 调起安装。返回 'started' 或 'needPermission'（已跳到系统设置页，
  /// 允许「安装未知应用」后回来重新点更新即可，APK 有缓存不用重下）。
  static Future<String> install(String apkPath) async {
    final res = await _channel.invokeMethod<String>('installApk', apkPath);
    return res ?? 'started';
  }

  static Future<String> _sha256Of(File file) => _Hasher(file: file).hashFile();
}

class UpdateException implements Exception {
  const UpdateException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// 流式 SHA-256 汇总器（避免把 20MB APK 整个读进内存）。
class _Hasher {
  _Hasher({this.file});

  final File? file;
  final _sink = _DigestSink();
  late final _hash = sha256.startChunkedConversion(_sink);

  void add(List<int> chunk) => _hash.add(chunk);

  String get hex {
    _hash.close();
    return _sink.digest.toString();
  }

  Future<String> hashFile() async {
    final f = file!;
    await for (final chunk in f.openRead()) {
      _hash.add(chunk);
    }
    return hex;
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? digest;

  @override
  void add(Digest data) => digest = data;

  @override
  void close() {}
}
