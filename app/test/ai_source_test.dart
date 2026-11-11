/// 模型来源配置：URL 规整、预置厂商、配置决策、本地存储与页面版式。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
        normalizeChatUrl('https://api.moonshot.cn/v1'),
        'https://api.moonshot.cn/v1/chat/completions',
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
      // DeepSeek / GLM / Kimi / MiMo 按量 / MiMo TokenPlan
      expect(kAiProviderPresets.length, 5);
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
      expect(findAiProvider('mimo')?.baseUrl, 'https://api.xiaomimimo.com/v1');
      expect(findAiProvider('mimo-tokenplan')?.baseUrl,
          'https://token-plan-cn.xiaomimimo.com/v1');
      expect(findAiProvider('不存在的厂商'), isNull);
    });

    test('MiMo 按量计费与 TokenPlan 的 Key 体系分开', () {
      final payAsYouGo = findAiProvider('mimo')!;
      final tokenPlan = findAiProvider('mimo-tokenplan')!;
      expect(payAsYouGo.name, contains('按量计费'));
      expect(tokenPlan.name, contains('TokenPlan'));
      expect(tokenPlan.note, contains('不通用'));
    });

    test('推荐模型名是 2026-11 的现行版本', () {
      expect(findAiProvider('deepseek')!.model, 'deepseek-flash');
      expect(findAiProvider('zhipu')!.model, 'glm-5.3');
      expect(findAiProvider('moonshot')!.model, 'kimi-k3.1-pro');
      expect(findAiProvider('mimo')!.model, 'mimo-v2.6-flash');
      expect(findAiProvider('mimo-tokenplan')!.model, 'mimo-v2.6-flash');
    });
  });

  group('AiSourceConfig 决策', () {
    test('默认指向 DeepSeek 官方，但地址和 Key 都要用户填', () {
      const config = AiSourceConfig();
      expect(config.providerId, 'deepseek');
      expect(config.providerName, 'DeepSeek 官方');
      expect(config.baseUrl, isEmpty);
      expect(config.chatUrl, isEmpty);
      expect(config.effectiveApiKey, isEmpty);
      expect(config.effectiveModel, isEmpty);
      expect(config.validate(), '请填写 Base URL');
    });

    test('填好后地址按 OpenAI 格式拼出', () {
      const config = AiSourceConfig(
        providerId: 'deepseek',
        baseUrl: 'https://api.deepseek.com',
        apiKey: 'sk-my-own-key',
        model: 'deepseek-flash',
      );
      expect(config.chatUrl, 'https://api.deepseek.com/chat/completions');
      expect(config.effectiveApiKey, 'sk-my-own-key');
      expect(config.effectiveModel, 'deepseek-flash');
      expect(config.validate(), isNull);
    });

    test('自定义厂商没有预置名字', () {
      expect(
        const AiSourceConfig(providerId: kCustomProviderId).providerName,
        '自定义服务',
      );
    });

    test('thinking 字段只对 DeepSeek 官方发，开深度思考时不发', () {
      expect(
        const AiSourceConfig(providerId: 'deepseek').supportsThinking,
        isTrue,
      );
      expect(const AiSourceConfig(providerId: 'zhipu').supportsThinking,
          isFalse);
      expect(shouldSendThinking(true, false), isTrue);
      expect(shouldSendThinking(true, true), isFalse);
      expect(shouldSendThinking(false, false), isFalse);
      expect(shouldSendThinking(false, true), isFalse);
    });
  });

  group('表单校验', () {
    AiSourceConfig build({
      String baseUrl = 'https://api.deepseek.com',
      String apiKey = 'sk-test',
      String model = 'deepseek-flash',
    }) =>
        AiSourceConfig(
          baseUrl: baseUrl,
          apiKey: apiKey,
          model: model,
        );

    test('三项齐全才通过', () {
      expect(build().validate(), isNull);
    });

    test('逐项给出中文错误', () {
      expect(build(baseUrl: '').validate(), '请填写 Base URL');
      expect(build(baseUrl: 'api.deepseek.com').validate(),
          contains('http://'));
      expect(build(baseUrl: 'https://api deepseek.com').validate(),
          contains('空格'));
      expect(build(apiKey: '  ').validate(), '请填写 API Key');
      expect(build(model: '').validate(), '请填写模型名称');
    });
  });

  group('序列化与存储', () {
    test('JSON 往返保留全部字段', () {
      const config = AiSourceConfig(
        providerId: 'zhipu',
        baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
        apiKey: 'sk-abc',
        model: 'glm-5.3',
      );
      final restored = AiSourceConfig.decode(config.encode());
      expect(restored.providerId, 'zhipu');
      expect(restored.apiKey, 'sk-abc');
      expect(restored.model, 'glm-5.3');
      expect(restored.baseUrl, 'https://open.bigmodel.cn/api/paas/v4');
    });

    test('旧版本的 mode / freeModelIndex 字段会被忽略', () {
      final legacy = AiSourceConfig.decode(
        '{"mode":"custom","freeModelIndex":1,'
        '"providerId":"moonshot","baseUrl":"https://api.moonshot.cn/v1",'
        '"apiKey":"sk-kimi","model":"kimi-k3.1-pro"}',
      );
      expect(legacy.providerId, 'moonshot');
      expect(legacy.apiKey, 'sk-kimi');
      expect(legacy.model, 'kimi-k3.1-pro');
    });

    test('损坏数据回退到默认值', () {
      expect(AiSourceConfig.decode('{坏掉的 json').providerId, 'deepseek');
      expect(AiSourceConfig.decode(null).baseUrl, isEmpty);
    });

    test('仓库读写与清空', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      expect((await AiSourceRepository.load()).apiKey, isEmpty);

      const config = AiSourceConfig(
        providerId: 'moonshot',
        baseUrl: 'https://api.moonshot.cn/v1',
        apiKey: 'sk-kimi',
        model: 'kimi-k3.1-pro',
      );
      await AiSourceRepository.save(config);
      final loaded = await AiSourceRepository.load();
      expect(loaded.providerId, 'moonshot');
      expect(loaded.apiKey, 'sk-kimi');

      await AiSourceRepository.clear();
      expect((await AiSourceRepository.load()).apiKey, isEmpty);
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

    testWidgets('直接显示厂商下拉与三个输入框，未配置时自动预填 DeepSeek', (tester) async {
      await pump(tester);

      expect(find.text('配置模型来源'), findsOneWidget);
      expect(find.text('模型厂商'), findsNothing); // 厂商标题并入区块标题
      expect(find.text('Base URL'), findsOneWidget);
      expect(find.text('API Key'), findsOneWidget);
      expect(find.text('模型名称'), findsOneWidget);
      expect(find.text('测试连接'), findsOneWidget);
      expect(find.text('保存配置'), findsOneWidget);

      // 默认厂商预填好地址与推荐模型名，用户只需补 Key
      expect(find.text('https://api.deepseek.com'), findsWidgets);
      expect(find.text('deepseek-flash'), findsWidgets);
    });

    testWidgets('保存过的配置能回读到页面', (tester) async {
      SharedPreferences.setMockInitialValues({
        AiSourceRepository.prefsKey: const AiSourceConfig(
          providerId: 'zhipu',
          baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
          apiKey: 'sk-glm',
          model: 'glm-5.3',
        ).encode(),
      });
      await pump(tester);

      expect(find.text('https://open.bigmodel.cn/api/paas/v4'), findsOneWidget);
      expect(find.text('glm-5.3'), findsOneWidget);
    });

    testWidgets('配置不完整时测试连接给出中文提示，不发请求', (tester) async {
      await pump(tester);
      await tester.tap(find.text('测试连接'));
      await tester.pumpAndSettle();
      expect(find.text('请填写 API Key'), findsOneWidget);
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
    test('按厂商派生，模型地址跟着 Base URL 走', () {
      const config = AiSourceConfig(
        providerId: 'moonshot',
        baseUrl: 'https://api.moonshot.cn/v1',
        apiKey: 'sk-kimi',
        model: 'kimi-k3.1-pro',
      );
      expect(config.modelsUrl, 'https://api.moonshot.cn/v1/models');
      expect(config.balanceUrl, 'https://api.moonshot.cn/v1/users/me/balance');
      expect(config.supportsBalance, isTrue);
    });

    test('自定义厂商能查模型但没有余额接口', () {
      const config = AiSourceConfig(
        providerId: kCustomProviderId,
        baseUrl: 'https://example.com/v1',
        apiKey: 'sk-x',
        model: 'x',
      );
      expect(config.modelsUrl, 'https://example.com/v1/models');
      expect(config.balanceUrl, isNull);
      expect(config.supportsBalance, isFalse);
    });

    test('预置厂商里只有 DeepSeek 与 Kimi 有公开余额接口', () {
      final withBalance = kAiProviderPresets
          .where((p) => p.supportsBalance)
          .map((p) => p.id)
          .toSet();
      expect(withBalance, {'deepseek', 'moonshot'});
    });

    test('Key 没填时不允许自动查询', () {
      // 组件层面 _canProbe 的同款条件：地址和 Key 都要有
      const noKey = AiSourceConfig(
        providerId: 'deepseek',
        baseUrl: 'https://api.deepseek.com',
      );
      expect(
        noKey.baseUrl.trim().isNotEmpty && noKey.apiKey.trim().isNotEmpty,
        isFalse,
      );
    });
  });

  group('服务信息区', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    testWidgets('有获取模型列表与查询余额按钮', (tester) async {
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
          providerId: 'zhipu',
          baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
          apiKey: 'sk-glm',
          model: 'glm-5.3',
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
