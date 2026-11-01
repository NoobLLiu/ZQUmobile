/// 水电费查询页。
///
/// 进入页面用「我的」里已填写的学号自动查询；缓存/刷新分档与看板页
/// 共用同一套策略（见 services/utility_provider.dart）：
///   - 缓存 10 分钟内：直接展示缓存，不发起请求；
///   - 缓存 10 分钟 ~ 12 小时：先展示缓存，顶部显示「正在刷新」，
///     成功后替换数据；失败则从顶部弹出横条提示；
///   - 无缓存或超过 12 小时：与首次进入一样全屏加载。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../models/utility.dart';
import '../services/profile_repository.dart';
import '../services/utility_provider.dart';
import '../widgets/profile_dialog.dart';

/// 电费低余额阈值（度），参考完美校园轮询插件默认值。
const double _kLowElectricity = 10.0;

/// 水费低余额阈值（吨），参考完美校园轮询插件默认值。
const double _kLowWater = 1.0;

/// 电费主题色（琥珀色）。
const Color _kElectricityColor = Color(0xFFE8930C);

/// 页面状态。
enum _Phase { loading, content, error }

/// 水电费查询页。
class UtilityPage extends StatefulWidget {
  const UtilityPage({super.key});

  @override
  State<UtilityPage> createState() => _UtilityPageState();
}

class _UtilityPageState extends State<UtilityPage> {
  _Phase _phase = _Phase.loading;

  /// 当前展示的数据（可能来自缓存）。
  List<UtilityRoom>? _rooms;

  /// 当前展示数据的获取时间。
  DateTime? _fetchedAt;

  /// 后台刷新中（顶部显示“正在刷新”条）。
  bool _refreshing = false;

  /// 是否因未填写学号而停在错误页。
  bool _needsProfile = false;

  String _message = '';

  String _studentId = '';

  /// “刷新失败”横条自动消失计时器。
  Timer? _bannerTimer;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    super.dispose();
  }

  /// 进入页面：读学号与缓存，按缓存年龄决定展示策略。
  Future<void> _init() async {
    setState(() {
      _phase = _Phase.loading;
      _needsProfile = false;
    });
    final profile = await ProfileRepository.load();
    if (!mounted) return;
    if (!profile.isComplete) {
      setState(() {
        _phase = _Phase.error;
        _needsProfile = true;
        _message = '尚未填写学号，填写后即可查询宿舍水电费';
      });
      return;
    }
    _studentId = profile.studentId;

    // 与看板页共用同一套缓存/刷新策略。
    final snap = await UtilityDataProvider.load(_studentId);
    if (!mounted) return;

    if (snap.rooms != null) {
      setState(() {
        _rooms = snap.rooms;
        _fetchedAt = snap.fetchedAt;
        _phase = _Phase.content;
      });
      // 超出新鲜期但未过期则后台刷新。
      if (snap.shouldRefresh) _refresh(showFullLoading: false);
      return;
    }
    // 无缓存或超过 12 小时：与首次进入一样全屏加载。
    _refresh(showFullLoading: true);
  }

  /// 查询水电费。
  ///
  /// [showFullLoading] 为 true 时全屏加载（无可用数据）；
  /// 为 false 时后台刷新（已有缓存数据在展示）。
  Future<void> _refresh({required bool showFullLoading}) async {
    setState(() {
      if (showFullLoading) {
        _phase = _Phase.loading;
      } else {
        _refreshing = true;
      }
    });
    final snap = await UtilityDataProvider.refresh(_studentId);
    if (!mounted) return;
    if (snap.rooms != null) {
      setState(() {
        _rooms = snap.rooms;
        _fetchedAt = snap.fetchedAt;
        _refreshing = false;
        _phase = _Phase.content;
      });
      return;
    }
    final message = snap.error ?? '获取失败，请稍后重试';
    if (showFullLoading) {
      setState(() {
        _refreshing = false;
        _phase = _Phase.error;
        _message = message;
      });
    } else {
      setState(() => _refreshing = false);
      _showFailureBanner(message);
    }
  }

  /// 从顶部弹出“刷新失败”横条（自动消失）。
  void _showFailureBanner(String message) {
    _bannerTimer?.cancel();
    final theme = Theme.of(context);
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..clearMaterialBanners()
      ..showMaterialBanner(
        MaterialBanner(
          backgroundColor: theme.colorScheme.errorContainer,
          leading: Icon(
            Icons.cloud_off_outlined,
            color: theme.colorScheme.onErrorContainer,
          ),
          content: Text(
            '刷新失败：$message（仍展示缓存数据）',
            style: TextStyle(color: theme.colorScheme.onErrorContainer),
          ),
          actions: [
            TextButton(
              onPressed: messenger.clearMaterialBanners,
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    _bannerTimer = Timer(
      const Duration(seconds: 4),
      messenger.clearMaterialBanners,
    );
  }

  /// 未填写学号时引导填写。
  Future<void> _editProfile() async {
    final profile = await ProfileRepository.load();
    if (!mounted) return;
    final updated = await showProfileDialog(context, initial: profile);
    if (updated == null) return;
    await ProfileRepository.save(updated);
    if (!mounted) return;
    _init();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('水电费查询'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _refreshing
                ? null
                : () => _refresh(showFullLoading: _rooms == null),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: switch (_phase) {
        _Phase.loading => const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('正在获取水电费…'),
            ],
          ),
        ),
        _Phase.error => _buildError(),
        _Phase.content => _buildContent(),
      },
    );
  }

  /// 错误页：说明原因，可重试或去填写学号。
  Widget _buildError() {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text('获取失败', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              _message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _needsProfile
                  ? _editProfile
                  : () => _refresh(showFullLoading: true),
              icon: Icon(_needsProfile ? Icons.badge_outlined : Icons.refresh),
              label: Text(_needsProfile ? '去填写学号' : '重新查询'),
            ),
          ],
        ),
      ),
    );
  }

  /// 内容页：顶部刷新条 + 房间卡片列表。
  Widget _buildContent() {
    final rooms = _rooms!;
    return Column(
      children: [
        // 顶部“正在刷新”条（后台刷新时出现）。
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          child: _refreshing
              ? const _RefreshingBar()
              : const SizedBox(width: double.infinity),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              for (final room in rooms) _RoomCard(room: room),
              const SizedBox(height: 8),
              Text(
                '更新于 ${_formatTime(_fetchedAt)} · 数据来自完美校园',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatTime(DateTime? t) {
    if (t == null) return '未知';
    String p(int n) => n.toString().padLeft(2, '0');
    return '${t.month}-${p(t.day)} ${p(t.hour)}:${p(t.minute)}';
  }
}

/// 顶部“正在刷新”细条。
class _RefreshingBar extends StatelessWidget {
  const _RefreshingBar();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Text(
            '正在刷新…',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 一个房间的水电余额卡片。
class _RoomCard extends StatelessWidget {
  const _RoomCard({required this.room});

  final UtilityRoom room;

  bool get _elecLow => room.electricity <= _kLowElectricity;

  bool get _waterLow => room.water <= _kLowWater;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final warnings = <String>[
      if (_elecLow) '⚡ 电费余额不足，建议尽快充值',
      if (_waterLow) '💧 水费余额不足，建议尽快充值',
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.home_outlined,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    room.roomName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _BalanceTile(
                    icon: Icons.bolt,
                    label: '电费余额',
                    value: room.electricity,
                    unit: '度',
                    color: _kElectricityColor,
                    low: _elecLow,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _BalanceTile(
                    icon: Icons.water_drop_outlined,
                    label: '水费余额',
                    value: room.water,
                    unit: '吨',
                    color: theme.colorScheme.primary,
                    low: _waterLow,
                  ),
                ),
              ],
            ),
            if (warnings.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer.withValues(
                    alpha: 0.5,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  warnings.join('\n'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 单个余额块：图标 + 标签 + 大字号数值，低余额时变红警示。
class _BalanceTile extends StatelessWidget {
  const _BalanceTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
    required this.low,
  });

  final IconData icon;
  final String label;
  final double value;
  final String unit;
  final Color color;

  /// 是否低于阈值（变红 + 提示）。
  final bool low;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final valueColor = low ? theme.colorScheme.error : color;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: valueColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: low
              ? valueColor.withValues(alpha: 0.4)
              : valueColor.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: valueColor),
              const SizedBox(width: 4),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value.toStringAsFixed(2),
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: valueColor,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 3),
              Text(
                unit,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ),
          if (low) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 13,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(width: 2),
                Text(
                  '余额不足',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
