/// 应用内更新的纯逻辑测试：version.json 解析、版本对比、ABI 选包。
///
/// 网络与平台通道不在单测范围（check/download 依赖 HttpClient 与
/// MethodChannel，真机联调验证）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:zhangshang_yanyuan/services/update_service.dart';

void main() {
  // 与 CI 生成的 version.json 同构（Gitee 同步后 url 指向 Gitee）。
  const sampleJson = '''
{
  "schemaVersion": 1,
  "package": "com.nooblliu.zhangshang_yanyuan",
  "version": "1.15.4",
  "versionCode": 32,
  "buildNumber": 32,
  "fullVersion": "1.15.4+32",
  "tag": "latest",
  "gitSha": "abcdef1234567890",
  "buildTime": "2026-11-11T04:00Z",
  "releaseNotes": "由 CI 自动构建，每次提交更新。",
  "mirror": "gitee",
  "releasePage": "https://gitee.com/NoobLLiu/ZQUmobile/releases/tag/latest",
  "assets": [
    {
      "abi": "arm64-v8a",
      "name": "zhangshangyanyuan-1.15.4-arm64-v8a.apk",
      "size": 19123456,
      "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      "url": "https://gitee.com/NoobLLiu/ZQUmobile/releases/download/latest/zhangshangyanyuan-1.15.4-arm64-v8a.apk",
      "upstreamUrl": "https://github.com/NoobLLiu/ZQUmobile/releases/download/latest/zhangshangyanyuan-1.15.4-arm64-v8a.apk"
    },
    {
      "abi": "armeabi-v7a",
      "name": "zhangshangyanyuan-1.15.4-armeabi-v7a.apk",
      "size": 18111222,
      "sha256": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      "url": "https://gitee.com/NoobLLiu/ZQUmobile/releases/download/latest/zhangshangyanyuan-1.15.4-armeabi-v7a.apk"
    },
    {
      "abi": "x86_64",
      "name": "zhangshangyanyuan-1.15.4-x86_64.apk",
      "size": 20000000,
      "sha256": "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
      "url": "https://gitee.com/NoobLLiu/ZQUmobile/releases/download/latest/zhangshangyanyuan-1.15.4-x86_64.apk"
    }
  ]
}
''';

  late UpdateMeta meta;

  setUp(() {
    meta = UpdateMeta.parse(sampleJson);
  });

  group('UpdateMeta.parse', () {
    test('解析核心字段', () {
      expect(meta.version, '1.15.4');
      expect(meta.versionCode, 32);
      expect(meta.fullVersion, '1.15.4+32');
      expect(meta.releaseNotes, isNotEmpty);
      expect(meta.assets, hasLength(3));
    });

    test('资产字段完整', () {
      final a = meta.assets.first;
      expect(a.abi, 'arm64-v8a');
      expect(a.name, 'zhangshangyanyuan-1.15.4-arm64-v8a.apk');
      expect(a.size, 19123456);
      expect(a.sha256, hasLength(64));
      expect(a.url, startsWith('https://gitee.com/'));
    });

    test('缺 releaseNotes / assets 时有兜底', () {
      final m = UpdateMeta.parse('{"version":"1.0.0","versionCode":1}');
      expect(m.releaseNotes, '');
      expect(m.assets, isEmpty);
    });

    test('非法 JSON 抛 FormatException', () {
      expect(() => UpdateMeta.parse('not-json'), throwsFormatException);
    });
  });

  group('isNewerThan', () {
    test('远端更新 → true', () {
      expect(meta.isNewerThan(31), isTrue);
    });
    test('同版本 → false', () {
      expect(meta.isNewerThan(32), isFalse);
    });
    test('本地更新（回滚包）→ false', () {
      expect(meta.isNewerThan(33), isFalse);
    });
    test('本地版本号缺失（按 0）→ true', () {
      expect(meta.isNewerThan(0), isTrue);
    });
  });

  group('pickAsset', () {
    test('优先 arm64-v8a', () {
      final a = UpdateService.pickAsset(meta.assets, ['arm64-v8a']);
      expect(a?.abi, 'arm64-v8a');
    });

    test('v7a 设备拿到 armeabi-v7a', () {
      final a = UpdateService.pickAsset(meta.assets, ['armeabi-v7a', 'arm64-v8a']);
      expect(a?.abi, 'armeabi-v7a');
    });

    test('deviceAbis 兜底顺序：首选 ABI 没有时退到 arm64', () {
      final a = UpdateService.pickAsset(meta.assets, ['riscv64', 'arm64-v8a']);
      expect(a?.abi, 'arm64-v8a');
    });

    test('清单为空 → null', () {
      expect(UpdateService.pickAsset([], ['arm64-v8a']), isNull);
    });
  });
}
