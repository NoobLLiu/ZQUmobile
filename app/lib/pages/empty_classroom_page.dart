/// 空教室查询页。
///
/// 数据来自「扫描教室」采集的班级课表排课记录（见 zqu_room_scan.js），
/// 查询完全在本机完成：选楼栋 + 日期 + 节次，从内置教室目录里
/// 找出该时段没有任何排课的教室。
///
/// 交互约定与课表导入一致：扫描、查询都由用户手动触发，不自动刷新。
library;

import 'package:flutter/material.dart';

import '../models/empty_classroom.dart';
import '../models/timetable.dart';
import '../services/classroom_directory.dart';
import '../services/empty_room_query.dart';
import '../services/jwgl_service.dart';
import '../services/room_scan_repository.dart';
import '../services/timetable_repository.dart';
import 'jwgl_login_page.dart';

/// 空教室查询页。
class EmptyClassroomPage extends StatefulWidget {
  const EmptyClassroomPage({super.key});

  @override
  State<EmptyClassroomPage> createState() => _EmptyClassroomPageState();
}

class _EmptyClassroomPageState extends State<EmptyClassroomPage> {
  static final List<TimeSlot> _slots =
      kPresetTimeSlots.map((e) => TimeSlot.fromJson(e)).toList();

  RoomScanData? _scan;
  ClassroomDirectory? _directory;
  Timetable? _timetable;

  DateTime _selectedDate = DateTime.now();
  int? _building; // null=全部
  Set<int> _sections = {};
  int? _manualWeek; // 没有课表开学日期时的手动周次
  bool _showBusy = false;

  List<RoomQueryResult>? _results;
  bool _loadingData = true;

  @override
  void initState() {
    super.initState();
    _sections = _defaultSections(DateTime.now());
    _reloadData();
  }

  /// 按当前时刻推算默认节次：正在上的节；不在任何节内则取下一节。
  static Set<int> _defaultSections(DateTime now) {
    final minutes = now.hour * 60 + now.minute;
    for (final slot in _slots) {
      final start = _parseHm(slot.startTime);
      final end = _parseHm(slot.endTime);
      if (start == null || end == null) continue;
      if (minutes >= start && minutes <= end) return {slot.number};
    }
    for (final slot in _slots) {
      final start = _parseHm(slot.startTime);
      if (start == null) continue;
      if (minutes < start) return {slot.number};
    }
    return {_slots.first.number};
  }

  static int? _parseHm(String text) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(text.trim());
    if (m == null) return null;
    return int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!);
  }

  Future<void> _reloadData() async {
    setState(() => _loadingData = true);
    final scan = await RoomScanRepository.load();
    final directory = await ClassroomDirectory.load();
    final timetable = await TimetableRepository.load();
    if (!mounted) return;
    setState(() {
      _scan = scan;
      _directory = directory;
      _timetable = timetable;
      _loadingData = false;
    });
  }

  // ------------------------------------------------------------ 查询参数

  /// 查询周次：优先用课表推算，退回手动选择。
  int? get _effectiveWeek {
    final fromTimetable = _timetable?.weekOf(_selectedDate);
    return fromTimetable ?? _manualWeek;
  }

  int get _selectedDay => _selectedDate.weekday; // 周一=1 … 周日=7

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 180)),
      lastDate: DateTime.now().add(const Duration(days: 180)),
      helpText: '选择查询日期',
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _results = null;
      });
    }
  }

  void _setSections(Set<int> sections) {
    setState(() {
      _sections = sections;
      _results = null;
    });
  }

  void _toggleSection(int section) {
    final next = Set<int>.from(_sections);
    if (!next.remove(section)) next.add(section);
    if (next.isEmpty) return;
    _setSections(next);
  }

  /// 节次预设。
  static const Map<String, Set<int>> _sectionPresets = {
    '上午': {1, 2, 3, 4, 5},
    '下午': {6, 7, 8, 9, 10},
    '晚上': {11, 12, 13, 14},
    '全天': {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14},
  };

  // ------------------------------------------------------------ 查询

  void _runQuery() {
    final scan = _scan;
    final directory = _directory;
    final week = _effectiveWeek;
    if (scan == null || directory == null) return;
    if (week == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('无法确定周次：请先导入课表，或在下方手动选择周次'),
        ),
      );
      return;
    }
    if (_sections.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请至少选择一个节次')),
      );
      return;
    }

    final results = findRooms(
      scan: scan,
      directory: directory,
      week: week,
      day: _selectedDay,
      sections: _sections,
      building: _building,
    );
    setState(() => _results = results);
  }

  /// 去 WebView 扫描教室数据。
  Future<void> _openScan() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const JwglLoginPage(roomScan: true)),
    );
    await _reloadData();
  }

  // ------------------------------------------------------------ UI

  String _weekdayLabel(DateTime d) {
    const names = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return names[d.weekday - 1];
  }

  String _dateLabel(DateTime d) {
    final now = DateTime.now();
    final diff =
        DateTime(d.year, d.month, d.day)
            .difference(DateTime(now.year, now.month, now.day))
            .inDays;
    if (diff == 0) return '今天 ${_weekdayLabel(d)}';
    if (diff == 1) return '明天 ${_weekdayLabel(d)}';
    return '${d.month}-${d.day} ${_weekdayLabel(d)}';
  }

  String _sectionLabel(Set<int> sections) {
    final sorted = sections.toList()..sort();
    if (sorted.length == 1) return '第${sorted.first}节';
    return '第${sorted.first}-${sorted.last}节';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scan = _scan;

    return Scaffold(
      appBar: AppBar(title: const Text('空教室')),
      body: _loadingData
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                if (scan == null)
                  _EmptyDataCard(onScan: _openScan)
                else
                  _DataStatusCard(
                    scan: scan,
                    onScan: _openScan,
                    onRefresh: _reloadData,
                  ),
                const SizedBox(height: 12),
                _buildFilterCard(theme),
                const SizedBox(height: 12),
                _buildResultArea(theme),
              ],
            ),
    );
  }

  Widget _buildFilterCard(ThemeData theme) {
    final week = _effectiveWeek;
    return Card(
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('查询条件', style: theme.textTheme.titleSmall),
            const SizedBox(height: 12),

            // 楼栋
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<int?>(
                segments: const [
                  ButtonSegment(value: null, label: Text('全部')),
                  ButtonSegment(value: 1, label: Text('第一教学楼')),
                  ButtonSegment(value: 2, label: Text('第二教学楼')),
                ],
                selected: {_building},
                onSelectionChanged: (s) =>
                    setState(() => _building = s.first),
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
            const SizedBox(height: 12),

            // 日期 + 周次
            Row(
              children: [
                Icon(Icons.event_outlined,
                    size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                InkWell(
                  onTap: _pickDate,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 4),
                    child: Text(
                      _dateLabel(_selectedDate),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                if (week != null)
                  Text(
                    '第 $week 周',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  )
                else
                  _ManualWeekPicker(
                    value: _manualWeek,
                    onChanged: (v) => setState(() {
                      _manualWeek = v;
                      _results = null;
                    }),
                  ),
              ],
            ),
            if (_timetable == null || _timetable!.semesterStartDate.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '未导入课表，无法自动推算周次，请手动选择',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            const SizedBox(height: 10),

            // 快捷日期
            Wrap(
              spacing: 8,
              children: [0, 1, 2].map((offset) {
                final date = DateTime.now().add(Duration(days: offset));
                final selected = _sameDay(date, _selectedDate);
                return ChoiceChip(
                  label: Text(_dateLabel(date)),
                  selected: selected,
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => setState(() {
                    _selectedDate = date;
                    _results = null;
                  }),
                );
              }).toList(),
            ),
            const SizedBox(height: 10),

            // 节次预设 + 明细
            Text(
              '节次（${_sectionLabel(_sections)}）',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final entry in _sectionPresets.entries)
                  ActionChip(
                    label: Text(entry.key),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _setSections(Set.of(entry.value)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var i = 1; i <= 14; i++)
                  FilterChip(
                    label: Text('$i'),
                    selected: _sections.contains(i),
                    showCheckmark: false,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onSelected: (_) => _toggleSection(i),
                  ),
              ],
            ),
            const SizedBox(height: 14),

            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _scan == null ? null : _runQuery,
                    icon: const Icon(Icons.search),
                    label: const Text('查询空教室'),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: _reloadData,
                  child: const Text('刷新'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Widget _buildResultArea(ThemeData theme) {
    final results = _results;
    final scan = _scan;
    final directory = _directory;
    if (scan == null || directory == null) return const SizedBox.shrink();

    if (results == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            '选好日期和节次，点「查询空教室」',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }

    final empty = results.where((r) => r.isEmpty).toList();
    final busy = results.where((r) => !r.isEmpty).toList();
    final sectionText = _sectionLabel(_sections);
    final dayLabel = '${_dateLabel(_selectedDate)} $sectionText';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$dayLabel：共 ${empty.length} 间空教室',
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        if (empty.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: Text(
                '这个时段一教二教全都排了课',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          )
        else
          _RoomGroups(results: empty),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('显示已占用教室'),
          value: _showBusy,
          onChanged: (v) => setState(() => _showBusy = v),
        ),
        if (_showBusy && busy.isNotEmpty) _RoomGroups(results: busy, busy: true),
      ],
    );
  }
}

/// 没有扫描数据时的引导卡。
class _EmptyDataCard extends StatelessWidget {
  const _EmptyDataCard({required this.onScan});

  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(Icons.meeting_room_outlined,
                size: 40, color: theme.colorScheme.primary),
            const SizedBox(height: 10),
            Text(
              '还没有教室数据',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              '先到教务系统扫描一次班级课表\n'
              '（遍历各院系专业年级的上课地点，约需几分钟）',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onScan,
              icon: const Icon(Icons.radar),
              label: const Text('去扫描教室数据'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 数据状态卡（学期 / 扫描时间 / 覆盖量）。
class _DataStatusCard extends StatelessWidget {
  const _DataStatusCard({
    required this.scan,
    required this.onScan,
    required this.onRefresh,
  });

  final RoomScanData scan;
  final VoidCallback onScan;
  final VoidCallback onRefresh;

  String _fmt(DateTime t) {
    final mm = t.month.toString().padLeft(2, '0');
    final dd = t.day.toString().padLeft(2, '0');
    final hh = t.hour.toString().padLeft(2, '0');
    final mi = t.minute.toString().padLeft(2, '0');
    return '$mm-$dd $hh:$mi';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grades = scan.gradeFrom > 0 && scan.gradeTo > 0
        ? '${scan.gradeFrom}-${scan.gradeTo} 级'
        : '全部年级';

    return Card(
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.dataset_outlined,
                    size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    scan.termName.isNotEmpty
                        ? '教室数据 · ${scan.termName}'
                        : '教室数据',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: '重新扫描',
                  onPressed: onScan,
                  icon: const Icon(Icons.radar_outlined, size: 20),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: '重新加载',
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '扫描于 ${_fmt(scan.scannedAt)} · $grades · '
              '${scan.classCount} 个班级 · ${scan.lessons.length} 条排课记录',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (scan.termName.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '建议重新扫描一次以更新到最新学期',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 没有课表时的手动周次选择。
class _ManualWeekPicker extends StatelessWidget {
  const _ManualWeekPicker({required this.value, required this.onChanged});

  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DropdownButton<int>(
      value: value ?? 1,
      underline: const SizedBox.shrink(),
      isDense: true,
      items: [
        for (var i = 1; i <= 25; i++)
          DropdownMenuItem(value: i, child: Text('第 $i 周')),
      ],
      onChanged: onChanged,
      hint: Text('选择周次', style: theme.textTheme.bodyMedium),
    );
  }
}

/// 按楼栋 → 楼层分组展示教室。
class _RoomGroups extends StatelessWidget {
  const _RoomGroups({required this.results, this.busy = false});

  final List<RoomQueryResult> results;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // results 已按楼栋/楼层/房间号排序，直接顺序分组
    final groups = <String, List<RoomQueryResult>>{};
    final order = <String>[];
    for (final r in results) {
      final key = '${r.room.buildingName} ${r.room.floor}F';
      if (!groups.containsKey(key)) {
        groups[key] = [];
        order.add(key);
      }
      groups[key]!.add(r);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final key in order) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 6),
            child: Text(
              key,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final r in groups[key]!)
                _RoomChip(result: r, busy: busy),
            ],
          ),
        ],
      ],
    );
  }
}

/// 单间教室的小片。
class _RoomChip extends StatelessWidget {
  const _RoomChip({required this.result, required this.busy});

  final RoomQueryResult result;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final room = result.room;
    final isStudy = room.type.contains('考研');

    final scheme = theme.colorScheme;
    final background = busy
        ? scheme.surfaceContainerHighest
        : (isStudy
            ? scheme.tertiaryContainer.withValues(alpha: 0.55)
            : scheme.primaryContainer.withValues(alpha: 0.55));
    final foreground = busy ? scheme.onSurfaceVariant : scheme.onPrimaryContainer;

    return Tooltip(
      message: '${room.buildingName} ${room.number} · ${room.type}'
          '${busy && result.occupiedLessons.isNotEmpty ? '\n被占用' : ''}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              room.number,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: foreground,
              ),
            ),
            Text(
              room.type.replaceAll('教室', ''),
              style: TextStyle(
                fontSize: 9.5,
                height: 1.2,
                color: foreground.withValues(alpha: 0.85),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
