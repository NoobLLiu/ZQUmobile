/// 验证码识别用的字形模板：样本存储 + 聚类质心 + 排序打分。
///
/// 样本来源有两个：
///   1. **内置预置训练集**（`assets/captcha_templates.json`，由 90 张真实验证码
///      视觉标注构建）——首次启动自动播种到本机；
///   2. 用户自己的样本——登录成功自动回流 + 训练页手输，存在本机
///      `shared_preferences`，不上传。
///
/// 排序用**多质心**：同一字符在不同图里笔画轻重不同，单质心会把这些变体
/// 平均成一个「四不像」，导致分数偏低、过不了置信度门禁。按类做确定性
/// k-means（k≤3），匹配时取该类各质心里最高的分，覆盖率和精度都明显更好。
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import 'captcha_ocr.dart';

/// 一个字符的样本集合与质心缓存。
class _ClassSamples {
  final List<Float32List> pixels = [];
  List<Float32List>? centroids;

  void invalidate() => centroids = null;
}

/// 字形模板集。
class CaptchaTemplates {
  CaptchaTemplates();

  final Map<String, _ClassSamples> _classes = {};

  /// 每个字符最多保留多少张样本。
  ///
  /// 超出丢最旧；不设上限会让本地存储无限增长
  /// （单样本 base64 后约 0.8KB，31 类 × 15 张 ≈ 400KB，可控）。
  static const int maxPerClass = 15;

  /// 按样本数决定簇数：≥9 拆 3 簇，≥5 拆 2 簇，否则 1 簇。
  static int clusterCountFor(int n) => n >= 9 ? 3 : (n >= 5 ? 2 : 1);

  /// 样本总数。
  int get sampleCount =>
      _classes.values.fold(0, (sum, c) => sum + c.pixels.length);

  /// 已覆盖的字符数。
  int get classCount => _classes.length;

  /// 每个字符的样本数（用于训练页进度）。
  Map<String, int> get counts =>
      {for (final e in _classes.entries) e.key: e.value.pixels.length};

  bool get isEmpty => _classes.isEmpty;

  /// 加一个样本（超过上限丢最旧的）。
  void add(String ch, Float32List pixels) {
    final c = _classes.putIfAbsent(ch, _ClassSamples.new);
    c.pixels.add(pixels);
    if (c.pixels.length > maxPerClass) c.pixels.removeAt(0);
    c.invalidate();
  }

  /// 把另一套模板的样本并进来（预置集 + 用户样本合并时用）。
  void merge(CaptchaTemplates other) {
    for (final e in other._classes.entries) {
      for (final p in e.value.pixels) {
        add(e.key, p);
      }
    }
  }

  static int get _glyphLen => CaptchaOcr.glyphSize * CaptchaOcr.glyphSize;

  /// 确定性 k-means（最远点初始化，无随机性，同输入必同输出）。
  static List<Float32List> _kmeans(List<Float32List> units, int k) {
    final len = _glyphLen;

    Float32List meanOf(List<double> acc) {
      var norm = 0.0;
      final out = Float32List(len);
      for (var i = 0; i < len; i++) {
        out[i] = acc[i];
        norm += out[i] * out[i];
      }
      norm = math.sqrt(norm);
      if (norm > 0) {
        for (var i = 0; i < len; i++) {
          out[i] /= norm;
        }
      }
      return out;
    }

    if (k <= 1 || units.length <= k) {
      final acc = Float64List(len);
      for (final u in units) {
        for (var i = 0; i < len; i++) {
          acc[i] += u[i];
        }
      }
      return [meanOf(acc)];
    }

    // 最远点初始化
    final seeds = <Float32List>[units[0]];
    while (seeds.length < k) {
      Float32List? best;
      var bestD = -1.0;
      for (final u in units) {
        var nearest = 2.0;
        for (final s in seeds) {
          var dot = 0.0;
          for (var i = 0; i < len; i++) {
            dot += u[i] * s[i];
          }
          final dist = 1 - dot;
          if (dist < nearest) nearest = dist;
        }
        if (nearest > bestD) {
          bestD = nearest;
          best = u;
        }
      }
      if (best == null || bestD <= 1e-6) break;
      seeds.add(best);
    }

    var cents = seeds.map((s) => Float32List.fromList(s)).toList();
    for (var iter = 0; iter < 8; iter++) {
      final acc = List.generate(cents.length, (_) => Float64List(len));
      final cnt = List<int>.filled(cents.length, 0);
      for (final u in units) {
        var bi = 0;
        var bs = -2.0;
        for (var c = 0; c < cents.length; c++) {
          var dot = 0.0;
          for (var i = 0; i < len; i++) {
            dot += u[i] * cents[c][i];
          }
          if (dot > bs) {
            bs = dot;
            bi = c;
          }
        }
        for (var i = 0; i < len; i++) {
          acc[bi][i] += u[i];
        }
        cnt[bi]++;
      }
      final next = <Float32List>[];
      for (var c = 0; c < cents.length; c++) {
        if (cnt[c] == 0) continue; // 空簇丢弃
        next.add(meanOf(acc[c]));
      }
      cents = next;
      if (cents.length <= 1) break;
    }
    return cents;
  }

  /// 某字符的质心列表（单位向量）。[skipIndex] 为该类样本内的下标（留一用）。
  List<Float32List>? centroidsOf(String ch, {int? skipIndex}) {
    final c = _classes[ch];
    if (c == null || c.pixels.isEmpty) return null;
    if (skipIndex == null && c.centroids != null) return c.centroids;

    final units = <Float32List>[];
    for (var i = 0; i < c.pixels.length; i++) {
      if (i == skipIndex) continue;
      units.add(CaptchaOcr.unit(c.pixels[i]));
    }
    if (units.isEmpty) return null;
    final cents = _kmeans(units, clusterCountFor(units.length));
    if (skipIndex == null) c.centroids = cents;
    return cents;
  }

  /// 某字符的单质心（兼容旧调用）。
  Float32List? centroidOf(String ch, {int? skipIndex}) {
    final cents = centroidsOf(ch, skipIndex: skipIndex);
    if (cents == null || cents.isEmpty) return null;
    return cents.first;
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
    for (final e in _classes.entries) {
      final ch = e.key;
      final c = e.value;
      final available =
          c.pixels.length - (ch == skipChar && skipIndex != null ? 1 : 0);
      if (available < minSamples) continue;
      final cents =
          centroidsOf(ch, skipIndex: ch == skipChar ? skipIndex : null);
      if (cents == null || cents.isEmpty) continue;
      var best = -2.0;
      for (final cent in cents) {
        var s = 0.0;
        for (var i = 0; i < u.length; i++) {
          s += u[i] * cent[i];
        }
        if (s > best) best = s;
      }
      out.add(MapEntry(ch, best));
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
        'v': 2,
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

/// 模板的本地存储 + 预置训练集播种。
class CaptchaTemplateRepository {
  CaptchaTemplateRepository._();

  static const String _key = 'zsy_captcha_templates';

  /// 预置训练集（内置资产，构建脚本从真实标注样本生成）。
  static const String assetPath = 'assets/captcha_templates.json';

  /// 是否已经播过种（播一次即可；用户清空后不再复活）。
  static const String _seededKey = 'zsy_captcha_seeded';

  /// 不做静态缓存：训练页写入后登录页要立刻读到新模板。
  static Future<CaptchaTemplates> load() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_key);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          final t = CaptchaTemplates.fromJson(decoded);
          if (t.sampleCount > 0) return t;
        }
      } catch (_) {
        /* 损坏则走播种/空模板 */
      }
    }

    // 本地没有样本：第一次启动时播种预置训练集
    if (!(sp.getBool(_seededKey) ?? false)) {
      try {
        final assetRaw = await rootBundle.loadString(assetPath);
        final decoded = jsonDecode(assetRaw);
        if (decoded is Map<String, dynamic>) {
          final t = CaptchaTemplates.fromJson(decoded);
          if (t.sampleCount > 0) {
            await sp.setString(_key, jsonEncode(t.toJson()));
            await sp.setBool(_seededKey, true);
            return t;
          }
        }
      } catch (_) {
        /* 资产缺失（如部分单测环境）就当没有预置集 */
      }
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
    // 不重置 _seededKey：用户明确清空后，预置集也不复活
  }
}
