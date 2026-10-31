/// 教务图形验证码的离线识别。
///
/// 算法与 `%TEMP%\zsy_proto` 里的 Python 原型一致（实测：切字成功率 84%，
/// 同字一致性 0.87~0.93，5 类留一交叉验证 100%）：
///
///   1. 亮度阈值 170 → 3x3 腐蚀 2 次 + 膨胀 2 次，去掉背景细线与斑点；
///   2. 连通域取字块（面积/高度/宽度过滤），按 x 排序；
///   3. 文字整体倾斜只有 ±6°，用字块中心做最小二乘拟合求角度，
///      旋转摆正后重新切一次字（迭代到残差变小）；
///   4. 每个字块裁出来、反色、按最大值归一化、补成正方形、缩放到 24x24；
///   5. 与「每类质心」做归一化相关（等价余弦相似度）取最近类，
///      并要求「最高分够高 + 与次高分差距够大」才判定可信。
///
/// ⚠️ 这里刻意**不做字形合成/字体渲染**：实测该验证码不是标准字体
/// （与 10 种 Windows 字体最佳相关仅 0.54~0.60），只能用真实样本训练。
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'captcha_templates.dart';

/// 归一化后的单个字形（24x24 灰度像素，0~255）。
class CaptchaGlyph {
  CaptchaGlyph(this.pixels, this.box);

  /// 长度 = [CaptchaOcr.glyphSize]^2 的像素值数组。
  final Float32List pixels;

  /// 原图坐标 [x0, y0, x1, y1]。
  final List<int> box;
}

/// 一张验证码的切字结果。
class CaptchaSegmentation {
  CaptchaSegmentation({
    required this.glyphs,
    required this.angle,
    required this.width,
    required this.height,
  });

  final List<CaptchaGlyph> glyphs;

  /// 为了摆正文字旋转的角度（度）。
  final double angle;

  /// 原始图尺寸。
  final int width;
  final int height;
}

/// 一次识别结论。
class CaptchaPrediction {
  CaptchaPrediction({
    required this.ok,
    required this.text,
    required this.scores,
    required this.margins,
    this.reason,
  });

  /// 是否可信到可以直接代填。
  final bool ok;

  /// 识别出的文本（[ok] 为 false 时也给出猜测，仅供展示）。
  final String text;

  /// 每个字符的最高相关分。
  final List<double> scores;

  /// 每个字符「最高分 - 次高分」。
  final List<double> margins;

  /// 不可信的原因。
  final String? reason;
}

/// 灰度图。
class _Gray {
  _Gray(this.w, this.h, this.data);

  final int w;
  final int h;
  final Uint8List data;
}

/// 验证码识别器（无状态，模板由外部传入）。
class CaptchaOcr {
  CaptchaOcr._();

  /// 字形归一化边长。
  static const int glyphSize = 24;

  /// 亮度阈值（实测 170 最稳）。
  static const int threshold = 170;

  /// 形态学迭代次数。
  static const int erodeIterations = 2;

  /// 字块过滤下限。
  static const int minArea = 150;
  static const int minHeight = 22;
  static const int minWidth = 6;

  /// 合法字数范围。
  static const int minGlyphs = 4;
  static const int maxGlyphs = 6;

  /// 判定「可信」的门槛：最高相关 ≥ [minScore]，且与次高差距 ≥ [minMargin]。
  static const double minScore = 0.70;
  static const double minMargin = 0.06;

  /// 解码 → 切字 → 归一化。切不出 4~6 个字时返回 null。
  static CaptchaSegmentation? segment(Uint8List jpegBytes) {
    final decoded = img.decodeImage(jpegBytes);
    if (decoded == null) return null;
    var g = _toGray(decoded);
    var angle = 0.0;

    // 摆正：最多两轮，每轮先试正反两个方向，取残差小的
    for (var pass = 0; pass < 2; pass++) {
      final bs = _boxes(_mask(g), g.w, g.h);
      if (bs.isEmpty) break;
      final a = _centerAngle(bs);
      if (a.abs() < 0.15) break;
      final plus = _residualAfter(g, a);
      final minus = _residualAfter(g, -a);
      final use = plus <= minus ? a : -a;
      g = _rotate(g, use);
      angle += use;
    }

    var bs = _boxes(_mask(g), g.w, g.h);
    if (bs.length < minGlyphs || bs.length > maxGlyphs) return null;
    // 高度异常的多半是背景碎块
    final hs = bs.map((b) => b[3] - b[1]).toList()..sort();
    final med = hs[hs.length ~/ 2].toDouble();
    bs = bs
        .where((b) => (b[3] - b[1]) >= 0.55 * med && (b[3] - b[1]) <= 1.7 * med)
        .toList();
    if (bs.length < minGlyphs || bs.length > maxGlyphs) return null;

    final glyphs = bs.map((b) => CaptchaGlyph(_normalize(g, b), b)).toList();
    return CaptchaSegmentation(
      glyphs: glyphs,
      angle: angle,
      width: g.w,
      height: g.h,
    );
  }

  /// 识别整串。
  static CaptchaPrediction? predict(
    Uint8List jpegBytes,
    CaptchaTemplates templates,
  ) {
    final seg = segment(jpegBytes);
    if (seg == null) return null;

    final sb = StringBuffer();
    final scores = <double>[];
    final margins = <double>[];
    String? reason;

    for (final glyph in seg.glyphs) {
      final ranked = templates.rank(glyph.pixels);
      if (ranked.isEmpty) {
        reason = '还没有训练数据';
        sb.write('?');
        scores.add(0);
        margins.add(0);
        continue;
      }
      final best = ranked.first;
      final second = ranked.length > 1 ? ranked[1].value : 0.0;
      sb.write(best.key);
      scores.add(best.value);
      margins.add(best.value - second);
    }

    final ok = reason == null &&
        scores.isNotEmpty &&
        scores.every((s) => s >= minScore) &&
        margins.every((m) => m >= minMargin);
    if (!ok && reason == null) {
      reason = scores.any((s) => s < minScore) ? '字符置信度不足' : '字符容易混淆';
    }
    return CaptchaPrediction(
      ok: ok,
      text: sb.toString(),
      scores: scores,
      margins: margins,
      reason: reason,
    );
  }

  // ---------------------------------------------------------------- 图像

  static _Gray _toGray(img.Image im) {
    final n = im.width * im.height;
    final out = Uint8List(n);
    var i = 0;
    for (var y = 0; y < im.height; y++) {
      for (var x = 0; x < im.width; x++) {
        final p = im.getPixel(x, y);
        final l = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round();
        out[i++] = l < 0 ? 0 : (l > 255 ? 255 : l);
      }
    }
    return _Gray(im.width, im.height, out);
  }

  /// 阈值 + 腐蚀 + 膨胀，得到「粗笔画」掩码（1 = 字）。
  static Uint8List _mask(_Gray g, {int erode = erodeIterations}) {
    final n = g.w * g.h;
    var m = Uint8List(n);
    for (var i = 0; i < n; i++) {
      m[i] = g.data[i] < threshold ? 1 : 0;
    }
    for (var k = 0; k < erode; k++) {
      m = _minFilter(m, g.w, g.h);
    }
    for (var k = 0; k < erode; k++) {
      m = _maxFilter(m, g.w, g.h);
    }
    return m;
  }

  static Uint8List _minFilter(Uint8List src, int w, int h) {
    final out = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var v = 1;
        for (var dy = -1; dy <= 1 && v == 1; dy++) {
          final yy = y + dy;
          if (yy < 0 || yy >= h) {
            v = 0;
            break;
          }
          for (var dx = -1; dx <= 1; dx++) {
            final xx = x + dx;
            if (xx < 0 || xx >= w || src[yy * w + xx] == 0) {
              v = 0;
              break;
            }
          }
        }
        out[y * w + x] = v;
      }
    }
    return out;
  }

  static Uint8List _maxFilter(Uint8List src, int w, int h) {
    final out = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var v = 0;
        for (var dy = -1; dy <= 1 && v == 0; dy++) {
          final yy = y + dy;
          if (yy < 0 || yy >= h) continue;
          for (var dx = -1; dx <= 1; dx++) {
            final xx = x + dx;
            if (xx < 0 || xx >= w) continue;
            if (src[yy * w + xx] == 1) {
              v = 1;
              break;
            }
          }
        }
        out[y * w + x] = v;
      }
    }
    return out;
  }

  /// 连通域切字，返回 [x0, y0, x1, y1]（右/下开区间），按 x 排序。
  static List<List<int>> _boxes(Uint8List m, int w, int h) {
    final seen = Uint8List(w * h);
    final out = <List<int>>[];
    final stack = <int>[];
    for (var start = 0; start < m.length; start++) {
      if (m[start] == 0 || seen[start] == 1) continue;
      seen[start] = 1;
      stack
        ..clear()
        ..add(start);
      var x0 = w, y0 = h, x1 = 0, y1 = 0, area = 0;
      while (stack.isNotEmpty) {
        final idx = stack.removeLast();
        final x = idx % w, y = idx ~/ w;
        area++;
        if (x < x0) x0 = x;
        if (y < y0) y0 = y;
        if (x + 1 > x1) x1 = x + 1;
        if (y + 1 > y1) y1 = y + 1;
        for (var dy = -1; dy <= 1; dy++) {
          final yy = y + dy;
          if (yy < 0 || yy >= h) continue;
          for (var dx = -1; dx <= 1; dx++) {
            final xx = x + dx;
            if (xx < 0 || xx >= w) continue;
            final j = yy * w + xx;
            if (m[j] == 1 && seen[j] == 0) {
              seen[j] = 1;
              stack.add(j);
            }
          }
        }
      }
      if (area < minArea) continue;
      if (y1 - y0 < minHeight || x1 - x0 < minWidth) continue;
      out.add([x0, y0, x1, y1]);
    }
    out.sort((a, b) => a[0].compareTo(b[0]));
    return out;
  }

  static double _centerAngle(List<List<int>> bs) {
    if (bs.length < 3) return 0;
    var mx = 0.0, my = 0.0;
    for (final b in bs) {
      mx += (b[0] + b[2]) / 2.0;
      my += (b[1] + b[3]) / 2.0;
    }
    mx /= bs.length;
    my /= bs.length;
    var sxy = 0.0, sxx = 0.0;
    for (final b in bs) {
      final dx = (b[0] + b[2]) / 2.0 - mx;
      final dy = (b[1] + b[3]) / 2.0 - my;
      sxy += dx * dy;
      sxx += dx * dx;
    }
    if (sxx.abs() < 1e-6) return 0;
    return math.atan(sxy / sxx) * 180.0 / math.pi;
  }

  static double _residualAfter(_Gray g, double angle) {
    final r = _rotate(g, angle);
    return _centerAngle(_boxes(_mask(r), r.w, r.h)).abs();
  }

  /// 双线性旋转（逆映射），空白填浅色以贴合原图背景。
  static _Gray _rotate(_Gray g, double deg) {
    final rad = deg * math.pi / 180.0;
    final ca = math.cos(rad), sa = math.sin(rad);
    final cx = (g.w - 1) / 2.0, cy = (g.h - 1) / 2.0;
    final out = Uint8List(g.w * g.h);
    for (var y = 0; y < g.h; y++) {
      for (var x = 0; x < g.w; x++) {
        final dx = x - cx, dy = y - cy;
        final sx = ca * dx + sa * dy + cx;
        final sy = -sa * dx + ca * dy + cy;
        out[y * g.w + x] = _bilinear(g, sx, sy, 240);
      }
    }
    return _Gray(g.w, g.h, out);
  }

  static int _bilinear(_Gray g, double x, double y, int fill) {
    if (x < 0 || y < 0 || x > g.w - 1 || y > g.h - 1) return fill;
    final x0 = x.floor(), y0 = y.floor();
    final x1 = math.min(x0 + 1, g.w - 1), y1 = math.min(y0 + 1, g.h - 1);
    final fx = x - x0, fy = y - y0;
    final p00 = g.data[y0 * g.w + x0], p10 = g.data[y0 * g.w + x1];
    final p01 = g.data[y1 * g.w + x0], p11 = g.data[y1 * g.w + x1];
    final v = p00 * (1 - fx) * (1 - fy) +
        p10 * fx * (1 - fy) +
        p01 * (1 - fx) * fy +
        p11 * fx * fy;
    return v.round().clamp(0, 255);
  }

  /// 裁字 → 反色 → 归一化 → 补成正方形 → 缩放到 24x24 → 去均值单位化。
  static Float32List _normalize(_Gray g, List<int> box) {
    final x0 = box[0], y0 = box[1];
    final bw = box[2] - x0, bh = box[3] - y0;
    final crop = Float32List(bw * bh);
    var maxV = 0.0;
    for (var y = 0; y < bh; y++) {
      for (var x = 0; x < bw; x++) {
        final v = 255.0 - g.data[(y0 + y) * g.w + (x0 + x)];
        crop[y * bw + x] = v;
        if (v > maxV) maxV = v;
      }
    }
    if (maxV <= 0) maxV = 1;
    final side = math.max(bw, bh);
    final padX = (side - bw) ~/ 2, padY = (side - bh) ~/ 2;
    final out = Float32List(glyphSize * glyphSize);
    for (var y = 0; y < glyphSize; y++) {
      for (var x = 0; x < glyphSize; x++) {
        // 目标像素映射回正方形内的浮点坐标
        final sx = (x + 0.5) * side / glyphSize - padX - 0.5;
        final sy = (y + 0.5) * side / glyphSize - padY - 0.5;
        var v = 0.0;
        if (sx >= 0 && sy >= 0 && sx <= bw - 1 && sy <= bh - 1) {
          final ix = sx.floor(), iy = sy.floor();
          final ix1 = math.min(ix + 1, bw - 1), iy1 = math.min(iy + 1, bh - 1);
          final fx = sx - ix, fy = sy - iy;
          v = crop[iy * bw + ix] * (1 - fx) * (1 - fy) +
              crop[iy * bw + ix1] * fx * (1 - fy) +
              crop[iy1 * bw + ix] * (1 - fx) * fy +
              crop[iy1 * bw + ix1] * fx * fy;
        }
        out[y * glyphSize + x] = (v / maxV * 255.0);
      }
    }
    return out;
  }

  /// 把 24x24 像素向量变成「去均值 + 单位化」的向量，便于直接点积当相关分。
  static Float32List unit(Float32List pixels) {
    final out = Float32List.fromList(pixels);
    var mean = 0.0;
    for (final v in out) {
      mean += v;
    }
    mean /= out.length;
    var norm = 0.0;
    for (var i = 0; i < out.length; i++) {
      out[i] -= mean;
      norm += out[i] * out[i];
    }
    norm = math.sqrt(norm);
    if (norm > 0) {
      for (var i = 0; i < out.length; i++) {
        out[i] /= norm;
      }
    }
    return out;
  }

  /// 像素向量存成 base64（0~255 正好一个字节）。
  static String encodePixels(Float32List pixels) {
    final bytes = Uint8List(pixels.length);
    for (var i = 0; i < pixels.length; i++) {
      final v = pixels[i].round();
      bytes[i] = v < 0 ? 0 : (v > 255 ? 255 : v);
    }
    return base64Encode(bytes);
  }

  static Float32List decodePixels(String text) {
    final bytes = base64Decode(text);
    final out = Float32List(bytes.length);
    for (var i = 0; i < bytes.length; i++) {
      out[i] = bytes[i].toDouble();
    }
    return out;
  }
}
