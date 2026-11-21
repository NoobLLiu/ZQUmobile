/// 空教室查询页（版式参考 where_to_study 的查询页）。
///
/// 数据来自「扫描教室」采集的班级课表排课记录（见 zqu_room_scan.js），
/// 查询完全在本机完成：选校区 → 楼栋 + 日期 + 节次，从内置教室目录里
/// 找出该时段没有任何排课的教室；点教室小片可查看该教室当天的课表。
///
/// 星湖校区用地已转为住宅用地（肇庆市自然资源局 2026-10 规划公示），
/// 切到星湖校区时展示公示图并附说明文字。
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

/// 校区。
enum _Campus { main, xinghu }

/// 空教室查询页。
class EmptyClassroomPage extends StatefulWidget {
  const EmptyClassroomPage({super.key});

  @override
  State<EmptyClassroomPage> createState() => _EmptyClassroomPageState();
}

class _EmptyClassroomPageState extends State<EmptyClassroomPage> {
  static final List<TimeSlot> _slots =
      kPresetTimeSlots.map((e) => TimeSlot.fromJson(e)).toList();

  static const String _xinghuImage = 'assets/images/xinghu_gongshi.jpg';

  RoomScanData? _scan;
  ClassroomDirectory? _directory;
  Timetable? _timetable;

  _Campus _campus = _Campus.main;
  DateTime _selectedDate = DateTime.now();
  int? _building; // null=全部
  Set<int> _sections = {};
  int? _manualWeek; // 没有开学日期时的手动周次
  bool _excludePersonal = false; // 用个人课表排除已有课程的节次

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

  /// 查询周次：优先用课表推算，退回扫描数据里的开学日期，再退回手动选择。
  int? get _effectiveWeek {
    final fromTimetable = _timetable?.weekOf(_selectedDate);
    if (fromTimetable != null) return fromTimetable;
    return _scan?.weekOf(_selectedDate) ?? _manualWeek;
  }

  int get _selectedDay => _selectedDate.weekday; // 周一=1 … 周日=7

  /// 当天（所选日期 + 周次）有课的节次集合（来自个人课表）。
  Set<int> get _personalBusySections {
    final timetable = _timetable;
    final week = _effectiveWeek;
    if (timetable == null || week == null) return {};
    final busy = <int>{};
    for (final course in timetable.courses) {
      if (course.day != _selectedDay) continue;
      if (!course.weeks.contains(week)) continue;
      for (var s = course.startSection; s <= course.endSection; s++) {
        if (s >= 1 && s <= 14) busy.add(s);
      }
    }
    return busy;
  }

  /// 个人空闲节次（1..14 减去有课节次）。
  Set<int> get _personalFreeSections {
    final free = <int>{for (var i = 1; i <= 14; i++) i};
    return free.difference(_personalBusySections);
  }

  /// 当天个人课程（用于「当天课程」卡片）。
  List<Course> get _personalCoursesToday {
    final timetable = _timetable;
    final week = _effectiveWeek;
    if (timetable == null || week == null) return const [];
    return timetable.courses
        .where((c) => c.day == _selectedDay && c.weeks.contains(week))
        .toList()
      ..sort((a, b) => a.startSection.compareTo(b.startSection));
  }

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
    _setSections(next); // 允许清空；查询时校验
  }

  /// 「选中空闲」：勾选个人课表里没课的节次。
  void _selectFreeSections() {
    if (_timetable == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未导入个人课表，先全选全部节次')),
      );
      _setSections({for (var i = 1; i <= 14; i++) i});
      return;
    }
    final free = _personalFreeSections;
    if (free.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('这天 14 节都有课，没有空闲节次')),
      );
      return;
    }
    _setSections(free);
  }

  // ------------------------------------------------------------ 查询

  void _runQuery() {
    final scan = _scan;
    final directory = _directory;
    final week = _effectiveWeek;
    if (scan == null || directory == null) return;
    if (week == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('无法确定周次：请先导入课表，或手动选择周次'),
        ),
      );
      return;
    }

    var sections = _sections;
    if (_excludePersonal) {
      sections = sections.difference(_personalBusySections);
      if (sections.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('所选节次你都有课，换几节或关闭「排除已有课程」'),
          ),
        );
        return;
      }
    }
    if (sections.isEmpty) {
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
      sections: sections,
      building: _building,
    );
    setState(() {
      _results = results;
      _lastQuerySections = sections;
    });
  }

  /// 实际参与判定的节次（排除已有课程后），用于结果标题与概览。
  Set<int> _lastQuerySections = {};

  /// 去 WebView 扫描教室数据。
  Future<void> _openScan() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const JwglLoginPage(roomScan: true)),
    );
    await _reloadData();
  }

  // ------------------------------------------------------------ 教室当天课表

  void _showRoomSchedule(RoomQueryResult result) {
    final scan = _scan;
    final directory = _directory;
    if (scan == null || directory == null) return;
    final room = result.room;
    final ref = RoomRef(building: room.building, number: room.number);
    final lessons = daySchedule(
      scan: scan,
      directory: directory,
      ref: ref,
      day: _selectedDay,
    );
    final week = _effectiveWeek;
    final courseNames = scan.courseNames;

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${room.buildingName} ${room.number}'),
        contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text(
                  '${_dateLabel(_selectedDate)} 的课表'
                  '${room.type.isEmpty ? '' : ' · ${room.type}'}',
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  children: [
                    if (lessons.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          '当天无排课记录，全天空闲',
                          style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(ctx).colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      )
                    else
                      for (final l in lessons)
                        ListTile(
                          dense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 16),
                          leading: SizedBox(
                            width: 58,
                            child: Text(
                              l.startSection == l.endSection
                                  ? '第${l.startSection}节'
                                  : '第${l.startSection}-${l.endSection}节',
                              style: Theme.of(ctx)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          title: Text(
                            l.nameIndex >= 0 &&
                                    l.nameIndex < courseNames.length &&
                                    courseNames[l.nameIndex].isNotEmpty
                                ? courseNames[l.nameIndex]
                                : '（未知名课程）',
                            style: Theme.of(ctx).textTheme.bodyMedium,
                          ),
                          subtitle: Text(
                            weeksLabel(l.weeks) + (l.day == 0 ? ' · 星期未知' : ''),
                            style: Theme.of(ctx).textTheme.bodySmall,
                          ),
                          trailing: week != null && l.weeks.contains(week)
                              ? Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Theme.of(ctx)
                                        .colorScheme
                                        .primaryContainer,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '本周',
                                    style: Theme.of(ctx)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: Theme.of(ctx)
                                              .colorScheme
                                              .onPrimaryContainer,
                                        ),
                                  ),
                                )
                              : null,
                        ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ UI

  String _weekdayLabel(DateTime d) {
    const names = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return names[d.weekday - 1];
  }

  String _dateLabel(DateTime d) {
    final now = DateTime.now();
    final diff = DateTime(d.year, d.month, d.day)
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;
    if (diff == 0) return '今天 ${_weekdayLabel(d)}';
    if (diff == 1) return '明天 ${_weekdayLabel(d)}';
    return '${d.month}-${d.day} ${_weekdayLabel(d)}';
  }

  String _sectionLabel(Set<int> sections) {
    final sorted = sections.toList()..sort();
    if (sorted.isEmpty) return '未选';
    if (sorted.length == 1) return '第${sorted.first}节';
    return '第${sorted.first}-${sorted.last}节';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final xinghu = _campus == _Campus.xinghu;

    return Scaffold(
      appBar: AppBar(title: const Text('空教室')),
      body: _loadingData
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                _buildQueryCard(theme),
                if (xinghu) ...[
                  const SizedBox(height: 12),
                  _buildXinghuCard(theme),
                ] else ...[
                  const SizedBox(height: 12),
                  if (_scan == null)
                    _EmptyDataCard(onScan: _openScan)
                  else ...[
                    _buildSectionFilterCard(theme),
                    const SizedBox(height: 12),
                    _buildTodayCoursesCard(theme),
                    const SizedBox(height: 12),
                    _buildBuildingsCard(theme),
                    const SizedBox(height: 12),
                    _buildResultCard(theme),
                    const SizedBox(height: 12),
                    _buildOverviewCard(theme),
                  ],
                ],
              ],
            ),
    );
  }

  /// 卡片标题行。
  Widget _cardTitle(ThemeData theme, IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 6),
        Text(text, style: theme.textTheme.titleSmall),
      ],
    );
  }

  /// 卡 1：查询条件（校区切换 + 日期 + 获取按钮）。
  Widget _buildQueryCard(ThemeData theme) {
    final scan = _scan;
    return Card(
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cardTitle(theme, Icons.fact_check_outlined, '查询条件'),
            const SizedBox(height: 12),

            // 校区
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<_Campus>(
                segments: const [
                  ButtonSegment(value: _Campus.main, label: Text('主校区')),
                  ButtonSegment(value: _Campus.xinghu, label: Text('星湖校区')),
                ],
                selected: {_campus},
                onSelectionChanged: (s) =>
                    setState(() => _campus = s.first),
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
            if (_campus != _Campus.xinghu) ...[
              const SizedBox(height: 10),

              // 日期快捷 + 周次
              Row(
                children: [
                  for (final offset in [0, 1, 2])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(_dateLabel(
                            DateTime.now().add(Duration(days: offset)))),
                        selected: _sameDay(
                            DateTime.now().add(Duration(days: offset)),
                            _selectedDate),
                        showCheckmark: false,
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) => setState(() {
                          _selectedDate =
                              DateTime.now().add(Duration(days: offset));
                          _results = null;
                        }),
                      ),
                    ),
                  InkWell(
                    onTap: _pickDate,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.edit_calendar_outlined,
                              size: 16, color: theme.colorScheme.primary),
                          const SizedBox(width: 4),
                          Text(
                            '选日期',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  _buildWeekBadge(theme),
                ],
              ),

              // 数据状态（一行小字 + 重新扫描入口）
              if (scan != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _dataSummary(scan),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Tooltip(
                      message: '重新扫描教室数据',
                      child: IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: _openScan,
                        icon: const Icon(Icons.radar_outlined, size: 18),
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: scan == null ? null : _runQuery,
                  icon: const Icon(Icons.search),
                  label: const Text('获取空教室信息'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildWeekBadge(ThemeData theme) {
    final week = _effectiveWeek;
    if (week != null) {
      return Text(
        '第 $week 周',
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.primary,
        ),
      );
    }
    return _ManualWeekPicker(
      value: _manualWeek,
      onChanged: (v) => setState(() {
        _manualWeek = v;
        _results = null;
      }),
    );
  }

  String _dataSummary(RoomScanData scan) {
    final mm = scan.scannedAt.month.toString().padLeft(2, '0');
    final dd = scan.scannedAt.day.toString().padLeft(2, '0');
    final hh = scan.scannedAt.hour.toString().padLeft(2, '0');
    final mi = scan.scannedAt.minute.toString().padLeft(2, '0');
    final term = scan.termName.isNotEmpty ? scan.termName : scan.term;
    return '教室数据 $term · $mm-$dd $hh:$mi 扫描 · '
        '${scan.classCount} 个班级 ${scan.lessons.length} 条排课';
  }

  /// 卡 2：节次筛选。
  Widget _buildSectionFilterCard(ThemeData theme) {
    return Card(
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: _cardTitle(theme, Icons.schedule, '节次筛选')),
                Text(
                  _sectionLabel(_sections),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '使用个人课表排除已有课程',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                Switch(
                  value: _excludePersonal,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: (v) => setState(() {
                    _excludePersonal = v;
                    _results = null;
                  }),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: [
                ActionChip(
                  label: const Text('选中空闲'),
                  visualDensity: VisualDensity.compact,
                  onPressed: _selectFreeSections,
                ),
                ActionChip(
                  label: const Text('清空'),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _setSections({}),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final slot in _slots)
                  _SectionChip(
                    slot: slot,
                    selected: _sections.contains(slot.number),
                    onToggle: () => _toggleSection(slot.number),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 卡 3：当天课程（个人课表）。
  Widget _buildTodayCoursesCard(ThemeData theme) {
    final courses = _personalCoursesToday;
    return Card(
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cardTitle(theme, Icons.event_note_outlined, '当天课程'),
            const SizedBox(height: 10),
            if (courses.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  _timetable == null
                      ? '暂无本地课程，请先在「我的课表」导入个人课表'
                      : '${_dateLabel(_selectedDate)}没有课，全天有空',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              for (final c in courses)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 62,
                        child: Text(
                          c.startSection == c.endSection
                              ? '第${c.startSection}节'
                              : '第${c.startSection}-${c.endSection}节',
                          style: theme.textTheme.labelMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          c.name,
                          style: theme.textTheme.bodyMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (c.position.isNotEmpty)
                        Text(
                          c.position,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }

  /// 卡 4：教学楼筛选。
  Widget _buildBuildingsCard(ThemeData theme) {
    return Card(
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cardTitle(theme, Icons.location_city_outlined, '教学楼'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _BuildingChip(
                  label: '全部',
                  selected: _building == null,
                  onTap: () => setState(() {
                    _building = null;
                    _results = null;
                  }),
                ),
                _BuildingChip(
                  label: '第一教学楼',
                  selected: _building == 1,
                  onTap: () => setState(() {
                    _building = 1;
                    _results = null;
                  }),
                ),
                _BuildingChip(
                  label: '第二教学楼',
                  selected: _building == 2,
                  onTap: () => setState(() {
                    _building = 2;
                    _results = null;
                  }),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 卡 5：空教室结果。
  Widget _buildResultCard(ThemeData theme) {
    final results = _results;
    final scan = _scan;
    if (scan == null) return const SizedBox.shrink();

    final empty = results?.where((r) => r.isEmpty).toList();
    final sectionText = _sectionLabel(_lastQuerySections);

    return Card(
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cardTitle(theme, Icons.check_circle_outline, '空教室结果'),
            const SizedBox(height: 10),
            if (results == null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '选好日期和节次，点「获取空教室信息」',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else ...[
              Text(
                '${_dateLabel(_selectedDate)} $sectionText：'
                '${empty!.length} 间空教室（点教室看当天课表）',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              if (empty.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '这个时段一教二教全都排了课',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              else
                _RoomGroups(results: empty, onRoomTap: _showRoomSchedule),
            ],
          ],
        ),
      ),
    );
  }

  /// 卡 6：查询概览。
  Widget _buildOverviewCard(ThemeData theme) {
    final queried = _results != null;
    final emptyCount =
        _results?.where((r) => r.isEmpty).length ?? 0;
    final courseCount = _personalCoursesToday.length;
    final freeCount = _personalFreeSections.length;

    Widget stat(String label, String value) {
      return Expanded(
        child: Column(
          children: [
            Text(
              value,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
          ],
        ),
      );
    }

    return Card(
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cardTitle(theme, Icons.insights_outlined, '查询概览'),
            const SizedBox(height: 10),
            Row(
              children: [
                stat('当天课程', '$courseCount'),
                stat('个人空闲节次', '$freeCount'),
                stat('空教室', queried ? '$emptyCount' : '—'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 星湖校区卡：规划公示图 + 说明。
  Widget _buildXinghuCard(ThemeData theme) {
    return Card(
      color: theme.colorScheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cardTitle(theme, Icons.map_outlined, '星湖校区'),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset(
                _xinghuImage,
                width: double.infinity,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 10),
            Center(
              child: Text(
                '空悲切（星湖校区用地性质已转为"二类城镇住宅用地"）',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
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
              '（全校 3500+ 个班级，约需 20 秒）',
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

/// 节次筛选的小块（节号 + 作息时间）。
class _SectionChip extends StatelessWidget {
  const _SectionChip({
    required this.slot,
    required this.selected,
    required this.onToggle,
  });

  final TimeSlot slot;
  final bool selected;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 92,
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 6),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primaryContainer.withValues(alpha: 0.7)
              : scheme.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '第 ${slot.number} 节',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: selected ? scheme.onPrimaryContainer : scheme.onSurface,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              '${slot.startTime}-${slot.endTime}',
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 9.5,
                color: selected
                    ? scheme.onPrimaryContainer.withValues(alpha: 0.85)
                    : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 教学楼筛选小块。
class _BuildingChip extends StatelessWidget {
  const _BuildingChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primaryContainer.withValues(alpha: 0.7)
              : scheme.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.place_outlined,
              size: 15,
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: selected ? scheme.onPrimaryContainer : scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 按楼栋 → 楼层分组展示教室。
class _RoomGroups extends StatelessWidget {
  const _RoomGroups({required this.results, required this.onRoomTap});

  final List<RoomQueryResult> results;
  final void Function(RoomQueryResult) onRoomTap;

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
                _RoomChip(result: r, onTap: () => onRoomTap(r)),
            ],
          ),
        ],
      ],
    );
  }
}

/// 单间教室的小片（可点击查看当天课表）。
class _RoomChip extends StatelessWidget {
  const _RoomChip({required this.result, required this.onTap});

  final RoomQueryResult result;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final room = result.room;
    final isStudy = room.type.contains('考研');

    final scheme = theme.colorScheme;
    final background = isStudy
        ? scheme.tertiaryContainer.withValues(alpha: 0.55)
        : scheme.primaryContainer.withValues(alpha: 0.55);
    final foreground = scheme.onPrimaryContainer;

    return Tooltip(
      message: '${room.buildingName} ${room.number} · ${room.type}\n点按查看当天课表',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
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
      ),
    );
  }
}
