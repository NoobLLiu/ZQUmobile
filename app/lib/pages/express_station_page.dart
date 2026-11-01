/// 快递站状态页。
///
/// 按校门分组展示各驿站的实时营业状态：
///   - 绿：营业中；黄：距打烊不足 30 分钟；红：未营业 / 校门已关不可达；灰：数据待补充
/// 分组默认展开，点分组栏的小箭头可折叠；状态随系统时间每 30 秒自动刷新。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../models/express_station.dart';

/// 快递站状态页。
class ExpressStationPage extends StatefulWidget {
  const ExpressStationPage({super.key, this.clock});

  /// 当前时间来源，测试时可注入固定时间。
  final DateTime Function()? clock;

  @override
  State<ExpressStationPage> createState() => _ExpressStationPageState();
}

class _ExpressStationPageState extends State<ExpressStationPage> {
  late DateTime _now;

  /// 各分组是否展开（默认全展开）。
  final Map<String, bool> _expanded = {
    for (final g in kExpressStationGroups) g.name: true,
  };

  Timer? _timer;

  DateTime _clock() => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _now = _clock();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = _clock());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _refreshNow() => setState(() => _now = _clock());

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
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _TimeBanner(now: _now),
          const SizedBox(height: 12),
          for (final group in kExpressStationGroups) ...[
            _GroupSection(
              group: group,
              now: _now,
              expanded: _expanded[group.name] ?? true,
              onToggle: () => setState(
                () => _expanded[group.name] = !(_expanded[group.name] ?? true),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Text(
            '营业时间为预先录入的公示时间，以驿站现场公告为准；'
            '「南门车库驿站」等数据待补充，欢迎反馈。',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}

/// 顶部时间条：当前时间 + 状态色图例。
class _TimeBanner extends StatelessWidget {
  const _TimeBanner({required this.now});

  final DateTime now;

  static const _weekdayNames = [
    '周一',
    '周二',
    '周三',
    '周四',
    '周五',
    '周六',
    '周日',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    String p(int n) => n.toString().padLeft(2, '0');
    final weekday = _weekdayNames[now.weekday - 1];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.schedule, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '现在 ${p(now.hour)}:${p(now.minute)}（$weekday）· 每 30 秒自动刷新',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          _LegendDot(color: _kGreenBase, label: '营业'),
          const SizedBox(width: 4),
          _LegendDot(color: _kAmberBase, label: '将打烊'),
          const SizedBox(width: 4),
          _LegendDot(color: _kRedBase, label: '未营业'),
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
  });

  final ExpressStationGroup group;
  final DateTime now;
  final bool expanded;
  final VoidCallback onToggle;

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
                        station: station,
                        now: now,
                        result: evaluateExpressStation(
                          station,
                          now,
                          gateHours: group.gateHours,
                        ),
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
    required this.station,
    required this.now,
    required this.result,
  });

  final ExpressStation station;
  final DateTime now;
  final ExpressStatusResult result;

  /// 今日是否有按星期的特殊时间（有则展示「今日 xx-xx」）。
  bool get _hasOverride =>
      station.weekdayHours.containsKey(now.weekday) && station.hasData;

  Color get _baseColor => switch (result.status) {
        ExpressStatus.open => _kGreenBase,
        ExpressStatus.closingSoon => _kAmberBase,
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

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: base.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: base.withValues(alpha: 0.5), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            station.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
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
    );
  }
}
