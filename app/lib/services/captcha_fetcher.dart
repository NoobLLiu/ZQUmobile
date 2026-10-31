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

  /// 取一张新的验证码 JPEG。
  static Future<Uint8List> fetch() async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
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
      await for (final chunk in res) {
        builder.add(chunk);
      }
      final bytes = builder.toBytes();
      if (bytes.isEmpty) throw const HttpException('验证码图片为空');
      return bytes;
    } finally {
      client.close(force: true);
    }
  }
}
