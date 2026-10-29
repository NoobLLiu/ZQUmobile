/// 课程冲突处理弹窗。
///
/// 导入完成后若发现同一时段有多门课（节次重叠且周次有交集），
/// 由用户在弹窗里为每一组冲突选择保留哪一门。
library;

import 'package:flutter/material.dart';

import '../models/timetable.dart';

/// 弹窗让用户解决课程冲突。
///
/// 返回处理后的课程列表；用户点「取消」时返回 null（保持原样不删减）。
Future<List<Course>?> showConflictResolver(
  BuildContext context,
  List<CourseConflict> conflicts,
  List<Course> allCourses,
) {
  return showDialog<List<Course>>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _ConflictDialog(
      conflicts: conflicts,
      allCourses: allCourses,
    ),
  );
}

class _ConflictDialog extends StatefulWidget {
  const _ConflictDialog({required this.conflicts, required this.allCourses});

  final List<CourseConflict> conflicts;
  final List<Course> allCourses;

  @override
  State<_ConflictDialog> createState() => _ConflictDialogState();
}

class _ConflictDialogState extends State<_ConflictDialog> {
  /// 每组的选择：
  ///  -1  = 全部保留（默认，不悄悄删数据）
  ///  >=0 = 保留该组里第 i 门课
  late List<int> _choices;

  @override
  void initState() {
    super.initState();
    _choices = List<int>.filled(widget.conflicts.length, -1);
  }

  List<Course> _resolved() {
    final dropped = <Course>{};
    for (var g = 0; g < widget.conflicts.length; g++) {
      final keep = _choices[g];
      if (keep < 0) continue;
      final group = widget.conflicts[g].courses;
      for (var i = 0; i < group.length; i++) {
        if (i != keep) dropped.add(group[i]);
      }
    }
    // 用 identical 判断对象身份，避免同名课程被误删
    return widget.allCourses
        .where((c) => !dropped.any((d) => identical(d, c)))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text('发现 ${widget.conflicts.length} 处课程冲突'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '同一时段有多门课，请选择要保留的那一门。'
                '未处理的冲突会全部保留（课表上并排显示）。',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
              const SizedBox(height: 8),
              for (var g = 0; g < widget.conflicts.length; g++) ...[
                const Divider(height: 20),
                Text(
                  '${_weekdayCn(widget.conflicts[g].day)} · '
                  '${widget.conflicts[g].sectionLabel}',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                RadioGroup<int>(
                  groupValue: _choices[g],
                  onChanged: (v) => setState(() => _choices[g] = v ?? -1),
                  child: Column(
                    children: [
                      const RadioListTile<int>(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: -1,
                        title: Text('全部保留'),
                      ),
                      for (var i = 0;
                          i < widget.conflicts[g].courses.length;
                          i++)
                        RadioListTile<int>(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          value: i,
                          title: Text(
                            widget.conflicts[g].courses[i].name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            _describe(widget.conflicts[g].courses[i]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_resolved()),
          child: const Text('确定'),
        ),
      ],
    );
  }

  static String _describe(Course c) {
    final bits = <String>[];
    if (c.teacher.isNotEmpty) bits.add(c.teacher);
    if (c.position.isNotEmpty) bits.add(c.position);
    if (c.weeks.isNotEmpty) {
      bits.add('${c.weeks.length} 周');
    }
    return bits.isEmpty ? '—' : bits.join(' · ');
  }

  static String _weekdayCn(int day) =>
      const ['', '周一', '周二', '周三', '周四', '周五', '周六', '周日']
          [day.clamp(0, 7)];
}
