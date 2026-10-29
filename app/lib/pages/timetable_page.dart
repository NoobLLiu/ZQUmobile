/// 课表页：周视图网格 + 周次切换 + 课程详情。
library;

import 'package:flutter/material.dart';

import '../models/timetable.dart';
import '../services/timetable_repository.dart';
import '../widgets/schedule_grid.dart';

/// 课表页。
class TimetablePage extends StatefulWidget {
  const TimetablePage({super.key, this.onRefreshRequest});

  /// 请求刷新（由外层注入，通常是跳转到教务登录页）。
  final Future<bool> Function()? onRefreshRequest;

  @override
  State<TimetablePage> createState() => _TimetablePageState();
}

class _TimetablePageState extends State<TimetablePage> {
  Timetable? _tt;
  bool _loading = true;
  String? _error;
  int _week = 1;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tt = await TimetableRepository.load();
    if (!mounted) return;
    setState(() {
      _tt = tt;
      _loading = false;
      _error = tt == null ? '还没有课表数据，点击右上角登录教务系统导入' : null;
      _week = tt?.weekOf(DateTime.now()) ?? 1;
    });
  }

  Future<void> _refresh() async {
    if (widget.onRefreshRequest == null) return;
    setState(() => _refreshing = true);
    try {
      final ok = await widget.onRefreshRequest!();
      if (ok) await _load();
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
                tt.termName,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
          ],
        ),
        actions: [
          if (_refreshing)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                  width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            IconButton(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
              tooltip: '重新导入',
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _EmptyState(message: _error!, onRetry: _load)
              : Column(
                  children: [
                    _WeekSelector(
                      week: _week,
                      totalWeeks: tt!.totalWeeks,
                      onChanged: (w) => setState(() => _week = w),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ScheduleGrid(
                        courses: tt.courses,
                        week: _week,
                        totalWeeks: tt.totalWeeks,
                        timeSlots: tt.timeSlots,
                        semesterStartDate: tt.semesterStartDate,
                        onCourseTap: _showDetail,
                      ),
                    ),
                  ],
                ),
    );
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
            Text(course.name,
                style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              '共 ${course.weeks.length} 周 · ${course.weeks.join(', ')}',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            _kv(ctx, '时间', '第$course.day 周 $slotText'),
            _kv(ctx, '教室', course.position.isEmpty ? '待定' : course.position),
            _kv(ctx, '教师', course.teacher.isEmpty ? '—' : course.teacher),
            if (tt != null) _kv(ctx, '学期', tt.termName.isEmpty ? tt.term : tt.termName),
          ],
        ),
      ),
    );
  }

  Widget _kv(BuildContext ctx, String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 52,
                child: Text(k, style: TextStyle(color: Theme.of(ctx).colorScheme.outline))),
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
              child: Text('第 $week 周',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
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

/// 空状态。
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_note_outlined,
                size: 56, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}
