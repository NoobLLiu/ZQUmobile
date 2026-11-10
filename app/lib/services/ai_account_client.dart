/// 模型列表与账户余额查询。
///
/// 只做两件事：GET 一个地址拿到 JSON，再交给纯函数解析。
/// 解析函数单独暴露出来，方便不联网直接测；网络与状态码错误统一转成
/// [AiException] 的中文说明，界面可以直接展示。
///
/// 各家能力差异（2026-11 查证）：
/// - 模型列表：绝大多数 OpenAI 兼容厂商都有 `GET /models`，统一用这个；
/// - 余额：只有 DeepSeek / Kimi / 硅基流动 / OpenRouter 提供公开接口，
///   其余厂商要去控制台看，界面上会明确说明。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/ai_source.dart';
import 'deepseek_client.dart' show AiException;

/// 一次余额查询的结果。
class AiBalanceResult {
  const AiBalanceResult({required this.text, this.sufficient});

  /// 展示用的一句话，例如「¥12.34，其中赠金 ¥2.00」。
  final String text;

  /// 官方是否明确说额度够用；null 表示接口没给这个信息。
  final bool? sufficient;
}

/// 从 `/models` 的返回里取模型 id。
///
/// 标准格式是 `{"data":[{"id":"..."}]}`；少数网关用 `models` 字段或直接给字符串。
List<String> parseModelIds(Map<String, dynamic> json) {
  final raw = json['data'] ?? json['models'];
  if (raw is! List) return const [];
  final ids = <String>{};
  for (final item in raw) {
    if (item is Map) {
      final id = item['id'] ?? item['model'] ?? item['name'];
      if (id is String && id.trim().isNotEmpty) ids.add(id.trim());
    } else if (item is String && item.trim().isNotEmpty) {
      ids.add(item.trim());
    }
  }
  final list = ids.toList()..sort();
  return list;
}

/// 把各家余额返回体格式化成一句话；解析不出来返回 null。
String? formatBalance(AiBalanceFormat format, Map<String, dynamic> json) {
  switch (format) {
    case AiBalanceFormat.none:
      return null;
    case AiBalanceFormat.deepseek:
      return _formatDeepSeek(json);
    case AiBalanceFormat.moonshot:
      return _formatMoonshot(json);
    case AiBalanceFormat.siliconflow:
      return _formatSiliconflow(json);
    case AiBalanceFormat.openrouter:
      return _formatOpenRouter(json);
  }
}

/// DeepSeek：`balance_infos` 里可能同时有 CNY 和 USD，优先显示人民币。
String? _formatDeepSeek(Map<String, dynamic> json) {
  final infos = json['balance_infos'];
  if (infos is! List || infos.isEmpty) return null;
  Map? chosen;
  for (final item in infos) {
    if (item is! Map) continue;
    chosen ??= item;
    if (item['currency'] == 'CNY') {
      chosen = item;
      break;
    }
  }
  if (chosen == null) return null;
  final total = _asNum(chosen['total_balance']);
  if (total == null) return null;
  final symbol = chosen['currency'] == 'USD' ? r'$' : '¥';
  final parts = <String>['$symbol${total.toStringAsFixed(2)}'];
  final granted = _asNum(chosen['granted_balance']);
  if (granted != null && granted > 0) {
    parts.add('其中赠金 $symbol${granted.toStringAsFixed(2)}');
  }
  if (json['is_available'] == false) parts.add('额度不足，无法调用');
  return parts.join('，');
}

/// Kimi：`data.available_balance`（元），含代金券。
String? _formatMoonshot(Map<String, dynamic> json) {
  final data = json['data'];
  if (data is! Map) return null;
  final available = _asNum(data['available_balance']);
  if (available == null) return null;
  final parts = <String>['¥${available.toStringAsFixed(2)}'];
  final voucher = _asNum(data['voucher_balance']);
  if (voucher != null && voucher > 0) {
    parts.add('含代金券 ¥${voucher.toStringAsFixed(2)}');
  }
  if (available <= 0) parts.add('余额不足，无法调用');
  return parts.join('，');
}

/// 硅基流动：`data.totalBalance`（元）。
String? _formatSiliconflow(Map<String, dynamic> json) {
  final data = json['data'];
  if (data is! Map) return null;
  final total = _asNum(data['totalBalance']) ?? _asNum(data['balance']);
  if (total == null) return null;
  return '¥${total.toStringAsFixed(2)}';
}

/// OpenRouter：`total_credits` 是总额度，`total_usage` 是已用，差值即剩余。
String? _formatOpenRouter(Map<String, dynamic> json) {
  final data = json['data'];
  if (data is! Map) return null;
  final credits = _asNum(data['total_credits']);
  if (credits == null) return null;
  final used = _asNum(data['total_usage']) ?? 0;
  final remaining = credits - used;
  return '剩余 \$${remaining.toStringAsFixed(2)}'
      '（已用 \$${used.toStringAsFixed(2)} / 共 \$${credits.toStringAsFixed(2)}）';
}

num? _asNum(Object? value) {
  if (value is num) return value;
  if (value is String) return num.tryParse(value.trim());
  return null;
}

/// 查询客户端：一次构造查一种来源。
class AiAccountClient {
  AiAccountClient({
    required this.apiKey,
    required this.modelsUrl,
    this.balanceUrl,
    this.balanceFormat = AiBalanceFormat.none,
    Duration? timeout,
  }) : _timeout = timeout ?? const Duration(seconds: 15);

  final String apiKey;
  final String modelsUrl;
  final String? balanceUrl;
  final AiBalanceFormat balanceFormat;
  final Duration _timeout;

  /// 拉取可用模型列表。
  Future<List<String>> fetchModels() async {
    if (modelsUrl.trim().isEmpty) {
      throw AiException('还没有可用的服务地址，请先填写 Base URL。');
    }
    final json = await _getJson(modelsUrl);
    final ids = parseModelIds(json);
    if (ids.isEmpty) {
      throw AiException('接口通了，但没解析到模型列表（可能需要 Key 权限）。');
    }
    return ids;
  }

  /// 查询余额。
  Future<AiBalanceResult> fetchBalance() async {
    if (balanceUrl == null || balanceFormat == AiBalanceFormat.none) {
      throw AiException('该厂商没有提供公开的余额接口，请到官网控制台查看。');
    }
    final json = await _getJson(balanceUrl!);
    final text = formatBalance(balanceFormat, json);
    if (text == null) {
      throw AiException('余额接口返回了未识别的格式。');
    }
    final sufficient =
        json['is_available'] is bool ? json['is_available'] as bool : null;
    return AiBalanceResult(text: text, sufficient: sufficient);
  }

  Future<Map<String, dynamic>> _getJson(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw AiException('地址格式不对：$url');
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(_timeout);
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != HttpStatus.ok) {
        throw AiException(
          _describeHttpError(response.statusCode, body),
          statusCode: response.statusCode,
        );
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw AiException('接口返回的不是 JSON 对象。');
      }
      return decoded;
    } on AiException {
      rethrow;
    } on SocketException catch (e) {
      throw AiException(_describeSocketError(e));
    } on TimeoutException {
      throw AiException('查询超时，请检查网络后重试。');
    } on FormatException {
      throw AiException('接口返回的内容不是合法 JSON。');
    } on HttpException catch (e) {
      throw AiException('网络连接中断：${e.message}');
    } finally {
      client.close(force: true);
    }
  }

  static String _describeHttpError(int status, String body) {
    final detail = _extractMessage(body);
    switch (status) {
      case 401:
        return 'API Key 无效或已过期，查不了。';
      case 403:
        return '这个 Key 没有查询权限${detail.isEmpty ? '（可能需要 management key）' : '：$detail'}';
      case 404:
        return '该厂商没有这个查询接口（404）。';
      case 429:
        return '请求太频繁了，请稍后再试。';
      default:
        if (status >= 500) return '厂商服务暂时不可用，请稍后再试。';
        return '查询失败（HTTP $status）${detail.isEmpty ? '' : '：$detail'}';
    }
  }

  static String _describeSocketError(SocketException e) {
    final text = e.message;
    if (text.contains('timed out') ||
        e.osError?.message.contains('timed out') == true) {
      return '连接厂商服务超时，请检查网络。';
    }
    return '网络不可用，请检查网络后重试。';
  }

  static String _extractMessage(String body) {
    if (body.trim().isEmpty) return '';
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is Map) return (error['message'] ?? '').toString();
        if (decoded['message'] is String) return decoded['message'] as String;
      }
    } catch (_) {
      // 不是 JSON 就当没有详情
    }
    return '';
  }
}
