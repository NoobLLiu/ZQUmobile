/// 清空课表缓存（危险操作，单独成页）。
library;

import 'package:flutter/material.dart';

import '../models/timetable.dart';
import '../services/timetable_repository.dart';

/// 清空课表页。清空成功后按钮变为不可用，页面留在原地让用户确认结果。
class ClearTimetablePage extends StatefulWidget {
  const ClearTimetablePage({super.key});

  @override
  State<ClearTimetablePage> createState() => _ClearTimetablePageState();
}

class _ClearTimetablePageState extends State<ClearTimetablePage> {
  Timetable? _tt;
  bool _loading = true;

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
    });
  }

  Future<void> _confirmClear() async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空课表缓存'),
        content: const Text('将删除本地保存的课表数据，下次可重新从教务系统导入。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确定清空'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await TimetableRepository.clear();
    await _load();
    if (!mounted) return;
    messenger.showSnackBar(const SnackBar(content: Text('已清空课表缓存')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final count = _tt?.courses.length ?? 0;

    return Scaffold(
      appBar: AppBar(title: const Text('清空课表缓存')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: scheme.errorContainer.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            size: 18,
                            color: scheme.error,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            count == 0 ? '当前没有课表数据' : '当前已导入 $count 门课',
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: scheme.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        count == 0
                            ? '无需清空。若课表显示异常，可以重新从教务系统导入。'
                            : '清空后本地课表、看板上的今日课程都会消失，'
                                '直到你重新从教务系统导入。个人资料与水电数据不受影响。',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.55,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.tonal(
                  onPressed: count == 0 ? null : _confirmClear,
                  style: FilledButton.styleFrom(
                    backgroundColor: scheme.errorContainer,
                    foregroundColor: scheme.onErrorContainer,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: const Text('清空课表'),
                ),
              ],
            ),
    );
  }
}
