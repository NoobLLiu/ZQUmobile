/// 验证码训练页。
///
/// 目的：用「人工输入」给离线识别器攒带标签的真样本。
/// 该验证码不是标准字体（实测与 10 种系统字体最佳相关仅 0.54~0.60），
/// 无法合成训练数据，只能靠真实样本；实测 36 类各 4~6 张即可达到可用精度。
///
/// 页面流程：抓一张验证码 → 用户照着输入 → 切字成功且字数一致才收录
/// → 自动换下一张。收满后可以点「自检」看留一交叉验证的准确率。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/captcha_fetcher.dart';
import '../services/captcha_ocr.dart';
import '../services/captcha_templates.dart';

/// 训练页。
class CaptchaTrainingPage extends StatefulWidget {
  const CaptchaTrainingPage({super.key});

  @override
  State<CaptchaTrainingPage> createState() => _CaptchaTrainingPageState();
}

class _CaptchaTrainingPageState extends State<CaptchaTrainingPage> {
  final TextEditingController _ctrl = TextEditingController();

  CaptchaTemplates _templates = CaptchaTemplates();
  Uint8List? _image;
  bool _loading = true;
  String? _error;
  String _hint = '';
  int _skipped = 0;
  String _selfCheck = '';

  /// 建议的字符集（出现过的都是大写字母 + 数字）。
  static const String alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final t = await CaptchaTemplateRepository.load();
    if (!mounted) return;
    setState(() => _templates = t);
    await _next();
  }

  Future<void> _next() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bytes = await CaptchaFetcher.fetch();
      if (!mounted) return;
      setState(() {
        _image = bytes;
        _loading = false;
      });
      _ctrl.clear();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '取验证码失败：$e\n'
            '校外网络可能无法直连教务系统；这种情况下不用在这里训练，'
            '正常登录时每次登录成功都会自动收录一张。';
      });
    }
  }

  /// 提交当前这串字符。
  Future<void> _submit() async {
    final text = _ctrl.text.trim().toUpperCase();
    final image = _image;
    if (text.isEmpty || image == null) return;

    final seg = CaptchaOcr.segment(image);
    if (seg == null) {
      setState(() {
        _skipped++;
        _hint = '这张没切准（背景干扰），已跳过';
      });
      await _next();
      return;
    }
    if (seg.glyphs.length != text.length) {
      setState(() {
        _skipped++;
        _hint = '切出 ${seg.glyphs.length} 个字，你输了 ${text.length} 个，已跳过';
      });
      await _next();
      return;
    }

    for (var i = 0; i < text.length; i++) {
      _templates.add(text[i], seg.glyphs[i].pixels);
    }
    await CaptchaTemplateRepository.save(_templates);
    if (!mounted) return;
    setState(() {
      _hint = '已收录 $text';
      _selfCheck = '';
    });
    await _next();
  }

  Future<void> _runSelfCheck() async {
    if (_templates.sampleCount == 0) {
      setState(() => _selfCheck = '还没有样本');
      return;
    }
    final (correct, total) = _templates.leaveOneOut();
    final acc = total == 0 ? 0.0 : correct / total;
    setState(() {
      _selfCheck = '留一自检：$correct / $total = ${(acc * 100).toStringAsFixed(1)}%'
          '（单字准确率；整串 4~6 位会再乘方）';
    });
  }

  Future<void> _clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空训练样本'),
        content: const Text('将删除本机保存的全部验证码字形样本，识别会退回手动输入。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确定清空'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await CaptchaTemplateRepository.clear();
    if (!mounted) return;
    setState(() {
      _templates = CaptchaTemplates();
      _selfCheck = '';
      _hint = '已清空';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final counts = _templates.counts;
    final covered = counts.keys.where((c) => (counts[c] ?? 0) >= 3).length;
    final missing = alphabet.split('').where((c) => (counts[c] ?? 0) < 3).join(' ');

    return Scaffold(
      appBar: AppBar(title: const Text('验证码训练')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Card(
            color: theme.colorScheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '已收集 ${_templates.sampleCount} 个字形样本，'
                    '$covered/${alphabet.length} 个字符够用（每类 ≥3）',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '建议先攒到 150 个以上（约 30~45 张验证码）。'
                    '缺样本的字符：${missing.isEmpty ? "无" : missing}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          Container(
            height: 88,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            alignment: Alignment.center,
            child: _loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : (_image == null
                    ? Text('没有图片', style: theme.textTheme.bodySmall)
                    : Image.memory(_image!, height: 80, fit: BoxFit.contain)),
          ),
          const SizedBox(height: 10),

          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error, fontSize: 13),
              ),
            ),

          TextField(
            controller: _ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            maxLength: 6,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
            ],
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 22,
              letterSpacing: 6,
              fontWeight: FontWeight.w600,
            ),
            decoration: const InputDecoration(
              isDense: true,
              counterText: '',
              hintText: '照着图输入',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 10),

          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _loading ? null : _next,
                  child: const Text('换一张'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: _loading ? null : _submit,
                  child: const Text('提交并下一张'),
                ),
              ),
            ],
          ),

          if (_hint.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                _hint,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.primary),
              ),
            ),

          const Divider(height: 32),

          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _runSelfCheck,
                  child: const Text('自检准确率'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextButton(
                  onPressed: _clearAll,
                  child: const Text('清空样本'),
                ),
              ),
            ],
          ),
          if (_selfCheck.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_selfCheck, style: theme.textTheme.bodySmall),
            ),

          const SizedBox(height: 16),
          Text(
            '说明：样本只存本机，不上传。登录时若能识别就自动代填，'
            '识别没把握会自动退回手动输入，不会反复试错把账号试到锁定。\n'
            '另外，每次登录教务系统成功，也会把那一张验证码自动收录为样本。',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
          if (_skipped > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '本次会话已跳过 $_skipped 张切不准的验证码',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ),
        ],
      ),
    );
  }
}
