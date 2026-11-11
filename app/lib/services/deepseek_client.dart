/// OpenAI 兼容格式的流式对话客户端。
///
/// 使用用户在「模型来源」里自己配置的服务
/// （endpoint / Key / 模型名都来自配置，请求体格式不变）。
///
/// 用 `HttpClient` 直接读 SSE，不引第三方 HTTP 库，理由有二：
/// 1. `dart:io` 自带，配 `HttpClient.close(force: true)` 就能真的中断请求；
/// 2. 少一个依赖，CI 上少一次解算风险。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/ai_source.dart';

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

/// 一次请求的总时限：超过就中断，避免界面无限转圈。
const Duration _kOverallTimeout = Duration(seconds: 150);

/// 连接测试的时限，比正式转写短，别让用户干等。
const Duration _kTestTimeout = Duration(seconds: 30);

/// OpenAI 兼容的流式对话。
class DeepSeekClient {
  DeepSeekClient({
    required this._apiKey,
    required this._endpoint,
    this._sendThinkingParam = false,
    Duration? connectTimeout,
  }) : _connectTimeout = connectTimeout ?? const Duration(seconds: 20);

  /// 按当前「模型来源」配置构造客户端。
  factory DeepSeekClient.fromConfig(
    AiSourceConfig config, {
    Duration? connectTimeout,
  }) =>
      DeepSeekClient(
        apiKey: config.effectiveApiKey,
        endpoint: config.chatUrl,
        sendThinkingParam: config.supportsThinking,
        connectTimeout: connectTimeout,
      );

  final String _apiKey;
  final String _endpoint;

  /// 只有 DeepSeek 官方认识 `thinking` 字段，其它服务一律不发。
  final bool _sendThinkingParam;
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

  /// 组装请求体。测试连接和正式转写共用，保证测的就是真正会发的格式。
  Map<String, dynamic> _buildPayload({
    required String model,
    required String systemPrompt,
    required String userMessage,
    required bool stream,
    required int maxTokens,
    bool deepThinking = false,
  }) =>
      <String, dynamic>{
        'model': model,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userMessage},
        ],
        'stream': stream,
        'max_tokens': maxTokens,
        if (shouldSendThinking(_sendThinkingParam, deepThinking))
          'thinking': {'type': 'disabled'},
      };

  void _setHeaders(HttpClientRequest request) {
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_apiKey');
    request.headers
        .set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8');
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
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

    final payload = _buildPayload(
      model: model,
      systemPrompt: systemPrompt,
      userMessage: userMessage,
      deepThinking: deepThinking,
      stream: true,
      maxTokens: 4096,
    );

    final stopwatch = Stopwatch()..start();

    try {
      final HttpClientResponse response;
      try {
        final request = await client.postUrl(Uri.parse(_endpoint));
        _setHeaders(request);
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

  /// 测试连接：发一条最短的非流式请求，能拿到 200 就算通。
  ///
  /// 用的是和保存后完全一样的 endpoint / Key / 模型 / 请求体格式，
  /// 所以测试通过基本等于转写能用。返回模型回复的一句话，供界面展示。
  Future<String> testConnection({required String model}) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      return await _doTest(client, model).timeout(
        _kTestTimeout,
        onTimeout: () => throw AiException('连接测试超时，请检查地址与网络。'),
      );
    } on AiException {
      rethrow;
    } on SocketException catch (e) {
      throw AiException(_describeSocketError(e));
    } on HttpException catch (e) {
      throw AiException('网络连接中断：${e.message}');
    } catch (e) {
      throw AiException('连接测试失败：$e');
    } finally {
      client.close(force: true);
    }
  }

  Future<String> _doTest(HttpClient client, String model) async {
    final payload = _buildPayload(
      model: model,
      systemPrompt: '你是一个连通性测试助手。',
      userMessage: '只回复两个字：正常',
      stream: false,
      maxTokens: 16,
    );
    final request = await client.postUrl(Uri.parse(_endpoint));
    _setHeaders(request);
    request.add(utf8.encode(jsonEncode(payload)));
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      final body = await _readAll(response);
      throw AiException(
        _describeHttpError(response.statusCode, body),
        statusCode: response.statusCode,
      );
    }
    return _extractTestReply(await _readAll(response));
  }

  static Future<String> _readAll(HttpClientResponse response) async {
    try {
      return await response.transform(utf8.decoder).join();
    } catch (_) {
      return '';
    }
  }

  static String _extractTestReply(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is Map) {
          final msg = (error['message'] ?? '').toString();
          throw AiException(msg.isEmpty ? 'AI 服务返回了错误' : msg);
        }
        final choices = decoded['choices'];
        if (choices is List && choices.isNotEmpty && choices.first is Map) {
          final first = choices.first as Map;
          final message = first['message'];
          if (message is Map && message['content'] is String) {
            final text = (message['content'] as String).trim();
            if (text.isNotEmpty) return text;
          }
          final text = first['text'];
          if (text is String && text.trim().isNotEmpty) return text.trim();
        }
      }
    } on AiException {
      rethrow;
    } on FormatException {
      // 返回体不是 JSON：状态码已是 200，仍算连通
    }
    return '（接口已连通，未解析到回复文本）';
  }

  static String _describeSocketError(SocketException e) {
    final text = e.message;
    if (text.contains('timed out') || e.osError?.message.contains('timed out') == true) {
      return '连接模型服务超时，请检查网络后重试。';
    }
    return '网络不可用，请检查网络后重试。';
  }

  static String _describeHttpError(int status, String body) {
    final detail = _extractErrorMessage(body);
    switch (status) {
      case 400:
        return '请求参数有误${detail.isEmpty ? '' : '：$detail'}';
      case 401:
        return 'API Key 无效或已过期，请检查后重试。';
      case 402:
        return '账户余额不足，暂时无法使用。';
      case 404:
        return '找不到接口，请检查 Base URL 是否填对（需 OpenAI 兼容地址）。';
      case 422:
        return '请求内容不被接受${detail.isEmpty ? '' : '：$detail'}';
      case 429:
        return '请求太频繁了，请稍后再试。';
      default:
        if (status >= 500) return '模型服务暂时不可用，请稍后再试。';
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
