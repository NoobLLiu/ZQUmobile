/// 快递站状态页。
///
/// 按校门分组展示各驿站的实时营业状态：
///   - 绿：营业中；黄：距打烊 / 距开门不足 30 分钟；红：未营业 / 校门已关不可达；灰：数据待补充
/// 分组默认展开，点分组栏的小箭头可折叠；状态随系统时间每 30 秒自动刷新。
///
/// 页面里的**全部内容**（分组、驿站名称、位置、营业时间、备注、底部说明）
/// 都来自 `data/express_stations.json`：出厂时编译进包，进页后由
/// [ExpressStationRepository] 从 Gitee 仓库静默热更新，失败自动回退本地数据。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../models/express_station.dart';
import '../services/express_station_repository.dart';

/// 快递站状态页。
class ExpressStationPage extends StatefulWidget {
  const ExpressStationPage({super.key, this.clock, this.repository});

  /// 当前时间来源，测试时可注入固定时间。
  final DateTime Function()? clock;

  /// 数据仓库，测试时可注入不发网络的实例。
  final ExpressStationRepository? repository;

  @override
  State<ExpressStationPage> createState() => _ExpressStationPageState();
}

class _ExpressStationPageState extends State<ExpressStationPage> {
  late DateTime _now;
  late ExpressStationData _data;
  ExpressStationSource _source = ExpressStationSource.bundled;
  bool _updating = false;

  /// 各分组是否展开（默认全展开；新增分组也默认展开）。
  final Map<String, bool> _expanded = {};

  Timer? _timer;

  ExpressStationRepository get _repo =>
      widget.repository ?? ExpressStationRepository.instance;

  DateTime _clock() => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _now = _clock();
    // 首帧直接用出厂内置快照，不等网络；随后静默替换成缓存/在线数据。
    _data = _repo.bundled;
    for (final g in _data.groups) {
      _expanded[g.name] = true;
    }
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = _clock());
    });
    unawaited(_load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    try {
      final result = await _repo.load(forceRefresh: forceRefresh);
      if (!mounted) return;
      setState(() {
        _data = result.data;
        _source = result.source;
      });
    } catch (_) {
      // 任何异常都保留首帧的出厂数据，页面不空、不报错。
    }
  }

  void _refreshNow() => setState(() => _now = _clock());

  /// AppBar 的「更新数据」按钮：强制联网拉一次，并给出结果提示。
  Future<void> _updateData() async {
    if (_updating) return;
    setState(() => _updating = true);
    ExpressStationLoadResult? result;
    try {
      result = await _repo.load(forceRefresh: true);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      if (result != null) {
        _data = result.data;
        _source = result.source;
      }
      _now = _clock();
      _updating = false;
    });
    String message;
    if (result == null || result.error != null) {
      message = '在线更新失败，已显示本地数据';
    } else if (result.gotUpdate) {
      message = '快递站数据已更新到 r${result.data.revision}';
    } else {
      message = '已是最新数据（r${result.data.revision}）';
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('快递站状态'),
        actions: [
          IconButton(
            tooltip: '立即刷新',
            onPressed: _refreshNow,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: '更新快递站数据',
            onPressed: _updating ? null : _updateData,
            icon: _updating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_download_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          const _LegendBar(),
          const SizedBox(height: 12),
          for (final group in _data.groups) ...[
            _GroupSection(
              group: group,
              now: _now,
              expanded: _expanded[group.name] ?? true,
              onToggle: () => setState(
                () => _expanded[group.name] =
                    !(_expanded[group.name] ?? true),
              ),
              onStationTap: (station) => _showDetails(group, station),
            ),
            const SizedBox(height: 12),
          ],
          Text(
            _data.notice,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '数据 r${_data.revision} · ${_data.updatedAt} · ${_sourceLabel(_source)}',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  String _sourceLabel(ExpressStationSource source) => switch (source) {
        ExpressStationSource.bundled => '出厂内置',
        ExpressStationSource.cache => '本地缓存',
        ExpressStationSource.remote => '在线更新',
      };

  /// 点卡片看完整信息：位置、营业时间、备注等都可以随 JSON 热更新。
  void _showDetails(ExpressStationGroup group, ExpressStation station) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _StationDetailSheet(
        group: group,
        station: station,
        now: _now,
        revision: _data.revision,
        updatedAt: _data.updatedAt,
      ),
    );
  }
}

/// 顶部图例条：状态色说明（不显示当前时间，页面后台每 30 秒静默刷新）。
class _LegendBar extends StatelessWidget {
  const _LegendBar();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Wrap(
        alignment: WrapAlignment.center,
        spacing: 12,
        runSpacing: 6,
        children: [
          _LegendDot(color: _kGreenBase, label: '营业'),
          // 黄色同时代表「快开门」和「快打烊」，两个状态各列一项。
          _LegendDot(color: _kAmberBase, label: '将营业'),
          _LegendDot(color: _kAmberBase, label: '将打烊'),
          _LegendDot(color: _kRedBase, label: '未营业'),
          _LegendDot(color: _kGrayBase, label: '待补充'),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 3),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      ],
    );
  }
}

/// 一个分组：可折叠的分组栏 + 组内驿站卡片（一行两个）。
class _GroupSection extends StatelessWidget {
  const _GroupSection({
    required this.group,
    required this.now,
    required this.expanded,
    required this.onToggle,
    required this.onStationTap,
  });

  final ExpressStationGroup group;
  final DateTime now;
  final bool expanded;
  final VoidCallback onToggle;
  final void Function(ExpressStation station) onStationTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(
              children: [
                Icon(
                  Icons.location_on_outlined,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  group.name,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                if (group.gateHours != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    '校门开放 ${group.gateHours!.format()}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                ],
                const Spacer(),
                AnimatedRotation(
                  turns: expanded ? 0 : 0.5,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.expand_more,
                    size: 22,
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: expanded
              ? GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.15,
                  children: [
                    for (final station in group.stations)
                      _StationCard(
                        group: group,
                        station: station,
                        now: now,
                        result: evaluateExpressStation(
                          station,
                          now,
                          gateHours: group.gateHours,
                        ),
                        onTap: () => onStationTap(station),
                      ),
                  ],
                )
              : const SizedBox(width: double.infinity, height: 0),
        ),
      ],
    );
  }
}

// 状态基准色（卡片底色 / 边框 / 图例用），文字色随明暗主题单独取。
const Color _kRedBase = Color(0xFFE5484D);
const Color _kAmberBase = Color(0xFFE8A33D);
const Color _kGreenBase = Color(0xFF3BB273);
const Color _kGrayBase = Color(0xFF9AA1AC);

/// 单个驿站卡片。
class _StationCard extends StatelessWidget {
  const _StationCard({
    required this.group,
    required this.station,
    required this.now,
    required this.result,
    required this.onTap,
  });

  final ExpressStationGroup group;
  final ExpressStation station;
  final DateTime now;
  final ExpressStatusResult result;
  final VoidCallback onTap;

  /// 今日是否有按星期的特殊时间（有则展示「今日 xx-xx」）。
  bool get _hasOverride =>
      station.weekdayHours.containsKey(now.weekday) && station.hasData;

  /// 是否有位置或备注可展开查看。
  bool get _hasDetails =>
      station.location.isNotEmpty ||
      station.note.isNotEmpty ||
      group.location.isNotEmpty ||
      group.note.isNotEmpty;

  Color get _baseColor => switch (result.status) {
        ExpressStatus.open => _kGreenBase,
        ExpressStatus.closingSoon => _kAmberBase,
        ExpressStatus.openingSoon => _kAmberBase,
        ExpressStatus.closed => _kRedBase,
        ExpressStatus.unreachable => _kRedBase,
        ExpressStatus.noData => _kGrayBase,
      };

  Color _textColor(Brightness brightness) => switch (result.status) {
        ExpressStatus.open => brightness == Brightness.light
            ? const Color(0xFF1E8E5A)
            : const Color(0xFF5BC98C),
        ExpressStatus.closingSoon => brightness == Brightness.light
            ? const Color(0xFFB45309)
            : const Color(0xFFF0B454),
        ExpressStatus.openingSoon => brightness == Brightness.light
            ? const Color(0xFFB45309)
            : const Color(0xFFF0B454),
        ExpressStatus.closed => brightness == Brightness.light
            ? const Color(0xFFCC3A3F)
            : const Color(0xFFF07A7A),
        ExpressStatus.unreachable => brightness == Brightness.light
            ? const Color(0xFFCC3A3F)
            : const Color(0xFFF07A7A),
        ExpressStatus.noData => brightness == Brightness.light
            ? const Color(0xFF7C838D)
            : const Color(0xFF9AA1AC),
      };

  /// 状态行文字。
  String get _statusLabel {
    final hours = result.hours;
    switch (result.status) {
      case ExpressStatus.open:
        return '营业中';
      case ExpressStatus.closingSoon:
        return '即将打烊 · 剩 ${result.minutesToClose} 分钟';
      case ExpressStatus.openingSoon:
        return '即将营业 · 还有 ${result.minutesToOpen} 分钟';
      case ExpressStatus.closed:
        final minutes = now.hour * 60 + now.minute;
        if (hours != null && minutes < hours.open) {
          final h = hours.open ~/ 60;
          final m = hours.open % 60;
          final hhmm =
              '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
          return '未营业 · $hhmm 开门';
        }
        return '已打烊';
      case ExpressStatus.unreachable:
        return '不可达 · 校门已关';
      case ExpressStatus.noData:
        return '数据待补充';
    }
  }

  /// 营业时间行文字。
  String get _hoursLabel {
    final hours = result.hours;
    if (hours == null) return '营业时间待录入';
    return _hasOverride ? '今日 ${hours.format()}' : hours.format();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = _textColor(theme.brightness);
    final base = _baseColor;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: base.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: base.withValues(alpha: 0.5), width: 1.2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    station.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (_hasDetails)
                  Icon(
                    Icons.info_outline,
                    size: 14,
                    color: theme.colorScheme.outline,
                  ),
              ],
            ),
            const Spacer(),
            Text(
              _statusLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: textColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              _hoursLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 卡片详情：位置、营业时间、按星期特例、备注等完整信息。
class _StationDetailSheet extends StatelessWidget {
  const _StationDetailSheet({
    required this.group,
    required this.station,
    required this.now,
    required this.revision,
    required this.updatedAt,
  });

  final ExpressStationGroup group;
  final ExpressStation station;
  final DateTime now;
  final int revision;
  final String updatedAt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = evaluateExpressStation(
      station,
      now,
      gateHours: group.gateHours,
    );
    final rows = <MapEntry<String, String>>[
      MapEntry('所属分组', group.name),
      if (group.location.isNotEmpty) MapEntry('分组位置', group.location),
      if (station.location.isNotEmpty) MapEntry('具体位置', station.location),
      MapEntry(
        '营业时间',
        result.hours?.format() ?? '待补充',
      ),
      if (station.weekdayHours.isNotEmpty)
        MapEntry(
          '特殊安排',
          [
            for (final e in station.weekdayHours.entries)
              '周${_weekdayName(e.key)} ${e.value.format()}',
          ].join('；'),
        ),
      if (group.gateHours != null)
        MapEntry('校门开放', group.gateHours!.format()),
      if (station.note.isNotEmpty) MapEntry('备注', station.note),
      if (group.note.isNotEmpty) MapEntry('分组提示', group.note),
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                station.name,
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 14),
              for (final row in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 72,
                        child: Text(
                          row.key,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          row.value.isEmpty ? '待补充' : row.value,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 4),
              Text(
                '数据 r$revision · $updatedAt（可在「更新快递站数据」中刷新）',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const List<String> _weekdayNames = <String>[
  '',
  '一',
  '二',
  '三',
  '四',
  '五',
  '六',
  '日',
];

String _weekdayName(int weekday) =>
    weekday >= 1 && weekday <= 7 ? _weekdayNames[weekday] : '$weekday';
