/// DeepSeek 流式对话客户端。
///
/// 只做一件事：把一段对话发出去，把模型逐段吐出来的文本变成 `Stream<String>`。
/// 用 `HttpClient` 直接读 SSE，不引第三方 HTTP 库，理由有二：
/// 1. `dart:io` 自带，配 `HttpClient.close(force: true)` 就能真的中断请求；
/// 2. 少一个依赖，CI 上少一次解算风险。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/ai_credentials.dart';

/// 一次 AI 调用失败。
class AiException implements Exception {
  AiException(this.message, {this.statusCode});

  /// 可以直接展示给用户的中文说明。
  final String message;

  /// HTTP 状态码（网络错误时为 null）。
  final int? statusCode;

  @override
  String toString() => message;
}

/// 可选的模型。
class AiModelOption {
  const AiModelOption(this.id, this.label, this.hint);

  final String id;
  final String label;
  final String hint;
}

/// App 里开放的模型：够用就好，不把整个目录摊给用户。
const List<AiModelOption> kAiModels = [
  AiModelOption('deepseek-flash', 'DeepSeek V4.1 Flash', '默认，速度快，日常通知够用'),
  AiModelOption('deepseek-v4-pro', 'DeepSeek V4 Pro', '更稳，长通知 / 复杂补充要求时用'),
];

/// 默认模型。
const String kDefaultModelId = 'deepseek-flash';

/// 一次请求的总时限：超过就中断，避免界面无限转圈。
const Duration _kOverallTimeout = Duration(seconds: 150);

/// DeepSeek 流式对话。
class DeepSeekClient {
  DeepSeekClient({String? apiKey, Duration? connectTimeout})
      : _apiKey = apiKey ?? deepSeekApiKey(),
        _connectTimeout = connectTimeout ?? const Duration(seconds: 20);

  final String _apiKey;
  final Duration _connectTimeout;

  HttpClient? _client;
  bool _cancelled = false;

  /// 用户主动中断（不算错误）。
  bool get isCancelled => _cancelled;

  /// 中断当前请求。已在流里的调用方应把后续异常当成「用户取消」。
  void cancel() {
    _cancelled = true;
    _client?.close(force: true);
  }

  /// 发起一次流式对话，逐段返回正文增量。
  ///
  /// [deepThinking] 打开时模型会先「想」再答，更慢也更贵；
  /// 通知转写这种有明确规则的改写任务关掉它更划算。
  Stream<String> streamChat({
    required String model,
    required String systemPrompt,
    required String userMessage,
    bool deepThinking = false,
  }) async* {
    _cancelled = false;

    final client = HttpClient()..connectionTimeout = _connectTimeout;
    _client = client;

    final payload = <String, dynamic>{
      'model': model,
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': userMessage},
      ],
      'stream': true,
      'max_tokens': 4096,
      if (!deepThinking) 'thinking': {'type': 'disabled'},
    };

    final stopwatch = Stopwatch()..start();

    try {
      final HttpClientResponse response;
      try {
        final request = await client.postUrl(Uri.parse(kDeepSeekEndpoint));
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_apiKey');
        request.headers
            .set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8');
        request.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
        request.add(utf8.encode(jsonEncode(payload)));
        response = await request.close();
      } on SocketException catch (e) {
        throw AiException(_describeSocketError(e));
      }

      if (response.statusCode != HttpStatus.ok) {
        final body = await _readAll(response);
        throw AiException(
          _describeHttpError(response.statusCode, body),
          statusCode: response.statusCode,
        );
      }

      // SSE：一行一个 `data: {...}`，以 `data: [DONE]` 收尾。
      // 注意行可能被 TCP 拆开，交给 LineSplitter 攒齐再解析。
      await for (final line
          in response.transform(utf8.decoder).transform(const LineSplitter())) {
        if (stopwatch.elapsed > _kOverallTimeout) {
          throw AiException('等待太久了，已中断。请检查网络后重试。');
        }
        final trimmed = line.trim();
        if (trimmed.isEmpty || !trimmed.startsWith('data:')) continue;
        final data = trimmed.substring(5).trim();
        if (data.isEmpty) continue;
        if (data == '[DONE]') break;

        Map<dynamic, dynamic>? decoded;
        try {
          final parsed = jsonDecode(data);
          if (parsed is Map) decoded = parsed;
        } on FormatException {
          continue; // 半截包，跳过，不影响整段输出
        }
        if (decoded == null) continue;

        final error = decoded['error'];
        if (error is Map) {
          final msg = (error['message'] ?? '').toString();
          throw AiException(msg.isEmpty ? 'AI 服务返回了错误，请稍后重试' : msg);
        }

        final choices = decoded['choices'];
        if (choices is! List || choices.isEmpty) continue;
        final first = choices.first;
        if (first is! Map) continue;
        final delta = first['delta'];
        if (delta is! Map) continue;
        final content = delta['content'];
        if (content is String && content.isNotEmpty) yield content;
      }
    } catch (e) {
      if (_cancelled) return;
      if (e is AiException) rethrow;
      if (e is HttpException) throw AiException('网络连接中断：${e.message}');
      if (e is SocketException) throw AiException(_describeSocketError(e));
      if (e is TimeoutException) throw AiException('AI 响应超时，请稍后再试。');
      throw AiException('AI 调用失败：$e');
    } finally {
      client.close(force: true);
      if (identical(_client, client)) _client = null;
    }
  }

  static Future<String> _readAll(HttpClientResponse response) async {
    try {
      return await response.transform(utf8.decoder).join();
    } catch (_) {
      return '';
    }
  }

  static String _describeSocketError(SocketException e) {
    final text = e.message;
    if (text.contains('timed out') || e.osError?.message.contains('timed out') == true) {
      return '连接 DeepSeek 超时，请检查网络后重试。';
    }
    return '网络不可用，请检查网络后重试。';
  }

  static String _describeHttpError(int status, String body) {
    final detail = _extractErrorMessage(body);
    switch (status) {
      case 400:
        return '请求参数有误${detail.isEmpty ? '' : '：$detail'}';
      case 401:
        return 'AI 凭据无效或已过期，暂时无法使用。';
      case 402:
        return 'AI 账户余额不足，暂时无法使用。';
      case 422:
        return '请求内容不被接受${detail.isEmpty ? '' : '：$detail'}';
      case 429:
        return '请求太频繁了，请稍后再试。';
      default:
        if (status >= 500) return 'AI 服务暂时不可用，请稍后再试。';
        return 'AI 调用失败（HTTP $status）${detail.isEmpty ? '' : '：$detail'}';
    }
  }

  static String _extractErrorMessage(String body) {
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
