/// 课表页：周视图网格 + 周次切换 + 课程详情。
library;

import 'package:flutter/material.dart';

import '../models/timetable.dart';
import '../services/timetable_repository.dart';
import 'jwgl_login_page.dart';
import '../widgets/schedule_grid.dart';

/// 课表页。
class TimetablePage extends StatefulWidget {
  const TimetablePage({super.key});

  @override
  State<TimetablePage> createState() => _TimetablePageState();
}

class _TimetablePageState extends State<TimetablePage> {
  Timetable? _tt;
  bool _loading = true;
  int _week = 1;
  bool _refreshing = false;

  /// 是否显示周末。默认按课程自动判断：学期内没有周末课就隐藏。
  bool _showWeekends = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tt = await TimetableRepository.load();
    final savedPref = await TimetableRepository.loadShowWeekends();
    if (!mounted) return;
    setState(() {
      _tt = tt;
      _loading = false;
      _week = tt?.weekOf(DateTime.now()) ?? 1;
      // 用户手动设置过就尊重其选择；否则按是否有周末课自动决定
      _showWeekends = savedPref ?? _hasWeekendCourses(tt);
    });
  }

  /// 学期内是否存在周末（周六/周日）的课程。
  bool _hasWeekendCourses(Timetable? tt) {
    if (tt == null) return false;
    for (final c in tt.courses) {
      if (c.day >= 6) return true;
    }
    return false;
  }

  /// 切换周末显示，并记住选择。
  Future<void> _toggleWeekends() async {
    final next = !_showWeekends;
    setState(() => _showWeekends = next);
    await TimetableRepository.saveShowWeekends(next);
  }

  /// 重新同步：去教务系统导入一次，回来刷新。
  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    try {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const JwglLoginPage(allowImport: true),
        ),
      );
      if (mounted) await _load();
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tt = _tt;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('课程表'),
            if (tt != null)
              Text(
                '${tt.termName} · 共 ${tt.courses.length} 门课',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
          ],
        ),
        actions: [
          // 周末显示开关：有课表时才需要
          if (tt != null)
            IconButton(
              onPressed: _toggleWeekends,
              icon: Icon(
                _showWeekends ? Icons.date_range : Icons.date_range_outlined,
              ),
              color: _showWeekends ? theme.colorScheme.primary : null,
              tooltip: _showWeekends ? '隐藏周末' : '显示周末',
            ),
          // 有课表时提供「导入 / 重新同步」入口；无数据时由页面中间的按钮引导去登录
          if (tt != null)
            if (_refreshing)
              const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              IconButton(
                onPressed: _refresh,
                icon: const Icon(Icons.add),
                tooltip: '导入课表',
              ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : tt == null
          ? _EmptyState(onGoLogin: _goLogin)
          : Column(
              children: [
                _WeekSelector(
                  week: _week,
                  totalWeeks: tt.totalWeeks,
                  onChanged: (w) => setState(() => _week = w),
                ),
                const Divider(height: 1),
                // 本周无课但学期内有课时给出提示，避免看着像“数据没导入”
                if (!_hasCourseInWeek(tt, _week) && tt.courses.isNotEmpty)
                  _NoCourseHint(
                    week: _week,
                    total: tt.courses.length,
                    range: _weeksRange(tt),
                  ),
                Expanded(
                  child: ScheduleGrid(
                    courses: tt.courses,
                    week: _week,
                    totalWeeks: tt.totalWeeks,
                    timeSlots: tt.timeSlots,
                    semesterStartDate: tt.semesterStartDate,
                    showWeekends: _showWeekends,
                    onCourseTap: _showDetail,
                  ),
                ),
              ],
            ),
    );
  }

  /// 该周是否有课（含仅需灰化展示的课程）。
  bool _hasCourseInWeek(Timetable tt, int week) {
    for (final c in tt.courses) {
      if (c.weeks.isEmpty || c.isActiveInWeek(week)) return true;
    }
    return false;
  }

  /// 课程覆盖的周次范围文本，如「1-18 周」。
  String _weeksRange(Timetable tt) {
    var min = 1 << 30;
    var max = 0;
    for (final c in tt.courses) {
      for (final w in c.weeks) {
        if (w < min) min = w;
        if (w > max) max = w;
      }
    }
    if (max == 0) return '—';
    return '$min-$max 周';
  }

  /// 去教务系统登录并同步课表，回来后自动刷新。
  Future<void> _goLogin() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const JwglLoginPage(allowImport: true)),
    );
    if (!mounted) return;
    await _load();
  }

  void _showDetail(Course course) {
    final tt = _tt;
    final slotText = course.endSection > course.startSection
        ? '${course.startSection}-${course.endSection}节'
        : '${course.startSection}节';

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(course.name, style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              '共 ${course.weeks.length} 周 · ${course.weeks.join(', ')}',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            // 注意：$course.day 这种写法只会插值 $course，必须用 ${'$'}{...}
            _kv(ctx, '时间', '${_weekdayCn(course.day)} $slotText'),
            _kv(ctx, '教室', course.position.isEmpty ? '待定' : course.position),
            _kv(ctx, '教师', course.teacher.isEmpty ? '—' : course.teacher),
            if (tt != null)
              _kv(ctx, '学期', tt.termName.isEmpty ? '未获取' : tt.termName),
          ],
        ),
      ),
    );
  }

  static String _weekdayCn(int day) =>
      const ['', '周一', '周二', '周三', '周四', '周五', '周六', '周日'][day.clamp(0, 7)];

  Widget _kv(BuildContext ctx, String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 52,
          child: Text(
            k,
            style: TextStyle(color: Theme.of(ctx).colorScheme.outline),
          ),
        ),
        Expanded(child: Text(v)),
      ],
    ),
  );
}

/// 周次切换条。
class _WeekSelector extends StatelessWidget {
  const _WeekSelector({
    required this.week,
    required this.totalWeeks,
    required this.onChanged,
  });

  final int week;
  final int totalWeeks;
  final void Function(int week) onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            onPressed: week > 1 ? () => onChanged(week - 1) : null,
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Center(
              child: Text(
                '第 $week 周',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          IconButton(
            onPressed: week < totalWeeks ? () => onChanged(week + 1) : null,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}

/// 空状态：本地没有课表数据时，引导用户去教务系统登录同步。
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onGoLogin});

  final VoidCallback onGoLogin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.event_note_outlined,
              size: 64,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              '还没有课表数据',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '请先登录教务系统，同步本学期课表',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onGoLogin,
              icon: const Icon(Icons.login),
              label: const Text('去登录教务系统'),
              style: FilledButton.styleFrom(minimumSize: const Size(200, 46)),
            ),
          ],
        ),
      ),
    );
  }
}

/// 本周无课提示条。
class _NoCourseHint extends StatelessWidget {
  const _NoCourseHint({
    required this.week,
    required this.total,
    required this.range,
  });

  final int week;
  final int total;
  final String range;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.5),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            size: 16,
            color: theme.colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '第 $week 周没有课程排课 · 已导入 $total 门课（$range）',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
