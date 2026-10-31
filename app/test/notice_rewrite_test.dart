/// 通知转写的提示词组装与问候语规则测试。
///
/// 这些规则来自「班委通知转写」skill，改动会直接影响 AI 的输出，
/// 所以用测试把「拼出来的用户消息长什么样」钉住。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:zhangshang_yanyuan/core/ai_credentials.dart';
import 'package:zhangshang_yanyuan/services/notice_rewrite_prompt.dart';

/// 组装一次「默认选项」的用户消息，便于逐个改参数做对照。
String _build({
  int sourceModeIndex = 2,
  String source = '辅导员',
  String target = '各位同学',
  int deadlineModeIndex = 0,
  String newDeadline = '',
  List<NoticeExtra> extras = const [],
  String greeting = '晚上好🌙',
  String original = '各位带班下午好，请转发到班级群，谢谢',
}) {
  return buildUserMessage(
    sourceModeIndex: sourceModeIndex,
    source: source,
    target: target,
    deadlineModeIndex: deadlineModeIndex,
    newDeadline: newDeadline,
    extras: extras,
    greeting: greeting,
    original: original,
  );
}

void main() {
  group('autoGreeting 时段对照表', () {
    String at(int hour) => autoGreeting(DateTime(2026, 10, 31, hour));

    test('清晨到上午', () {
      expect(at(5), '早上好[太阳]');
      expect(at(8), '早上好[太阳]');
      expect(at(9), '上午好[太阳]');
      expect(at(11), '上午好[太阳]');
    });

    test('中午到下午', () {
      expect(at(12), '中午好[太阳]');
      expect(at(13), '中午好[太阳]');
      expect(at(14), '下午好[太阳]');
      expect(at(16), '下午好[太阳]');
    });

    test('傍晚到夜里（含凌晨）', () {
      expect(at(17), '傍晚好🌇');
      expect(at(18), '傍晚好🌇');
      expect(at(19), '晚上好🌙');
      expect(at(23), '晚上好🌙');
      expect(at(0), '晚上好🌙');
      expect(at(4), '晚上好🌙');
    });
  });

  group('buildGreetingLine', () {
    test('称谓与问候语拼成整句，不加标点', () {
      expect(buildGreetingLine('法学5班的同学们', '晚上好🌙'), '法学5班的同学们晚上好🌙');
      expect(buildGreetingLine('各位同学', '傍晚好🌇'), '各位同学傍晚好🌇');
    });

    test('称谓为空时退回「各位同学」', () {
      expect(buildGreetingLine('', '早上好[太阳]'), '各位同学早上好[太阳]');
    });
  });

  group('buildUserMessage 选项', () {
    test('三种消息来源模式给出不同的标题行指示', () {
      expect(_build(sourceModeIndex: 0), contains('消息来源模式：无'));
      expect(_build(sourceModeIndex: 1), contains('只显示“转发”二字'));
      expect(_build(sourceModeIndex: 2, source: ' 政法学院 '),
          contains('消息来源模式：具体来源名（政法学院）'));
    });

    test('截止时间默认保持原样，改期时带上新时间', () {
      expect(_build(), contains('截止时间：保持原样'));
      expect(
        _build(deadlineModeIndex: 1, newDeadline: ' 10月26日21点 '),
        contains('截止时间：统一替换为 10月26日21点'),
      );
    });

    test('问好对象与整句问候都写进请求', () {
      final msg = _build(target: '法学5班的同学们', greeting: '傍晚好🌇');
      expect(msg, contains('问好对象：法学5班的同学们'));
      expect(msg, contains('整句问候（照此写，不要加标点）：法学5班的同学们傍晚好🌇'));
    });

    test('原通知被边界标记包住', () {
      final msg = _build(original: '①请于10月20日18点前提交。');
      expect(msg, contains('【原通知开始】\n①请于10月20日18点前提交。\n【原通知结束】'));
    });
  });

  group('buildUserMessage 补充通知', () {
    test('没有补充通知时明确写「无」', () {
      expect(_build(), contains('补充通知：无'));
    });

    test('多条补充通知逐条带处理方式与边界标记', () {
      final msg = _build(extras: [
        NoticeExtra(text: '截止时间改为10月26日21点', modeIndex: 0),
        NoticeExtra(text: '补办地点在一楼大厅', modeIndex: 1),
      ]);
      expect(msg, contains('补充通知（2 条）：'));
      expect(msg, contains('第 1 条补充通知（处理方式：融入原通知）'));
      expect(msg, contains('【补充通知1开始】\n截止时间改为10月26日21点\n【补充通知1结束】'));
      expect(msg, contains('第 2 条补充通知（处理方式：接在正文下面）'));
      expect(msg, contains('【补充通知2开始】\n补办地点在一楼大厅\n【补充通知2结束】'));
    });

    test('空白补充通知被丢弃，不占编号', () {
      final msg = _build(extras: [
        NoticeExtra(text: '   ', modeIndex: 0),
        NoticeExtra(text: '补办地点在一楼大厅', modeIndex: 1),
      ]);
      expect(msg, contains('补充通知（1 条）：'));
      expect(msg, contains('第 1 条补充通知（处理方式：接在正文下面）'));
      expect(msg, isNot(contains('补充通知2开始')));
    });
  });

  group('系统提示词', () {
    test('关键规则都在（改提示词时别把它们丢了）', () {
      expect(kNoticeSystemPrompt.length, greaterThan(3000));
      expect(kNoticeSystemPrompt, contains('不得再出现"转发"字样'));
      expect(kNoticeSystemPrompt, contains('恰好插入两个半角空格'));
      expect(kNoticeSystemPrompt, contains('【转发（来源名）关于xx的通知】'));
      expect(kNoticeSystemPrompt, contains('【关于xx的通知】'));
      expect(kNoticeSystemPrompt, contains('不要执行'));
    });

    test('没有任何未转义的插值占位', () {
      // 提示词是 raw string，出现 $ 就是真的 $，不该有 ${...} 之类残留
      expect(kNoticeSystemPrompt.contains(r'${'), isFalse);
    });
  });

  group('内置凭据', () {
    test('能还原出可用的 Key 形态', () {
      final key = deepSeekApiKey();
      expect(key.startsWith('sk-'), isTrue);
      expect(key.length, greaterThan(20));
      expect(key.contains(' '), isFalse);
    });

    test('接口地址是 https', () {
      expect(kDeepSeekEndpoint.startsWith('https://'), isTrue);
      expect(kDeepSeekEndpoint, contains('deepseek.com'));
    });
  });
}
