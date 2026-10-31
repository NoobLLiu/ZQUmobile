/// 验证码识别用的字形模板：样本存储 + 质心计算 + 排序打分。
///
/// 模板完全来自用户自己在训练页手输的验证码（登录成功即标签正确），
/// 只存在本机 `shared_preferences`，不上传。
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import 'captcha_ocr.dart';

/// 一个字符的样本集合与质心。
class _ClassSamples {
  final List<Float32List> pixels = [];
  Float32List? centroid;

  void invalidate() => centroid = null;
}

/// 字形模板集。
class CaptchaTemplates {
  CaptchaTemplates();

  /// 每个字符最多保留多少张样本。
  ///
  /// 质心取平均，12 张已经远超收益；不设上限会让本地存储无限增长
  /// （单样本 base64 后约 0.8KB，36 类 × 无限张很快就到几百 KB）。
  static const int maxPerClass = 12;

  final Map<String, _ClassSamples> _classes = {};

  /// 样本总数。
  int get sampleCount =>
      _classes.values.fold(0, (sum, c) => sum + c.pixels.length);

  /// 已覆盖的字符数。
  int get classCount => _classes.length;

  /// 每个字符的样本数（用于训练页进度）。
  Map<String, int> get counts =>
      {for (final e in _classes.entries) e.key: e.value.pixels.length};

  bool get isEmpty => _classes.isEmpty;

  /// 加一个样本。
  void add(String ch, Float32List pixels) {
    final c = _classes.putIfAbsent(ch, _ClassSamples.new);
    c.pixels.add(pixels);
    if (c.pixels.length > maxPerClass) c.pixels.removeAt(0);
    c.invalidate();
  }

  /// 某字符的质心（单位向量）。
  Float32List? centroidOf(String ch, {int? skipIndex}) {
    final c = _classes[ch];
    if (c == null || c.pixels.isEmpty) return null;
    if (skipIndex == null && c.centroid != null) return c.centroid;

    final acc = Float64List(CaptchaOcr.glyphSize * CaptchaOcr.glyphSize);
    var used = 0;
    for (var i = 0; i < c.pixels.length; i++) {
      if (i == skipIndex) continue;
      final u = CaptchaOcr.unit(c.pixels[i]);
      for (var j = 0; j < acc.length; j++) {
        acc[j] += u[j];
      }
      used++;
    }
    if (used == 0) return null;
    var norm = 0.0;
    for (final v in acc) {
      norm += v * v;
    }
    norm = math.sqrt(norm);
    if (norm <= 0) return null;
    final out = Float32List(acc.length);
    for (var i = 0; i < acc.length; i++) {
      out[i] = acc[i] / norm;
    }
    if (skipIndex == null) c.centroid = out;
    return out;
  }

  /// 按相关分从高到低排序。样本数少于 [minSamples] 的字符不参与。
  List<MapEntry<String, double>> rank(
    Float32List pixels, {
    int minSamples = 1,
    String? skipChar,
    int? skipIndex,
  }) {
    final u = CaptchaOcr.unit(pixels);
    final out = <MapEntry<String, double>>[];
    for (final ch in _classes.keys) {
      final c = _classes[ch]!;
      final available = c.pixels.length - (ch == skipChar && skipIndex != null ? 1 : 0);
      if (available < minSamples) continue;
      final cent = centroidOf(ch, skipIndex: ch == skipChar ? skipIndex : null);
      if (cent == null) continue;
      var s = 0.0;
      for (var i = 0; i < u.length; i++) {
        s += u[i] * cent[i];
      }
      out.add(MapEntry(ch, s));
    }
    out.sort((a, b) => b.value.compareTo(a.value));
    return out;
  }

  /// 留一自检：对每个样本用它「未参与」的质心去分类，返回 (正确数, 总数)。
  (int, int) leaveOneOut() {
    var correct = 0, total = 0;
    for (final e in _classes.entries) {
      for (var i = 0; i < e.value.pixels.length; i++) {
        final ranked = rank(
          e.value.pixels[i],
          skipChar: e.key,
          skipIndex: i,
        );
        if (ranked.isEmpty) continue;
        total++;
        if (ranked.first.key == e.key) correct++;
      }
    }
    return (correct, total);
  }

  Map<String, dynamic> toJson() => {
        'v': 1,
        'data': {
          for (final e in _classes.entries)
            e.key: e.value.pixels
                .map((p) => CaptchaOcr.encodePixels(p))
                .toList(),
        },
      };

  factory CaptchaTemplates.fromJson(Map<String, dynamic> j) {
    final t = CaptchaTemplates();
    final data = (j['data'] as Map<String, dynamic>?) ?? const {};
    for (final e in data.entries) {
      for (final s in (e.value as List)) {
        try {
          t.add(e.key, CaptchaOcr.decodePixels(s.toString()));
        } catch (_) {
          /* 单条损坏就跳过 */
        }
      }
    }
    return t;
  }
}

/// 模板的本地存储。
class CaptchaTemplateRepository {
  CaptchaTemplateRepository._();

  static const String _key = 'zsy_captcha_templates';

  /// 不做静态缓存：训练页写入后登录页要立刻读到新模板。
  static Future<CaptchaTemplates> load() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_key);
    if (raw == null || raw.isEmpty) return CaptchaTemplates();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return CaptchaTemplates.fromJson(decoded);
      }
    } catch (_) {
      /* 损坏则当作空模板 */
    }
    return CaptchaTemplates();
  }

  static Future<void> save(CaptchaTemplates templates) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_key, jsonEncode(templates.toJson()));
  }

  static Future<void> clear() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_key);
  }
}
