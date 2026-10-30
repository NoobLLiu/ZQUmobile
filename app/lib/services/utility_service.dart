/// 完美校园宿舍水电费查询服务。
///
/// 接口逻辑参考 astrbot_plugin_perfect_campus_zqu_query 插件：
/// POST https://xqh5.17wanxiao.com/smartWaterAndElectricityService/SWAEServlet，
/// 以学号为账号查询绑定房间的水电剩余量（businesstype：0=电、1=水）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/utility.dart';

/// 水电查询异常（message 可直接展示给用户）。
class UtilityException implements Exception {
  UtilityException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 完美校园水电查询客户端。
class UtilityService {
  UtilityService._();

  /// 肇庆学院在完美校园的学校 ID（customercode）。
  static const String _schoolId = '834';

  static const String _baseUrl =
      'https://xqh5.17wanxiao.com/smartWaterAndElectricityService/SWAEServlet';

  /// 查询学号绑定的所有房间水电余额。
  static Future<List<UtilityRoom>> fetchRooms(String studentId) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.postUrl(Uri.parse(_baseUrl));
      request.headers.contentType = ContentType(
        'application',
        'x-www-form-urlencoded',
      );
      final param = jsonEncode({'cmd': 'getbindroom', 'account': studentId});
      final payload =
          'param=${Uri.encodeComponent(param)}'
          '&customercode=$_schoolId&method=getbindroom';
      final bytes = utf8.encode(payload);
      request.contentLength = bytes.length;
      request.add(bytes);

      final response = await request.close().timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw UtilityException('连接超时，请稍后重试'),
      );
      if (response.statusCode != HttpStatus.ok) {
        throw UtilityException('服务器返回 ${response.statusCode}');
      }
      final text = await response
          .transform(utf8.decoder)
          .join()
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw UtilityException('读取数据超时，请稍后重试'),
          );
      return parseRooms(text);
    } on SocketException {
      throw UtilityException('网络连接失败，请检查网络后重试');
    } on TimeoutException {
      throw UtilityException('连接超时，请稍后重试');
    } finally {
      client.close();
    }
  }

  /// 解析接口返回的 JSON 文本。
  ///
  /// 返回体 body 可能是 JSON 字符串或对象；房间列表在 body.roomlist，
  /// 无 roomlist 时视为单房间（body 本身即房间）。
  static List<UtilityRoom> parseRooms(String rawJson) {
    dynamic data;
    try {
      data = jsonDecode(rawJson);
    } catch (_) {
      throw UtilityException('返回数据解析失败');
    }
    if (data is! Map) throw UtilityException('返回数据格式异常');

    dynamic roomBody = data['body'];
    if (roomBody is String) {
      try {
        roomBody = roomBody.isEmpty ? null : jsonDecode(roomBody);
      } catch (_) {
        roomBody = null;
      }
    }

    List rooms;
    if (roomBody is Map && roomBody['roomlist'] is List) {
      rooms = roomBody['roomlist'] as List;
    } else if (roomBody is Map) {
      rooms = [roomBody];
    } else {
      throw UtilityException('该学号未绑定宿舍房间');
    }

    final result = <UtilityRoom>[];
    for (final item in rooms) {
      if (item is! Map) continue;
      double electricity = 0;
      double water = 0;
      final detail = item['detaillist'];
      if (detail is List) {
        for (final entry in detail) {
          if (entry is! Map) continue;
          final odd = double.tryParse(entry['odd']?.toString() ?? '') ?? 0;
          switch (entry['businesstype']?.toString()) {
            case '0':
              electricity = odd;
            case '1':
              water = odd;
          }
        }
      }
      final name = item['roomfullname']?.toString() ?? '';
      result.add(
        UtilityRoom(
          roomName: name.isEmpty ? '未命名房间' : name,
          electricity: electricity,
          water: water,
        ),
      );
    }
    if (result.isEmpty) throw UtilityException('该学号未绑定宿舍房间');
    return result;
  }
}
