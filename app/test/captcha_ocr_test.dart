/// 验证码离线识别的单元测试。
///
/// `test/fixtures/captcha/` 里的图是从教务系统 `/yzm` 真实抓下来的样本，
/// 用于固定「切字」行为：换算法时这里的断言会先报错。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:zhangshang_yanyuan/services/captcha_ocr.dart';
import 'package:zhangshang_yanyuan/services/captcha_templates.dart';

Uint8List fixture(String name) =>
    Uint8List.fromList(File('test/fixtures/captcha/$name').readAsBytesSync());

void main() {
  group('切字', () {
    test('真实验证码能切出 4~6 个字，字形已归一化成 24x24', () {
      final seg = CaptchaOcr.segment(fixture('c_048.jpg'));
      expect(seg, isNotNull);
      expect(seg!.glyphs.length, 4);
      expect(seg.width, 200);
      expect(seg.height, 80);
      for (final g in seg.glyphs) {
        expect(g.pixels.length, CaptchaOcr.glyphSize * CaptchaOcr.glyphSize);
        expect(g.pixels.every((v) => v >= 0 && v <= 255), isTrue);
        expect(g.box[2] > g.box[0] && g.box[3] > g.box[1], isTrue);
      }
    });

    test('字块按从左到右排序', () {
      final seg = CaptchaOcr.segment(fixture('c_007.jpg'))!;
      final xs = seg.glyphs.map((g) => g.box[0]).toList();
      final sorted = [...xs]..sort();
      expect(xs, sorted);
    });

    test('两位数的图也能切对字数（5 / 6 位）', () {
      expect(CaptchaOcr.segment(fixture('c_007.jpg'))!.glyphs.length, 5);
      expect(CaptchaOcr.segment(fixture('c_062.jpg'))!.glyphs.length, 6);
    });

    test('同一张图两次结果一致（无随机性）', () {
      final a = CaptchaOcr.segment(fixture('c_013.jpg'))!;
      final b = CaptchaOcr.segment(fixture('c_013.jpg'))!;
      expect(a.angle, b.angle);
      expect(a.glyphs.length, b.glyphs.length);
      for (var i = 0; i < a.glyphs.length; i++) {
        expect(a.glyphs[i].box, b.glyphs[i].box);
        expect(a.glyphs[i].pixels, b.glyphs[i].pixels);
      }
    });

    test('不是图片的数据返回 null，不抛异常', () {
      final notImage = Uint8List.fromList(List.generate(64, (i) => i));
      expect(CaptchaOcr.segment(notImage), isNull);
    });

    test('按 85% 质量重编码（页面 canvas 回传的真实路径）不影响切字', () {
      // auto_login.js 是把 <img> 画到 canvas 再 toDataURL('image/jpeg', 0.85)，
      // 所以线上拿到的永远是二次编码过的图，这里守住这条路径。
      for (final name in [
        'c_007.jpg',
        'c_013.jpg',
        'c_034.jpg',
        'c_048.jpg',
        'c_062.jpg',
      ]) {
        final original = fixture(name);
        final recoded = Uint8List.fromList(
          img.encodeJpg(img.decodeJpg(original)!, quality: 85),
        );
        expect(
          CaptchaOcr.segment(recoded)?.glyphs.length,
          CaptchaOcr.segment(original)?.glyphs.length,
          reason: name,
        );
      }
    });

    test('背景太花/字粘连的图宁可不切，也不硬凑字数', () {
      // 这三张实测切不出稳定字数（90 张里这类约 20%）：
      // 契约是返回 null，让调用方退回手动输入，而不是乱猜。
      // 若将来改进算法让它们可切，这里应更新为对应的字数。
      for (final name in ['c_000.jpg', 'c_021.jpg', 'c_077.jpg']) {
        expect(CaptchaOcr.segment(fixture(name)), isNull, reason: name);
      }
    });
  });

  group('模板打分', () {
    test('归一化后是零均值单位向量', () {
      final g = CaptchaOcr.segment(fixture('c_048.jpg'))!.glyphs.first;
      final u = CaptchaOcr.unit(g.pixels);
      final mean = u.reduce((a, b) => a + b) / u.length;
      final norm = u.fold<double>(0, (s, v) => s + v * v);
      expect(mean.abs() < 1e-4, isTrue);
      expect((norm - 1).abs() < 1e-4, isTrue);
    });

    test('自己跟自己的相关分是 1.0', () {
      final g = CaptchaOcr.segment(fixture('c_048.jpg'))!.glyphs.first;
      final t = CaptchaTemplates()..add('A', g.pixels);
      expect(t.rank(g.pixels).first.value, closeTo(1.0, 1e-5));
    });

    test('样本按相关分从高到低排序', () {
      final glyphs = CaptchaOcr.segment(fixture('c_062.jpg'))!.glyphs;
      final t = CaptchaTemplates();
      for (var i = 0; i < glyphs.length; i++) {
        t.add('ABCDEF'[i], glyphs[i].pixels);
      }
      final ranked = t.rank(glyphs[0].pixels);
      expect(ranked.first.key, 'A');
      for (var i = 1; i < ranked.length; i++) {
        expect(ranked[i - 1].value >= ranked[i].value, isTrue);
      }
    });

    test('留一自检：单样本每类时自检没有意义，重复样本时全对', () {
      final glyphs = CaptchaOcr.segment(fixture('c_062.jpg'))!.glyphs;
      final single = CaptchaTemplates();
      for (var i = 0; i < glyphs.length; i++) {
        single.add('ABCDEF'[i], glyphs[i].pixels);
      }
      // 每类只有 1 张：留一把它本身剔掉后该类没质心，
      // 只能在其余 5 类里选，正确率自然接近 0 —— 所以自检结果不可信
      final (c1, t1) = single.leaveOneOut();
      expect(t1, 6);
      expect(c1 <= 1, isTrue);

      final dup = CaptchaTemplates();
      for (var i = 0; i < glyphs.length; i++) {
        for (var k = 0; k < 3; k++) {
          dup.add('ABCDEF'[i], glyphs[i].pixels);
        }
      }
      final (correct, total) = dup.leaveOneOut();
      expect(total, 18);
      expect(correct, 18);
    });

    test('每类样本数有上限，防止本地存储无限增长', () {
      final g = CaptchaOcr.segment(fixture('c_048.jpg'))!.glyphs.first;
      final t = CaptchaTemplates();
      for (var i = 0; i < CaptchaTemplates.maxPerClass + 8; i++) {
        t.add('A', g.pixels);
      }
      expect(t.counts['A'], CaptchaTemplates.maxPerClass);
      expect(t.sampleCount, CaptchaTemplates.maxPerClass);
    });

    test('像素与 JSON 往返不丢样本', () {
      final glyphs = CaptchaOcr.segment(fixture('c_048.jpg'))!.glyphs;
      final t = CaptchaTemplates();
      for (var i = 0; i < glyphs.length; i++) {
        t.add('ABCD'[i], glyphs[i].pixels);
      }
      final back = CaptchaTemplates.fromJson(t.toJson());
      expect(back.sampleCount, t.sampleCount);
      expect(back.classCount, t.classCount);
      expect(back.counts, t.counts);
      expect(
        CaptchaOcr.encodePixels(glyphs.first.pixels),
        CaptchaOcr.encodePixels(
          CaptchaOcr.decodePixels(CaptchaOcr.encodePixels(glyphs.first.pixels)),
        ),
      );
    });
  });

  group('识别结论', () {
    test('没有训练样本时不分青红皂白地瞎猜：直接给出不可信', () {
      final pred = CaptchaOcr.predict(fixture('c_048.jpg'), CaptchaTemplates());
      expect(pred, isNotNull);
      expect(pred!.ok, isFalse);
      expect(pred.reason, '还没有训练数据');
      expect(pred.text, '????');
    });

    test('用自身字形做模板能认出自己（管道连通性）', () {
      final bytes = fixture('c_062.jpg');
      final seg = CaptchaOcr.segment(bytes)!;
      final t = CaptchaTemplates();
      for (var i = 0; i < seg.glyphs.length; i++) {
        t.add('ABCDEF'[i], seg.glyphs[i].pixels);
      }
      final pred = CaptchaOcr.predict(bytes, t)!;
      expect(pred.text.length, seg.glyphs.length);
      expect(pred.scores.every((s) => s > 0.95), isTrue);
    });

    test('两个字符长得一样时判为「容易混淆」，不许自动代填', () {
      final bytes = fixture('c_048.jpg');
      final glyphs = CaptchaOcr.segment(bytes)!.glyphs;
      final t = CaptchaTemplates();
      // A~D 各占一个字，E 与 A 完全重复 → A 的字必然在 A/E 之间摇摆
      for (var i = 0; i < glyphs.length; i++) {
        t.add('ABCD'[i], glyphs[i].pixels);
      }
      t.add('E', glyphs.first.pixels);
      final pred = CaptchaOcr.predict(bytes, t)!;
      expect(pred.ok, isFalse);
      expect(pred.reason, '字符容易混淆');
      expect(pred.scores.every((s) => s >= CaptchaOcr.minScore), isTrue);
      expect(pred.margins.first < CaptchaOcr.minMargin, isTrue);
    });
  });
}
