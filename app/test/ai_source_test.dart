/// 模型来源配置：URL 规整、预置厂商、配置决策、本地存储与页面版式。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zhangshang_yanyuan/core/ai_credentials.dart';
import 'package:zhangshang_yanyuan/models/ai_source.dart';
import 'package:zhangshang_yanyuan/pages/ai_source_page.dart';
import 'package:zhangshang_yanyuan/services/ai_account_client.dart';
import 'package:zhangshang_yanyuan/services/ai_source_repository.dart';

void main() {
  group('normalizeChatUrl', () {
    test('裸域名自动补 /chat/completions', () {
      expect(normalizeChatUrl('https://api.deepseek.com'),
          'https://api.deepseek.com/chat/completions');
    });

    test('带版本段的地址不重复拼 /v1', () {
      expect(
        normalizeChatUrl('https://dashscope.aliyuncs.com/compatible-mode/v1'),
        'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions',
      );
      expect(
        normalizeChatUrl('https://open.bigmodel.cn/api/paas/v4/'),
        'https://open.bigmodel.cn/api/paas/v4/chat/completions',
      );
    });

    test('用户贴完整地址或多余斜杠都能用', () {
      expect(
        normalizeChatUrl('  https://api.moonshot.cn/v1/chat/completions/  '),
        'https://api.moonshot.cn/v1/chat/completions',
      );
    });

    test('空串原样返回空串', () {
      expect(normalizeChatUrl('   '), '');
    });
  });

  group('预置厂商清单', () {
    test('都有 https 地址、推荐模型名和 Key 官网', () {
      expect(kAiProviderPresets.length, greaterThanOrEqualTo(8));
      for (final p in kAiProviderPresets) {
        expect(p.baseUrl.startsWith('https://'), isTrue, reason: p.name);
        expect(p.baseUrl.contains('/chat/completions'), isFalse, reason: p.name);
        expect(p.model.trim(), isNotEmpty, reason: p.name);
        expect(p.keySite.trim(), isNotEmpty, reason: p.name);
      }
    });

    test('最后一项由界面单独追加「自定义」，清单里不重复', () {
      expect(kAiProviderPresets.any((p) => p.id == kCustomProviderId), isFalse);
      expect(findAiProvider(kCustomProviderId), isNull);
    });

    test('按 id 能找回厂商，DeepSeek 排在第一个', () {
      expect(kAiProviderPresets.first.id, 'deepseek');
      expect(findAiProvider('zhipu')?.baseUrl,
          'https://open.bigmodel.cn/api/paas/v4');
      expect(findAiProvider('不存在的厂商'), isNull);
    });
  });

  group('AiSourceConfig 决策', () {
    test('默认就是作者提供的免费模型', () {
      const config = AiSourceConfig();
      expect(config.isFree, isTrue);
      expect(config.chatUrl, kDeepSeekEndpoint);
      expect(config.effectiveApiKey, deepSeekApiKey());
      expect(config.effectiveModel, kAiModels.first.id);
      expect(config.supportsThinking, isTrue);
    });

    test('免费来源可切到第二个模型，下标越界会夹住', () {
      expect(
        const AiSourceConfig(freeModelIndex: 1).effectiveModel,
        kAiModels[1].id,
      );
      expect(
        const AiSourceConfig(freeModelIndex: 99).effectiveModel,
        kAiModels.last.id,
      );
    });

    test('自行配置用自己的 Key / 地址 / 模型，且不带 thinking 字段', () {
      const config = AiSourceConfig(
        mode: AiSourceMode.custom,
        providerId: 'dashscope',
        baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
        apiKey: 'sk-my-own-key',
        model: 'qwen-plus',
      );
      expect(config.isFree, isFalse);
      expect(config.providerName, '阿里云百炼（通义千问）');
      expect(config.chatUrl,
          'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions');
      expect(config.effectiveApiKey, 'sk-my-own-key');
      expect(config.effectiveModel, 'qwen-plus');
      expect(config.supportsThinking, isFalse);
    });

    test('自定义厂商没有预置名字', () {
      expect(
        const AiSourceConfig(providerId: kCustomProviderId).providerName,
        '自定义服务',
      );
    });

    test('shouldSendThinking 只对内置来源生效，开深度思考时不发', () {
      expect(shouldSendThinking(true, false), isTrue);
      expect(shouldSendThinking(true, true), isFalse);
      expect(shouldSendThinking(false, false), isFalse);
      expect(shouldSendThinking(false, true), isFalse);
    });
  });

  group('自行配置表单校验', () {
    AiSourceConfig build({
      String baseUrl = 'https://api.deepseek.com',
      String apiKey = 'sk-test',
      String model = 'deepseek-chat',
    }) =>
        AiSourceConfig(
          mode: AiSourceMode.custom,
          baseUrl: baseUrl,
          apiKey: apiKey,
          model: model,
        );

    test('三项齐全才通过', () {
      expect(build().validateCustom(), isNull);
    });

    test('逐项给出中文错误', () {
      expect(build(baseUrl: '').validateCustom(), '请填写 Base URL');
      expect(build(baseUrl: 'api.deepseek.com').validateCustom(),
          contains('http://'));
      expect(build(baseUrl: 'https://api deepseek.com').validateCustom(),
          contains('空格'));
      expect(build(apiKey: '  ').validateCustom(), '请填写 API Key');
      expect(build(model: '').validateCustom(), '请填写模型名称');
    });
  });

  group('序列化与存储', () {
    test('JSON 往返保留全部字段', () {
      const config = AiSourceConfig(
        mode: AiSourceMode.custom,
        providerId: 'siliconflow',
        baseUrl: 'https://api.siliconflow.cn/v1',
        apiKey: 'sk-abc',
        model: 'Qwen/Qwen2.5-7B-Instruct',
        freeModelIndex: 1,
      );
      final restored = AiSourceConfig.decode(config.encode());
      expect(restored.mode, AiSourceMode.custom);
      expect(restored.providerId, 'siliconflow');
      expect(restored.apiKey, 'sk-abc');
      expect(restored.model, 'Qwen/Qwen2.5-7B-Instruct');
      expect(restored.freeModelIndex, 1);
    });

    test('损坏数据回退到免费来源', () {
      expect(AiSourceConfig.decode('{坏掉的 json').isFree, isTrue);
      expect(AiSourceConfig.decode(null).isFree, isTrue);
    });

    test('仓库读写与清空', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      expect((await AiSourceRepository.load()).isFree, isTrue);

      const config = AiSourceConfig(
        mode: AiSourceMode.custom,
        providerId: 'moonshot',
        baseUrl: 'https://api.moonshot.cn/v1',
        apiKey: 'sk-kimi',
        model: 'moonshot-v1-8k',
      );
      await AiSourceRepository.save(config);
      final loaded = await AiSourceRepository.load();
      expect(loaded.mode, AiSourceMode.custom);
      expect(loaded.apiKey, 'sk-kimi');

      await AiSourceRepository.clear();
      expect((await AiSourceRepository.load()).isFree, isTrue);
    });
  });

  group('配置页面版式', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    Future<void> pump(WidgetTester tester) async {
      await tester.pumpWidget(
        // autoProbe 关掉：组件测试不能真的去请求厂商接口
        const MaterialApp(home: AiSourcePage(autoProbe: false)),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('免费模式下也有测试连接按钮，不显示自定义表单', (tester) async {
      await pump(tester);

      expect(find.text('配置模型来源'), findsOneWidget);
      expect(find.text('免费模型（作者提供）'), findsOneWidget);
      expect(find.text('自行配置'), findsOneWidget);
      expect(find.text('测试连接'), findsOneWidget);
      expect(find.text('保存配置'), findsOneWidget);
      expect(find.text('模型厂商'), findsNothing);
      expect(find.text('Base URL'), findsNothing);
    });

    testWidgets('切到自行配置会显示厂商下拉与三个输入框，并自动预填', (tester) async {
      await pump(tester);
      await tester.tap(find.text('自行配置'));
      await tester.pumpAndSettle();

      expect(find.text('模型厂商'), findsOneWidget);
      expect(find.text('Base URL'), findsOneWidget);
      expect(find.text('API Key'), findsOneWidget);
      expect(find.text('模型名称'), findsOneWidget);
      expect(find.text('测试连接'), findsOneWidget);

      // 首次切换按当前厂商（DeepSeek 官方）自动填好地址与推荐模型名
      expect(find.text('https://api.deepseek.com'), findsWidgets);
      expect(find.text('deepseek-chat'), findsWidgets);
    });

    testWidgets('保存的自定义配置能回读到页面', (tester) async {
      SharedPreferences.setMockInitialValues({
        AiSourceRepository.prefsKey: const AiSourceConfig(
          mode: AiSourceMode.custom,
          providerId: 'zhipu',
          baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
          apiKey: 'sk-glm',
          model: 'glm-4.6',
        ).encode(),
      });
      await pump(tester);

      expect(find.text('https://open.bigmodel.cn/api/paas/v4'), findsOneWidget);
      expect(find.text('glm-4.6'), findsOneWidget);
      expect(find.text('模型厂商'), findsOneWidget);
    });
  });

  group('模型列表解析', () {
    test('标准 OpenAI 格式按 id 排序去重', () {
      expect(
        parseModelIds({
          'data': [
            {'id': 'qwen-plus'},
            {'id': 'deepseek-chat'},
            {'id': 'qwen-plus'},
          ],
        }),
        ['deepseek-chat', 'qwen-plus'],
      );
    });

    test('兼容 models 字段与纯字符串数组', () {
      expect(parseModelIds({'models': ['b', 'a']}), ['a', 'b']);
      expect(parseModelIds({'data': ['z', 'y']}), ['y', 'z']);
    });

    test('没有列表或格式不对时返回空', () {
      expect(parseModelIds({}), isEmpty);
      expect(parseModelIds({'data': 'oops'}), isEmpty);
      expect(parseModelIds({'data': []}), isEmpty);
    });
  });

  group('余额解析', () {
    test('DeepSeek 优先人民币，并带上赠金', () {
      final text = formatBalance(AiBalanceFormat.deepseek, {
        'is_available': true,
        'balance_infos': [
          {'currency': 'USD', 'total_balance': '1.00', 'granted_balance': '0.00'},
          {'currency': 'CNY', 'total_balance': '12.34', 'granted_balance': '2.00'},
        ],
      });
      expect(text, '¥12.34，其中赠金 ¥2.00');
    });

    test('DeepSeek 余额不足会追加提示', () {
      final text = formatBalance(AiBalanceFormat.deepseek, {
        'is_available': false,
        'balance_infos': [
          {'currency': 'CNY', 'total_balance': '0', 'granted_balance': '0'},
        ],
      });
      expect(text, contains('额度不足'));
    });

    test('DeepSeek 美元账户用 \$ 符号', () {
      final text = formatBalance(AiBalanceFormat.deepseek, {
        'balance_infos': [
          {'currency': 'USD', 'total_balance': '5.5', 'granted_balance': '0'},
        ],
      });
      expect(text, r'$5.50');
    });

    test('Kimi 用 available_balance，并注明代金券', () {
      final text = formatBalance(AiBalanceFormat.moonshot, {
        'status': true,
        'data': {
          'available_balance': 49.58894,
          'voucher_balance': 46.58893,
          'cash_balance': 3.00001,
        },
      });
      expect(text, contains('¥49.59'));
      expect(text, contains('代金券'));
    });

    test('硅基流动兼容字符串数字', () {
      expect(
        formatBalance(AiBalanceFormat.siliconflow, {
          'data': {'totalBalance': '8.80'},
        }),
        '¥8.80',
      );
    });

    test('OpenRouter 用总额度减已用算剩余', () {
      final text = formatBalance(AiBalanceFormat.openrouter, {
        'data': {'total_credits': 100.5, 'total_usage': 25.75},
      });
      expect(text, contains(r'剩余 $74.75'));
      expect(text, contains(r'已用 $25.75'));
    });

    test('字段缺失返回 null，none 永远不支持', () {
      expect(formatBalance(AiBalanceFormat.deepseek, {}), isNull);
      expect(formatBalance(AiBalanceFormat.moonshot, {'data': {}}), isNull);
      expect(formatBalance(AiBalanceFormat.siliconflow, {'data': {}}), isNull);
      expect(formatBalance(AiBalanceFormat.none, {'data': {}}), isNull);
    });
  });

  group('查询能力派生', () {
    test('免费来源自动指向 DeepSeek 的模型与余额地址', () {
      const config = AiSourceConfig();
      expect(config.modelsUrl, 'https://api.deepseek.com/models');
      expect(config.balanceUrl, 'https://api.deepseek.com/user/balance');
      expect(config.balanceFormat, AiBalanceFormat.deepseek);
      expect(config.supportsBalance, isTrue);
    });

    test('自行配置按厂商派生，模型地址跟着 Base URL 走', () {
      const config = AiSourceConfig(
        mode: AiSourceMode.custom,
        providerId: 'moonshot',
        baseUrl: 'https://api.moonshot.cn/v1',
        apiKey: 'sk-kimi',
        model: 'moonshot-v1-8k',
      );
      expect(config.modelsUrl, 'https://api.moonshot.cn/v1/models');
      expect(config.balanceUrl, 'https://api.moonshot.cn/v1/users/me/balance');
      expect(config.supportsBalance, isTrue);
    });

    test('自定义厂商能查模型但没有余额接口', () {
      const config = AiSourceConfig(
        mode: AiSourceMode.custom,
        providerId: kCustomProviderId,
        baseUrl: 'https://example.com/v1',
        apiKey: 'sk-x',
        model: 'x',
      );
      expect(config.modelsUrl, 'https://example.com/v1/models');
      expect(config.balanceUrl, isNull);
      expect(config.supportsBalance, isFalse);
    });

    test('预置厂商里只有四家有公开余额接口', () {
      final withBalance = kAiProviderPresets
          .where((p) => p.supportsBalance)
          .map((p) => p.id)
          .toSet();
      expect(withBalance, {'deepseek', 'moonshot', 'siliconflow', 'openrouter'});
    });
  });

  group('服务信息区', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    testWidgets('免费模式下也有获取模型列表与查询余额按钮', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: AiSourcePage(autoProbe: false)),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('查询余额'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('可用模型'), findsOneWidget);
      expect(find.text('获取模型列表'), findsOneWidget);
      expect(find.text('账户余额'), findsOneWidget);
      expect(find.text('查询余额'), findsOneWidget);
    });

    testWidgets('不支持余额的厂商会给出说明', (tester) async {
      SharedPreferences.setMockInitialValues({
        AiSourceRepository.prefsKey: const AiSourceConfig(
          mode: AiSourceMode.custom,
          providerId: 'zhipu',
          baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
          apiKey: 'sk-glm',
          model: 'glm-4.6',
        ).encode(),
      });
      await tester.pumpWidget(
        const MaterialApp(home: AiSourcePage(autoProbe: false)),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('查询余额'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      // 滚到完整可见再点，否则按钮中心可能落在屏幕外，tap 打不中
      await tester.ensureVisible(find.text('查询余额'));
      await tester.pumpAndSettle();
      // 不支持余额时不发请求，点一下只给出说明
      await tester.tap(find.text('查询余额'));
      await tester.pumpAndSettle();
      expect(find.textContaining('没有提供公开的余额接口'), findsOneWidget);
    });
  });
}
