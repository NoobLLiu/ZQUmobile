/// 临时联调脚本：用真实 DeepSeek 接口跑一遍通知转写，检查输出格式是否守规矩。
///
/// 用法：cd app && dart run tool/smoke_notice.dart
library;

import 'dart:io';

import 'package:zhangshang_yanyuan/core/ai_credentials.dart';
import 'package:zhangshang_yanyuan/services/deepseek_client.dart';
import 'package:zhangshang_yanyuan/services/notice_rewrite_prompt.dart';

const _original = '''各位带班下午好，现有一则关于"挑战杯"赛事的补充通知⚠️
①电子版材料提交截止时间延长至10月24日21点前。
②负责人需在10月17日18点前填写报名表单。
(正式报名将以报名表单情况为准，请务必准确填写)
③后续比赛通知将在群内发布，务必加入咨询群。
请各位带班及时转发到新生群，收到请回复，谢谢[玫瑰][玫瑰]''';

Future<void> main() async {
  stdout.write('Key 形态：${deepSeekApiKey().substring(0, 3)}…（长度 ${deepSeekApiKey().length}）\n');

  final userMessage = buildUserMessage(
    sourceModeIndex: 2,
    source: '辅导员',
    target: '法学5班的同学们',
    deadlineModeIndex: 0,
    newDeadline: '',
    extras: [
      NoticeExtra(text: '提交邮箱改为 tzb@zqu.edu.cn，其他内容不变。', modeIndex: 0),
    ],
    greeting: '傍晚好🌇',
    original: _original,
  );

  stdout.write('===== 请求的用户消息 =====\n$userMessage\n');
  stdout.write('===== 模型输出 =====\n');

  final client = DeepSeekClient();
  final buffer = StringBuffer();
  final sw = Stopwatch()..start();
  await for (final delta in client.streamChat(
    model: kDefaultModelId,
    systemPrompt: kNoticeSystemPrompt,
    userMessage: userMessage,
  )) {
    buffer.write(delta);
  }
  stdout.write('${buffer.toString()}\n');
  stdout.write('===== 检查 =====\n');
  stdout.write('耗时：${sw.elapsedMilliseconds} ms\n');
  stdout.write('字数：${buffer.length}\n');

  final lines = buffer.toString().split('\n');
  final body = lines.where((l) => l.trim().isNotEmpty).toList();
  if (body.isEmpty) {
    stdout.write('❌ 空输出\n');
    exit(1);
  }
  final title = body.first;
  stdout.write('标题行：${title.startsWith(' ') ? '❌ 有缩进' : '✅ 顶格'} | $title');
  stdout.write('\n');
  final bodyNoTitle = body.skip(1).toList();
  var noIndent = <String>[];
  var hasFullWidth = <String>[];
  for (final line in bodyNoTitle) {
    final isItem = RegExp(r'^[①②③④⑤⭕⚠️（(]').hasMatch(line);
    if (isItem) continue;
    if (!line.startsWith('  ')) noIndent.add(line);
    if (line.contains('\u3000')) hasFullWidth.add(line);
  }
  final bodyText = bodyNoTitle.join('\n');
  stdout.write('缩进不符的段落：${noIndent.isEmpty ? '✅ 无' : '❌ ${noIndent.length} 行 → ${noIndent.first}'}\n');
  stdout.write('全角空格：${hasFullWidth.isEmpty ? '✅ 无' : '❌ ${hasFullWidth.length} 行'}\n');
  stdout.write('正文/结尾出现"转发"：${bodyText.contains('转发') ? '❌ 有' : '✅ 无'}\n');
  stdout.write('保留边界标记：${buffer.toString().contains('【原通知') ? '❌ 泄漏' : '✅ 无'}\n');
}
