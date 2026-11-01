/// 附属日程页：管理晚自习与阳光体育时间。
///
/// 同一页分「晚自习」「阳光体育」两个分类（版式参考功能页），
/// 每个分类可新建日程；点条目进入编辑页，行尾开关控制是否合并到看板。
library;

import 'package:flutter/material.dart';

import '../models/attachment_schedule.dart';
import '../services/attachment_schedule_repository.dart';

/// 分类主题色（浅色模式底色 / 深色模式底色、文字色）。
const Color _kEveningBase = Color(0xFF5C6BC0);
const Color _kSportBase = Color(0xFFEF8C3F);

/// 附属日程页。
class AttachmentSchedulePage extends StatefulWidget {
  const AttachmentSchedulePage({super.key});

  @override
  State<AttachmentSchedulePage> createState() =>
      _AttachmentSchedulePageState();
}

class _AttachmentSchedulePageState extends State<AttachmentSchedulePage> {
  List<AttachmentSchedule> _schedules = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await AttachmentScheduleRepository.load();
    if (!mounted) return;
    setState(() => _schedules = list);
  }

  Iterable<AttachmentSchedule> _of(AttachmentScheduleType type) =>
      _schedules.where((s) => s.type == type);

  Future<void> _addOrEdit(
    AttachmentScheduleType type, [
    AttachmentSchedule? initial,
  ]) async {
    final saved = await Navigator.of(context).push<AttachmentSchedule>(
      MaterialPageRoute(
        builder: (_) => AttachmentScheduleEditPage(type: type, initial: initial),
      ),
    );
    if (saved == null) return;
    await (initial == null
        ? AttachmentScheduleRepository.add(saved)
        : AttachmentScheduleRepository.update(saved));
    if (mounted) _load();
  }

  Future<void> _toggle(AttachmentSchedule schedule, bool value) async {
    await AttachmentScheduleRepository.setEnabled(schedule.id, value);
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('附属日程')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _TypeSection(
            type: AttachmentScheduleType.eveningStudy,
            schedules: _of(AttachmentScheduleType.eveningStudy).toList(),
            onAdd: () => _addOrEdit(AttachmentScheduleType.eveningStudy),
            onEdit: (s) => _addOrEdit(s.type, s),
            onToggle: _toggle,
          ),
          const SizedBox(height: 20),
          _TypeSection(
            type: AttachmentScheduleType.sunshineSport,
            schedules: _of(AttachmentScheduleType.sunshineSport).toList(),
            onAdd: () => _addOrEdit(AttachmentScheduleType.sunshineSport),
            onEdit: (s) => _addOrEdit(s.type, s),
            onToggle: _toggle,
          ),
          const SizedBox(height: 16),
          Text(
            '附属日程按星期重复，不受教学周限制；'
            '启用后会在首页看板对应日期的课程下方展示。',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// 一个分类区块：彩色标题 + 条目卡片（末尾带「新建」行）。
class _TypeSection extends StatelessWidget {
  const _TypeSection({
    required this.type,
    required this.schedules,
    required this.onAdd,
    required this.onEdit,
    required this.onToggle,
  });

  final AttachmentScheduleType type;
  final List<AttachmentSchedule> schedules;
  final VoidCallback onAdd;
  final ValueChanged<AttachmentSchedule> onEdit;
  final void Function(AttachmentSchedule, bool) onToggle;

  Color get _base =>
      type == AttachmentScheduleType.eveningStudy ? _kEveningBase : _kSportBase;

  IconData get _icon => type == AttachmentScheduleType.eveningStudy
      ? Icons.nights_stay_outlined
      : Icons.wb_sunny_outlined;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Row(
            children: [
              Icon(_icon, size: 18, color: _base),
              const SizedBox(width: 6),
              Text(
                type.label,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              Text(
                schedules.isEmpty ? '还没有日程' : '${schedules.length} 条',
                style:
                    theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
              ),
            ],
          ),
        ),
        Card(
          color: scheme.surfaceContainerLow,
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < schedules.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    thickness: 1,
                    indent: 68,
                    color: scheme.outlineVariant.withValues(alpha: 0.4),
                  ),
                _ScheduleRow(
                  schedule: schedules[i],
                  base: _base,
                  onTap: () => onEdit(schedules[i]),
                  onToggle: (v) => onToggle(schedules[i], v),
                ),
              ],
              const Divider(height: 1, thickness: 1),
              InkWell(
                onTap: onAdd,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: _base.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.add, size: 22, color: _base),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '新建${type.label}',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: _base,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 一条日程行。
class _ScheduleRow extends StatelessWidget {
  const _ScheduleRow({
    required this.schedule,
    required this.base,
    required this.onTap,
    required this.onToggle,
  });

  final AttachmentSchedule schedule;
  final Color base;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sub = [
      schedule.timeRange,
      schedule.weekdayLabel,
      if (schedule.location.isNotEmpty) schedule.location,
    ].join(' · ');

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: base.withValues(alpha: schedule.enabled ? 0.12 : 0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                schedule.type == AttachmentScheduleType.eveningStudy
                    ? Icons.nights_stay_outlined
                    : Icons.wb_sunny_outlined,
                size: 22,
                color: schedule.enabled ? base : scheme.outline,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    schedule.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color:
                          schedule.enabled ? scheme.onSurface : scheme.outline,
                      decoration: schedule.enabled
                          ? null
                          : TextDecoration.lineThrough,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: schedule.enabled,
              onChanged: onToggle,
            ),
          ],
        ),
      ),
    );
  }
}

/// 新建 / 编辑附属日程页（版式参考常见日历应用）。
class AttachmentScheduleEditPage extends StatefulWidget {
  const AttachmentScheduleEditPage({
    super.key,
    required this.type,
    this.initial,
  });

  /// 日程类型（决定默认标题与配色）。
  final AttachmentScheduleType type;

  /// 传入则为编辑模式。
  final AttachmentSchedule? initial;

  @override
  State<AttachmentScheduleEditPage> createState() =>
      _AttachmentScheduleEditPageState();
}

class _AttachmentScheduleEditPageState
    extends State<AttachmentScheduleEditPage> {
  late AttachmentScheduleType _type =
      widget.initial?.type ?? widget.type;
  late final TextEditingController _title =
      TextEditingController(text: widget.initial?.title ?? '');
  late final TextEditingController _location =
      TextEditingController(text: widget.initial?.location ?? '');
  late final TextEditingController _note =
      TextEditingController(text: widget.initial?.note ?? '');
  late final List<int> _weekdays = widget.initial?.weekdays.toList() ??
      [1, 2, 3, 4, 5];
  late String _start = widget.initial?.start ?? '19:00';
  late String _end = widget.initial?.end ?? '21:00';
  late bool _enabled = widget.initial?.enabled ?? true;

  bool get _isEditing => widget.initial != null;

  Color get _base =>
      _type == AttachmentScheduleType.eveningStudy ? _kEveningBase : _kSportBase;

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickTime({required bool isStart}) async {
    final current = isStart ? _start : _end;
    final parts = current.split(':');
    final initial = TimeOfDay(
      hour: int.tryParse(parts.first) ?? 19,
      minute: int.tryParse(parts.last) ?? 0,
    );
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      helpText: isStart ? '选择开始时间' : '选择结束时间',
    );
    if (picked == null) return;
    String p(int n) => n.toString().padLeft(2, '0');
    setState(() {
      if (isStart) {
        _start = '${p(picked.hour)}:${p(picked.minute)}';
      } else {
        _end = '${p(picked.hour)}:${p(picked.minute)}';
      }
    });
  }

  void _toggleWeekday(int day) {
    setState(() {
      if (_weekdays.contains(day)) {
        _weekdays.remove(day);
      } else {
        _weekdays.add(day);
      }
      _weekdays.sort();
    });
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除日程'),
        content: const Text('删除后无法恢复，确定删除这条日程吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await AttachmentScheduleRepository.remove(widget.initial!.id);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _save() {
    if (!AttachmentSchedule.isValidRange(_start, _end)) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('结束时间需要晚于开始时间')),
        );
      return;
    }
    if (_weekdays.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('至少选择一个重复的星期')));
      return;
    }
    final schedule = (widget.initial ?? AttachmentSchedule(
      id: '',
      type: _type,
      title: '',
      weekdays: const [],
      start: _start,
      end: _end,
    ))
        .copyWith(
      type: _type,
      title: _title.text.trim().isEmpty ? _type.label : _title.text.trim(),
      weekdays: _weekdays,
      start: _start,
      end: _end,
      location: _location.text.trim(),
      note: _note.text.trim(),
      enabled: _enabled,
    );
    Navigator.of(context).pop(schedule);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    const weekdayNames = ['一', '二', '三', '四', '五', '六', '日'];

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? '编辑日程' : '新建${widget.type.label}'),
        actions: [
          if (_isEditing)
            IconButton(
              tooltip: '删除',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          // 类型（编辑时可切换归属分类）
          SegmentedButton<AttachmentScheduleType>(
            segments: const [
              ButtonSegment(
                value: AttachmentScheduleType.eveningStudy,
                label: Text('晚自习'),
                icon: Icon(Icons.nights_stay_outlined),
              ),
              ButtonSegment(
                value: AttachmentScheduleType.sunshineSport,
                label: Text('阳光体育'),
                icon: Icon(Icons.wb_sunny_outlined),
              ),
            ],
            selected: {_type},
            onSelectionChanged: (set) => setState(() => _type = set.first),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _title,
            maxLength: 20,
            decoration: InputDecoration(
              labelText: '名称',
              hintText: widget.type.label,
              counterText: '',
              prefixIcon: Icon(
                _type == AttachmentScheduleType.eveningStudy
                    ? Icons.nights_stay_outlined
                    : Icons.wb_sunny_outlined,
                color: _base,
              ),
            ),
          ),
          const SizedBox(height: 8),
          // 时间段
          Card(
            color: scheme.surfaceContainerLow,
            clipBehavior: Clip.antiAlias,
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _pickTime(isStart: true),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Column(
                        children: [
                          Text('开始',
                              style: theme.textTheme.labelSmall
                                  ?.copyWith(color: scheme.outline)),
                          const SizedBox(height: 4),
                          Text(
                            _start,
                            style: theme.textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Icon(Icons.arrow_forward, size: 16, color: scheme.outline),
                Expanded(
                  child: InkWell(
                    onTap: () => _pickTime(isStart: false),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Column(
                        children: [
                          Text('结束',
                              style: theme.textTheme.labelSmall
                                  ?.copyWith(color: scheme.outline)),
                          const SizedBox(height: 4),
                          Text(
                            _end,
                            style: theme.textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '重复',
            style: theme.textTheme.labelLarge?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (var i = 1; i <= 7; i++)
                FilterChip(
                  label: Text(weekdayNames[i - 1]),
                  selected: _weekdays.contains(i),
                  onSelected: (_) => _toggleWeekday(i),
                  showCheckmark: false,
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _location,
            maxLength: 30,
            decoration: const InputDecoration(
              labelText: '地点（可选）',
              hintText: '如：图书馆三楼 / 田径场',
              counterText: '',
              prefixIcon: Icon(Icons.place_outlined),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _note,
            maxLines: 2,
            maxLength: 60,
            decoration: const InputDecoration(
              labelText: '备注（可选）',
              counterText: '',
              prefixIcon: Icon(Icons.notes_outlined),
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('合并到首页看板'),
            subtitle: const Text('关闭后仅在本页展示，看板不显示'),
            value: _enabled,
            onChanged: (v) => setState(() => _enabled = v),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check),
            label: Text(_isEditing ? '保存修改' : '创建日程'),
          ),
        ],
      ),
    );
  }
}
