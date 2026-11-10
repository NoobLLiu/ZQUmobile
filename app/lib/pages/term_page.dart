/// 学期与开学日期：课表元信息，可从这里回教务重新导入。
library;

import 'package:flutter/material.dart';

import '../models/timetable.dart';
import '../services/timetable_repository.dart';
import 'jwgl_login_page.dart';

/// 学期信息页。
class TermPage extends StatefulWidget {
  const TermPage({super.key});

  @override
  State<TermPage> createState() => _TermPageState();
}

class _TermPageState extends State<TermPage> {
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

  /// 回教务系统重新导入（导入完成返回后刷新本页）。
  Future<void> _reimport() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const JwglLoginPage(allowImport: true),
      ),
    );
    if (!mounted) return;
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tt = _tt;

    return Scaffold(
      appBar: AppBar(title: const Text('学期与开学日期')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                if (tt == null)
                  _emptyState(theme)
                else ...[
                  Card(
                    color: scheme.surfaceContainerLow,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: Column(
                        children: [
                          _row(context, '学期', tt.termName.isEmpty ? '未获取' : tt.termName),
                          _row(context, '当前周次', _weekLabel(tt)),
                          _row(
                            context,
                            '开学日期',
                            tt.semesterStartDate.isEmpty
                                ? '未获取'
                                : '${tt.semesterStartDate}（第 1 周周一）',
                          ),
                          _row(context, '总周数', '${tt.totalWeeks} 周'),
                          _row(context, '课程数', '${tt.courses.length} 门'),
                          _row(context, '导入时间', _formatFetchedAt(tt.fetchedAt)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '学期与开学日期在导入课表时从教务系统一并获取，'
                    '用于在看板上推算今天是第几周。换学期后重新导入即可更新。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.outline,
                      height: 1.5,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _reimport,
                  icon: const Icon(Icons.sync),
                  label: const Text('从教务重新导入'),
                ),
              ],
            ),
    );
  }

  Widget _emptyState(ThemeData theme) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            Icon(
              Icons.event_busy_outlined,
              size: 44,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text('还没有课表', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            Text(
              '导入课表后这里会显示学期与开学日期',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      );

  /// 当前第几周；学期外或无法推算时给出说明。
  String _weekLabel(Timetable tt) {
    final week = tt.weekOf(DateTime.now());
    if (week == null) return '学期外';
    return '第 $week 周';
  }

  String _formatFetchedAt(String? raw) {
    if (raw == null || raw.isEmpty) return '未知';
    final t = DateTime.tryParse(raw);
    if (t == null) return raw;
    String p(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${p(t.month)}-${p(t.day)} ${p(t.hour)}:${p(t.minute)}';
  }

  Widget _row(BuildContext context, String k, String v) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Text(
              k,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
