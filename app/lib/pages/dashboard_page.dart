/// 看板页（默认首页）：汇聚今日课程与生活数据。
///
/// 上方 Today 卡片展示所选日期的课程，支持左右滑动、箭头按钮与
/// 日历三种切日方式，日历范围限定在本学期内；下方以极简卡片
/// 展示宿舍水电余额（与水电页共用同一套缓存/刷新策略，
/// 见 UtilityDataProvider，查不到时显示「未查到」）。
library;

import 'package:flutter/material.dart';

import '../core/grid_style.dart';
import '../models/attachment_schedule.dart';
import '../models/timetable.dart';
import '../models/utility.dart';
import '../services/attachment_schedule_repository.dart';
import '../services/profile_repository.dart';
import '../services/timetable_repository.dart';
import '../services/utility_provider.dart';
import '../widgets/app_bar_title.dart';

const List<String> _weekdayLabels = [
  '周一',
  '周二',
  '周三',
  '周四',
  '周五',
  '周六',
  '周日',
];

/// 水电缓存的新鲜窗口等分档规则见 UtilityDataProvider。

DateTime _today() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

/// 看板页。
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => DashboardPageState();
}

class DashboardPageState extends State<DashboardPage>
    with SingleTickerProviderStateMixin {
  /// 切日动画控制器。
  late final AnimationController _dayCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );

  /// 动画开始前所在的日期（用于绘制滑出的旧内容）。
  DateTime? _prevSelected;

  /// 最近一次切日的方向：+1 往后一天，-1 往前一天。
  int _dayDir = 1;

  Timetable? _timetable;

  /// 附属日程（晚自习 / 阳光体育），按星期合并进 Today 列表。
  List<AttachmentSchedule> _extras = const [];

  /// 水电数据；为空表示暂无可展示的余额。
  List<UtilityRoom> _rooms = const [];

  String _roomName = '';

  /// true 表示当前展示的是刷新失败后回退的缓存，可能不是最新。
  bool _utilWarn = false;

  bool _utilLoading = false;

  String _studentId = '';

  DateTime _selected = _today();

  /// Today 卡片上拖动的累计位移（横向 / 纵向）。
  double _dragDx = 0;
  double _dragDy = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _dayCtrl.dispose();
    super.dispose();
  }

  /// 重新加载课表与水电数据（切回看板 tab 时调用）。
  void reload() => _load();

  Future<void> _load() async {
    final tt = await TimetableRepository.load();
    final extras = await AttachmentScheduleRepository.load();
    // 开学日期解析失败的课表视同没有课表。
    Timetable? usable =
        (tt != null && DateTime.tryParse(tt.semesterStartDate) != null)
        ? tt
        : null;

    final profile = await ProfileRepository.load();
    var rooms = const <UtilityRoom>[];
    var roomName = '';
    var warn = false;
    var needRefresh = false;
    final studentId = profile.studentId;

    if (studentId.isNotEmpty) {
      _studentId = studentId;
      // 与水电页共用同一套缓存/刷新策略。
      final snap = await UtilityDataProvider.load(studentId);
      if (snap.rooms != null) {
        rooms = snap.rooms!;
        roomName = rooms.first.roomName;
      }
      warn = snap.error != null;
      needRefresh = snap.shouldRefresh;
    }

    if (!mounted) return;
    setState(() {
      _timetable = usable;
      _extras = extras;
      _rooms = rooms;
      _roomName = roomName;
      _utilWarn = warn;
      _utilLoading = needRefresh;
      _clampSelection();
    });
    if (needRefresh) _refreshUtility();
  }

  /// 后台刷新水电余额（策略与水电页一致）。
  Future<void> _refreshUtility() async {
    final snap = await UtilityDataProvider.refresh(_studentId);
    if (!mounted) return;
    setState(() {
      _rooms = snap.rooms ?? const [];
      _roomName = _rooms.isEmpty ? '' : _rooms.first.roomName;
      _utilWarn = snap.error != null;
      _utilLoading = false;
    });
  }

  DateTime? get _semStart => DateTime.tryParse(_timetable?.semesterStartDate ?? '');

  DateTime? get _semEnd {
    final tt = _timetable;
    final start = _semStart;
    if (tt == null || start == null) return null;
    return start.add(Duration(days: tt.totalWeeks * 7 - 1));
  }

  void _clampSelection() {
    final start = _semStart;
    final end = _semEnd;
    if (start == null || end == null) return;
    if (_selected.isBefore(start)) {
      _selected = start;
    } else if (_selected.isAfter(end)) {
      _selected = end;
    }
  }

  bool get _isToday => _sameDay(_selected, DateTime.now());

  void _shiftDay(int delta) {
    final d = _selected.add(Duration(days: delta));
    final start = _semStart;
    final end = _semEnd;
    if (start != null && end != null) {
      if (d.isBefore(start) || d.isAfter(end)) return;
    }
    _animateDayTo(d, delta);
  }

  /// 切到目标日期并播放滑动动画，dir 为方向（+1 后一天 / -1 前一天）。
  void _animateDayTo(DateTime d, int dir) {
    setState(() {
      _prevSelected = _selected;
      _selected = d;
      _dayDir = dir >= 0 ? 1 : -1;
    });
    _dayCtrl.forward(from: 0);
  }

  Future<void> _pickDate() async {
    final today = _today();
    final first = _semStart ?? DateTime(today.year, 1, 1);
    final last = _semEnd ?? DateTime(today.year, 12, 31);
    var initial = _selected;
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      helpText: '选择本学期内的日期',
    );
    if (picked != null) {
      final d = DateTime(picked.year, picked.month, picked.day);
      _animateDayTo(d, d.isAfter(_selected) ? 1 : -1);
    }
  }

  /// 顶部居中的日期文案。
  String _headerLabel(DateTime date) {
    final label =
        '${date.month}月${date.day}日 '
        '${_weekdayLabels[date.weekday - 1]}';
    return _sameDay(date, DateTime.now()) ? '今天 · $label' : label;
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const AppBarBrandTitle('看板')),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: _buildTodayCard(context),
            ),
          ),
          _buildLifeSection(context),
        ],
      ),
    );
  }

  // ---------- Today 卡片 ----------

  Widget _buildTodayCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Listener(
        // 用原始指针位移累积判定，不参与手势竞技场：课程列表的滚动手势
        // 不会抢走事件，有课/无课页面的判定完全一致。横向位移达阈值且
        // 明显大于纵向时才切日，避免把竖向滚动误判成切日。
        onPointerDown: (_) {
          _dragDx = 0;
          _dragDy = 0;
        },
        onPointerMove: (event) {
          _dragDx += event.delta.dx;
          _dragDy += event.delta.dy;
        },
        onPointerUp: (_) {
          final dx = _dragDx;
          final dy = _dragDy;
          _dragDx = 0;
          _dragDy = 0;
          if (dx.abs() >= 40 && dx.abs() > dy.abs()) {
            _shiftDay(dx < 0 ? 1 : -1);
          }
        },
        child: Column(
          children: [
            // 顶部一行：箭头贴卡片左右两侧，日期与周次居中（参与切日动画）
            SizedBox(
              height: 48,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Center(
                      child: AnimatedBuilder(
                        animation: _dayCtrl,
                        builder: (context, _) => _dayLayer(
                          current: _buildHeaderCenter(context, _selected),
                          previous: _dayCtrl.isAnimating
                              ? _buildHeaderCenter(
                                  context,
                                  _prevSelected ?? _selected,
                                )
                              : null,
                        ),
                      ),
                    ),
                  ),
                  // 箭头给足 56x48 的点击区，方便手指点按
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: 56,
                    child: IconButton(
                      icon: const Icon(Icons.chevron_left),
                      tooltip: '前一天',
                      onPressed: () => _shiftDay(-1),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    width: 56,
                    child: IconButton(
                      icon: const Icon(Icons.chevron_right),
                      tooltip: '后一天',
                      onPressed: () => _shiftDay(1),
                    ),
                  ),
                ],
              ),
            ),
            // 课程列表（参与切日动画）
            Expanded(
              child: AnimatedBuilder(
                animation: _dayCtrl,
                builder: (context, _) => _dayLayer(
                  current: _buildCourseList(context, _selected),
                  previous: _dayCtrl.isAnimating
                      ? _buildCourseList(context, _prevSelected ?? _selected)
                      : null,
                ),
              ),
            ),
            // 底部一行：操作提示 + 回到今天 + 刷新
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 6, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '左右滑动或点日期切换',
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.outline,
                      ),
                    ),
                  ),
                  if (!_isToday)
                    GestureDetector(
                      onTap: () => _animateDayTo(
                        _today(),
                        _today().isAfter(_selected) ? 1 : -1,
                      ),
                      child: Text(
                        '回到今天',
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.primary,
                        ),
                      ),
                    ),
                  if (!_isToday) const SizedBox(width: 4),
                  IconButton(
                    tooltip: '刷新',
                    visualDensity: VisualDensity.compact,
                    onPressed: _utilLoading ? null : _load,
                    icon: _utilLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 顶行中央的日期 + 周次。
  Widget _buildHeaderCenter(BuildContext context, DateTime date) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 点日期文字直接弹日期选择器
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _pickDate,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            child: Text(
              _headerLabel(date),
              maxLines: 1,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
        _buildWeekChip(context, date),
      ],
    );
  }

  /// 切日动画层：旧内容向滑动方向平移、淡出、缩小；新内容从反方向
  /// 滑入、淡入、放大回原大。easeOutCubic 缓动。
  Widget _dayLayer({required Widget current, Widget? previous}) {
    if (previous == null) return current;
    final t = Curves.easeOutCubic.transform(_dayCtrl.value);
    final dir = _dayDir.toDouble();
    const slide = 56.0;
    return Stack(
      fit: StackFit.passthrough,
      alignment: Alignment.center,
      children: [
        Opacity(
          opacity: 1 - t,
          child: Transform.translate(
            offset: Offset(-dir * slide * t, 0),
            child: Transform.scale(scale: 1 - 0.1 * t, child: previous),
          ),
        ),
        Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(dir * slide * (1 - t), 0),
            child: Transform.scale(scale: 0.9 + 0.1 * t, child: current),
          ),
        ),
      ],
    );
  }

  Widget _buildWeekChip(BuildContext context, DateTime date) {
    final scheme = Theme.of(context).colorScheme;
    final week = _timetable?.weekOf(date);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        week == null ? '学期外' : '第 $week 周',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: scheme.onPrimaryContainer,
        ),
      ),
    );
  }

  Widget _buildCourseList(BuildContext context, DateTime date) {
    final isToday = _sameDay(date, _today());
    final tt = _timetable;
    if (tt == null) {
      return _emptyState(
        context,
        icon: Icons.event_busy_outlined,
        title: '还没有课表',
        sub: '导入课表后，这里会按天展示课程',
        action: FilledButton.tonalIcon(
          onPressed: () => Navigator.pushNamed(context, '/timetable'),
          icon: const Icon(Icons.download_outlined),
          label: const Text('去导入课表'),
        ),
      );
    }

    final week = tt.weekOf(date);
    if (week == null) {
      // 学期外没有课程周次，但附属日程仍按星期合并展示。
      final extras = _extras
          .where((s) => s.enabled && s.occursOn(date.weekday))
          .toList();
      if (extras.isEmpty) {
        return _emptyState(
          context,
          icon: Icons.beach_access_outlined,
          title: '该日期不在本学期内',
          sub: '选一个学期内的日子看看吧',
        );
      }
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        itemCount: extras.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, i) => i == 0
            ? _buildExtrasHeader(context)
            : _buildExtraRow(context, extras[i - 1], isToday),
      );
    }

    final slotMap = {for (final t in tt.timeSlots) t.number: t};
    final courses =
        tt.courses
            .where((c) => c.day == date.weekday && c.weeks.contains(week))
            .toList()
          ..sort((a, b) => a.startSection.compareTo(b.startSection));

    // 附属日程按星期合并，不受教学周限制。
    final extras = _extras
        .where((s) => s.enabled && s.occursOn(date.weekday))
        .toList();

    if (courses.isEmpty && extras.isEmpty) {
      return _emptyState(
        context,
        icon: Icons.nights_stay_outlined,
        title: isToday ? '今天没有课' : '这一天没有课',
        sub: isToday ? '好好休息，或者去图书馆自习吧' : '换个日子看看吧',
      );
    }

    final rows = <Widget>[
      for (final c in courses) _buildCourseRow(context, c, slotMap, isToday),
      if (extras.isNotEmpty) ...[
        _buildExtrasHeader(context),
        for (final e in extras) _buildExtraRow(context, e, isToday),
      ],
    ];

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) => rows[i],
    );
  }

  /// 附属日程区块的小标题。
  Widget _buildExtrasHeader(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 4),
      child: Row(
        children: [
          Icon(Icons.event_available_outlined,
              size: 13, color: scheme.primary),
          const SizedBox(width: 4),
          Text(
            '附属日程',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: scheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  /// 附属日程行（配色与课程条区分，用主题色淡底）。
  Widget _buildExtraRow(
    BuildContext context,
    AttachmentSchedule schedule,
    bool isToday,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final base = schedule.type == AttachmentScheduleType.eveningStudy
        ? const Color(0xFF5C6BC0)
        : const Color(0xFFEF8C3F);
    final bg = base.withValues(alpha: isDark ? 0.28 : 0.13);
    final fg = scheme.onSurface;
    final fgSub = scheme.onSurfaceVariant;

    final ongoing =
        isToday && _inProgress(schedule.start, schedule.end);
    final sub = [
      schedule.weekdayLabel,
      if (schedule.location.isNotEmpty) schedule.location,
      if (schedule.note.isNotEmpty) schedule.note,
    ].join(' · ');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            SizedBox(
              width: 48,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    schedule.start,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: fg,
                    ),
                  ),
                  Text(
                    schedule.end,
                    style: TextStyle(fontSize: 11, color: fgSub),
                  ),
                ],
              ),
            ),
            Container(width: 1, color: fgSub.withValues(alpha: 0.4)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Icon(
                        schedule.type == AttachmentScheduleType.eveningStudy
                            ? Icons.nights_stay_outlined
                            : Icons.wb_sunny_outlined,
                        size: 15,
                        color: base,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          schedule.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: fg,
                          ),
                        ),
                      ),
                      if (ongoing) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0x33FFFFFF)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '进行中',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? fg : const Color(0xFFA32D2D),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (sub.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: fgSub),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCourseRow(
    BuildContext context,
    Course course,
    Map<int, TimeSlot> slotMap,
    bool isToday,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final index =
        course.colorIndex ?? _hashIndex(course.name, kDefaultColorMaps.length);
    final pair = kDefaultColorMaps[index % kDefaultColorMaps.length];
    final bg = Color(isDark ? pair.dark : pair.light);
    final fg = isDark ? Colors.white : const Color(0xFF1F1F1F);
    final fgSub = isDark ? const Color(0xCCFFFFFF) : const Color(0x991F1F1F);

    final start = slotMap[course.startSection]?.startTime ?? '';
    final end = slotMap[course.endSection]?.endTime ?? '';
    final sectionLabel = course.startSection == course.endSection
        ? '第 ${course.startSection} 节'
        : '${course.startSection}-${course.endSection} 节';

    final ongoing = isToday && start.isNotEmpty && end.isNotEmpty && _inProgress(start, end);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            SizedBox(
              width: 48,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    start.isEmpty ? sectionLabel : start,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: fg,
                    ),
                  ),
                  if (end.isNotEmpty)
                    Text(
                      end,
                      style: TextStyle(fontSize: 11, color: fgSub),
                    ),
                ],
              ),
            ),
            Container(width: 1, color: fgSub),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          course.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: fg,
                          ),
                        ),
                      ),
                      if (ongoing) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0x33FFFFFF)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '进行中',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? fg : const Color(0xFFA32D2D),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$sectionLabel · ${course.position}'
                    '${course.teacher.isEmpty ? '' : ' · ${course.teacher}'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: fgSub),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _inProgress(String start, String end) {
    final now = DateTime.now();
    final minute = now.hour * 60 + now.minute;
    return minute >= _toMinute(start) && minute < _toMinute(end);
  }

  static int _toMinute(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return 0;
    return int.tryParse(parts[0])! * 60 + int.tryParse(parts[1])!;
  }

  /// 与课表网格一致的课程散列取色。
  static int _hashIndex(String name, int length) {
    if (length <= 0) return 0;
    var h = 0;
    for (final rune in name.codeUnits) {
      h = (h * 31 + rune) & 0x7fffffff;
    }
    return h % length;
  }

  Widget _emptyState(
    BuildContext context, {
    IconData? icon,
    required String title,
    String? sub,
    Widget? action,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) Icon(icon, size: 44, color: scheme.outline),
          if (icon != null) const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
          if (sub != null) ...[
            const SizedBox(height: 4),
            Text(sub, style: TextStyle(fontSize: 12, color: scheme.outline)),
          ],
          if (action != null) ...[const SizedBox(height: 14), action],
        ],
      ),
    );
  }

  // ---------- 生活数据 ----------

  Widget _buildLifeSection(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final room = _rooms.isNotEmpty ? _rooms.first : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                '生活数据',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (_utilLoading) ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: scheme.outline,
                  ),
                ),
              ],
              if (_utilWarn) ...[
                const SizedBox(width: 6),
                Tooltip(
                  message: _rooms.isEmpty
                      ? '查询失败，未能获取水电余额'
                      : '网络刷新失败，展示的是本地缓存，可能不是最新',
                  child: Icon(
                    Icons.error_outline,
                    size: 14,
                    color: const Color(0xFFBA7517),
                  ),
                ),
              ],
              const Spacer(),
              if (_roomName.isNotEmpty)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 140),
                  child: Text(
                    _roomName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: scheme.outline),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _UtilityCard(
                  icon: Icons.bolt,
                  iconColor: const Color(0xFFBA7517),
                  label: '电费余额',
                  value: room == null ? '未查到' : _fmt(room.electricity),
                  unit: room == null ? '' : '度',
                  low: room != null && isElectricityLow(room.electricity),
                  onTap: _openUtilityPage,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _UtilityCard(
                  icon: Icons.water_drop,
                  iconColor: const Color(0xFF378ADD),
                  label: '水费余额',
                  value: room == null ? '未查到' : _fmt(room.water),
                  unit: room == null ? '' : '吨',
                  low: room != null && isWaterLow(room.water),
                  onTap: _openUtilityPage,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openUtilityPage() async {
    await Navigator.pushNamed(context, '/utility');
    if (mounted) _load();
  }

  static String _fmt(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(1);
  }
}

/// 生活数据里的一个极简余额卡：图标 + 数字 + 淡灰单位，低余额时数字标红。
class _UtilityCard extends StatelessWidget {
  const _UtilityCard({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.unit,
    required this.onTap,
    this.low = false,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final String unit;
  final VoidCallback onTap;

  /// 是否低于阈值（数字标红）。
  final bool low;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final valueColor = low ? scheme.error : scheme.onSurface;
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(fontSize: 11, color: scheme.outline),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          value,
                          style: TextStyle(
                            fontSize: value == '未查到' ? 14 : 18,
                            fontWeight: FontWeight.w500,
                            color: valueColor,
                          ),
                        ),
                        if (unit.isNotEmpty) ...[
                          const SizedBox(width: 3),
                          Text(
                            unit,
                            style: TextStyle(
                              fontSize: 11,
                              color: scheme.outline,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
