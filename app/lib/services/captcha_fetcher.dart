/// 验证码图片抓取。
///
/// `/yzm` 是公开接口（实测无 cookie 也能取图），训练页直接抓图即可，
/// 不需要先登录、也不需要经过 WebView。
library;

import 'dart:io';
import 'dart:typed_data';

/// 抓取教务系统的验证码图片。
class CaptchaFetcher {
  CaptchaFetcher._();

  static const String baseUrl = 'https://jwgl.zqu.edu.cn/yzm';

  /// 整体超时：连接超时管不到读体卡住的情况。
  static const Duration timeout = Duration(seconds: 20);
  static const Duration connectTimeout = Duration(seconds: 15);

  /// 取一张新的验证码 JPEG。
  static Future<Uint8List> fetch() async {
    final client = HttpClient()..connectionTimeout = connectTimeout;
    try {
      final uri = Uri.parse(
        '$baseUrl?d=${DateTime.now().millisecondsSinceEpoch}',
      );
      final req = await client.getUrl(uri);
      req.headers.set(HttpHeaders.userAgentHeader, 'Mozilla/5.0');
      final res = await req.close();
      if (res.statusCode != 200) {
        throw HttpException('HTTP ${res.statusCode}');
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in res.timeout(timeout)) {
        builder.add(chunk);
      }
      final bytes = builder.toBytes();
      if (bytes.isEmpty) throw const HttpException('验证码图片为空');
      // 网关未放行时会回一张 HTML 登录页，别把它当图片
      if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) {
        throw const HttpException('返回内容不是 JPEG（可能是网关拦截页）');
      }
      return bytes;
    } finally {
      client.close(force: true);
    }
  }
}
