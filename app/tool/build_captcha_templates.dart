// 重新生成预置验证码模板 assets/captcha_templates.json 的构建脚本。
//
// 输入：视觉标注好的真实验证码（路径见下方常量，本机临时目录）。
// 步骤：切字 + 与标注配对 → 构建模板（多质心）→ 整串触发率/精度扫描
// → 导出资产。日后想扩充预置集时重跑本脚本即可。
//
// 运行：flutter run tool/... 不适用，直接 `dart run`（需先 flutter pub get）。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:zhangshang_yanyuan/services/captcha_ocr.dart';
import 'package:zhangshang_yanyuan/services/captcha_templates.dart';

const _labelPath = 'C:/Users/BrianLiu/AppData/Local/Temp/zsy_labels.json';
const _imgDir = 'C:/Users/BrianLiu/AppData/Local/Temp/zsy_yzm2';
const _labelPath2 = 'C:/Users/BrianLiu/AppData/Local/Temp/zsy_labels2.json';
const _imgDir2 = 'C:/Users/BrianLiu/AppData/Local/Temp/zsy_bulk';
const _outPath = 'assets/captcha_templates.json';

void main() {
  // ---- 0. 汇总两批标注 ----
  final jobs = <String, ({String text, String dir})>{};
  final l1 =
      jsonDecode(File(_labelPath).readAsStringSync()) as Map<String, dynamic>;
  final l2 =
      jsonDecode(File(_labelPath2).readAsStringSync()) as Map<String, dynamic>;
  for (final e in l1.entries) {
    jobs[e.key] = (text: (e.value as String).trim(), dir: _imgDir);
  }
  for (final e in l2.entries) {
    jobs[e.key] = (text: (e.value as String).trim(), dir: _imgDir2);
  }
  // ignore: avoid_print
  print('标注总数 ${jobs.length}');

  // ---- 1. 配对构建 ----
  final paired = <String, ({String text, CaptchaSegmentation seg})>{};
  var segFail = 0, lenMismatch = 0;
  for (final name in jobs.keys.toList()..sort()) {
    final text = jobs[name]!.text.toUpperCase();
    final bytes = Uint8List.fromList(
      File('${jobs[name]!.dir}/$name').readAsBytesSync(),
    );
    final seg = CaptchaOcr.segment(bytes);
    if (seg == null) {
      segFail++;
      continue;
    }
    if (seg.glyphs.length != text.length) {
      lenMismatch++;
      continue;
    }
    paired[name] = (text: text, seg: seg);
  }
  // ignore: avoid_print
  print('配对 ${paired.length} 张（切字失败 $segFail，字数不符 $lenMismatch）');

  // 每个字形样本：(字符, 像素, 来源图)
  final samples = <({String ch, Float32List px, String img})>[];
  final t = CaptchaTemplates();
  for (final e in paired.entries) {
    for (var i = 0; i < e.value.seg.glyphs.length; i++) {
      final ch = e.value.text[i];
      samples.add((ch: ch, px: e.value.seg.glyphs[i].pixels, img: e.key));
      t.add(ch, e.value.seg.glyphs[i].pixels);
    }
  }
  // ignore: avoid_print
  print('样本 ${t.sampleCount} 个，${t.classCount} 类');

  // ---- 2. 字符级留一统计（生产路径 predict，含 TTA）----
  // 注：predict 内部对每个字形做 TTA 取最高分；评估用整套模板（含该样本
  // 自身，会略偏乐观），但标签噪声也在同一侧抵消一部分，作为调参依据够用。
  final byImg = <String, List<({double s, double m, bool right})>>{};
  final ownScores = <double>[];
  final suspicious = <String>[];
  for (final e in paired.entries) {
    final bytes = Uint8List.fromList(
      File('${jobs[e.key]!.dir}/${e.key}').readAsBytesSync(),
    );
    final pred = CaptchaOcr.predict(bytes, t)!;
    final list = <({double s, double m, bool right})>[];
    for (var i = 0; i < pred.scores.length; i++) {
      final right = i < e.value.text.length && pred.text[i] == e.value.text[i];
      list.add((s: pred.scores[i], m: pred.margins[i], right: right));
      ownScores.add(pred.scores[i]);
      if (pred.scores[i] < 0.25 && i < e.value.text.length) {
        suspicious.add(
          '${e.key}:${e.value.text[i]}'
          '(${pred.scores[i].toStringAsFixed(2)}→${pred.text[i]})',
        );
      }
    }
    byImg[e.key] = list;
  }
  // ignore: avoid_print
  print('可疑字形（own<0.25）: ${suspicious.isEmpty ? "无" : suspicious.join(", ")}');

  // ---- 3. 整串门禁扫描 ----
  String sweep(double minS, double minM) {
    var trigger = 0, right = 0;
    for (final list in byImg.values) {
      final ok = list.every((g) => g.s >= minS && g.m >= minM);
      if (ok) {
        trigger++;
        if (list.every((g) => g.right)) right++;
      }
    }
    final total = byImg.length;
    final prec = trigger == 0 ? 100.0 : right / trigger * 100;
    return 's=$minS m=$minM → 触发 $trigger/$total'
        '(${(trigger / total * 100).toStringAsFixed(0)}%)'
        ' 精度 ${prec.toStringAsFixed(1)}%';
  }

  // ignore: avoid_print
  print('--- 整串门禁扫描（TTA 生产路径） ---');
  for (final m in [0.04, 0.06, 0.08, 0.10]) {
    for (final s in [0.60, 0.65, 0.70, 0.75, 0.80]) {
      // ignore: avoid_print
      print(sweep(s, m));
    }
  }
  // ignore: avoid_print
  print('默认: ${sweep(CaptchaOcr.minScore, CaptchaOcr.minMargin)}');

  // ---- 4. 导出预置集 ----
  final json = jsonEncode(t.toJson());
  File(_outPath).writeAsStringSync(json);
  // ignore: avoid_print
  print('已导出 $_outPath (${(json.length / 1024).toStringAsFixed(0)}KB)');
  // ignore: avoid_print
  print('留一自检（工具内置）: ${t.leaveOneOut()}');
}
