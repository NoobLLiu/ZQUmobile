// 从唯一数据源 data/express_stations.json 生成 App 的出厂初始数据。
//
// 用法：dart tool/gen_express_stations.dart [--check]
//   （无参数）写出 app/assets/express_stations.json 与
//             app/lib/generated/express_stations_bundled.dart，内容没变则不重写。
//   --check   只校验数据源是否合法、生成物是否最新，不写文件（CI 可选用）。
//
// 只用 dart:io / dart:convert，不需要 pub get，CI 与本机都能直接跑。
import 'dart:convert';
import 'dart:io';

const _relativeSource = 'data/express_stations.json';
const _relativeAsset = 'app/assets/express_stations.json';
const _relativeDart = 'app/lib/generated/express_stations_bundled.dart';

final _hhmmRange = RegExp(r'^\d{1,2}:\d{2}-\d{1,2}:\d{2}$');

void main(List<String> args) {
  final checkOnly = args.contains('--check');
  try {
    final root = _findRepoRoot();
    final source = File('${root.path}/$_relativeSource');
    final raw = source.readAsStringSync();

    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('顶层必须是 JSON 对象');
    }
    _validate(decoded);

    // 规范化一份（去 CRLF、统一缩进），保证源文件 / asset / 内置快照三者逐字一致。
    final normalized =
        '${const JsonEncoder.withIndent('  ').convert(decoded)}\n';
    if (normalized.contains("'''")) {
      throw const FormatException('数据里不能包含三个连续单引号（会截断 Dart 原始字符串）');
    }

    final dartSource = _dartSource(normalized);
    final targets = <String, String>{
      _relativeSource: normalized,
      _relativeAsset: normalized,
      _relativeDart: dartSource,
    };

    var changed = 0;
    for (final entry in targets.entries) {
      final file = File('${root.path}/${entry.key}');
      final current = file.existsSync() ? file.readAsStringSync() : null;
      if (current == entry.value) continue;
      changed++;
      if (checkOnly) {
        stderr.writeln('生成物不是最新的：${entry.key}');
        continue;
      }
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(entry.value);
      stdout.writeln('已写入 ${entry.key}');
    }

    if (checkOnly && changed > 0) {
      stderr.writeln('请运行：dart tool/gen_express_stations.dart');
      exit(1);
    }
    stdout.writeln(checkOnly
        ? '校验通过：数据合法且生成物均为最新'
        : '快递站数据已合入（revision ${decoded['revision']}，${decoded['updatedAt']}）');
  } catch (e) {
    stderr.writeln('生成快递站数据失败：$e');
    exit(1);
  }
}

/// 从脚本位置或当前工作目录向上找仓库根（CI 的 cwd 是 app/）。
Directory _findRepoRoot() {
  final starts = <Directory>[
    Directory(Platform.script.toFilePath()).parent,
    Directory.current,
  ];
  for (final start in starts) {
    var dir = start;
    for (var i = 0; i < 5; i++) {
      if (File('${dir.path}/$_relativeSource').existsSync()) return dir;
      dir = dir.parent;
    }
  }
  throw StateError('找不到 $_relativeSource');
}

void _validate(Map<String, dynamic> data) {
  final schema = (data['schemaVersion'] as num?)?.toInt();
  if (schema != 1) {
    throw FormatException('schemaVersion 只支持 1，实际 $schema');
  }
  final revision = (data['revision'] as num?)?.toInt();
  if (revision == null || revision < 1) {
    throw const FormatException('revision 必须是 >=1 的整数（每次改数据请 +1）');
  }
  if ((data['updatedAt'] as String? ?? '').trim().isEmpty) {
    throw const FormatException('updatedAt 不能为空');
  }
  if (data['notice'] is! String) {
    throw const FormatException('notice 必须是字符串');
  }

  final groups = data['groups'];
  if (groups is! List || groups.isEmpty) {
    throw const FormatException('groups 必须是非空数组');
  }
  final ids = <String>{};
  for (final raw in groups) {
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('groups 里每一项必须是对象');
    }
    if ((raw['name'] as String? ?? '').trim().isEmpty) {
      throw const FormatException('分组 name 不能为空');
    }
    _checkTime(raw['gateHours'], '${raw['name']} 的 gateHours');
    final stations = raw['stations'];
    if (stations is! List) {
      throw FormatException('${raw['name']} 缺少 stations 数组');
    }
    for (final station in stations) {
      if (station is! Map<String, dynamic>) {
        throw const FormatException('stations 里每一项必须是对象');
      }
      final name = (station['name'] as String? ?? '').trim();
      if (name.isEmpty) throw const FormatException('驿站 name 不能为空');
      _checkTime(station['hours'], '$name 的 hours');
      final overrides = station['weekdayHours'];
      if (overrides != null) {
        if (overrides is! Map) {
          throw FormatException('$name 的 weekdayHours 必须是对象');
        }
        overrides.forEach((key, value) {
          final day = int.tryParse(key.toString());
          if (day == null || day < 1 || day > 7) {
            throw FormatException('$name 的 weekdayHours 键必须是 1~7：$key');
          }
          _checkTime(value, '$name 周$day 时间');
        });
      }
      final id = station['id'] as String?;
      if (id != null && !ids.add(id)) {
        throw FormatException('驿站 id 重复：$id');
      }
    }
  }
}

void _checkTime(Object? value, String label) {
  if (value == null) return;
  final text = value.toString().trim();
  if (!_hhmmRange.hasMatch(text)) {
    throw FormatException('$label 应为 HH:mm-HH:mm，实际：$text');
  }
  final parts = text.split('-');
  for (final part in parts) {
    final hm = part.split(':');
    final h = int.parse(hm[0]);
    final m = int.parse(hm[1]);
    if (h < 0 || h > 23 || m < 0 || m > 59) {
      throw FormatException('$label 时间越界：$text');
    }
  }
}

String _dartSource(String json) => '''// GENERATED FILE - DO NOT EDIT.
// 由 tool/gen_express_stations.dart 从 data/express_stations.json 生成。
// CI 每次编译前会重新生成，保证出厂包里带的是最新快递站数据。
library;

/// 编译期内置的快递站数据快照（出厂初始值，可被热更新覆盖）。
const String kBundledExpressStationJson = r\'\'\'
$json\'\'\';
''';
