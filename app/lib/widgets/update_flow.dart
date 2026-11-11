/// 应用内更新的整套 UI 流程：检测 → 新版本弹窗 → 下载进度 → 调起安装。
///
/// 静默模式（启动自动检测）只在发现新版本时打扰用户；手动模式
/// （关于页按钮）无论结果都给一句反馈。
library;

import 'package:flutter/material.dart';

import '../core/build_info.dart';
import '../services/update_service.dart';

/// 检测更新并按结果处理。
///
/// [silent] 为 true 时：失败、无新版本都不提示（用于启动自动检测）。
Future<void> checkForUpdate(
  BuildContext context, {
  bool silent = false,
}) async {
  final messenger = ScaffoldMessenger.of(context);

  UpdateMeta? meta;
  try {
    meta = await UpdateService.check();
  } catch (_) {}
  if (meta == null) {
    if (!silent) {
      messenger.showSnackBar(const SnackBar(
        content: Text('检测更新失败，请检查网络后重试'),
      ));
    }
    return;
  }
  if (!meta.isNewerThan(UpdateService.localVersionCode)) {
    if (!silent) {
      messenger.showSnackBar(SnackBar(
        content: Text('已是最新版本（${_latestName(meta)}）'),
      ));
    }
    return;
  }
  if (!context.mounted) return;

  final confirmed = await _showUpdateDialog(context, meta);
  if (confirmed != true || !context.mounted) return;
  await _downloadAndInstall(context, meta);
}

/// 弹窗标题里用的版本名，缺 fullVersion 时退回 version。
String _latestName(UpdateMeta meta) =>
    meta.fullVersion.isNotEmpty ? meta.fullVersion : meta.version;

/// 新版本确认弹窗。返回 true 表示用户选择更新。
Future<bool?> _showUpdateDialog(BuildContext context, UpdateMeta meta) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('发现新版本'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('最新版本 ${_latestName(meta)}，当前 ${BuildInfo.version}'),
          const SizedBox(height: 8),
          if (meta.releaseNotes.isNotEmpty)
            Text(
              meta.releaseNotes,
              style: Theme.of(ctx).textTheme.bodySmall?.copyWith(height: 1.5),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('稍后再说'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('立即更新'),
        ),
      ],
    ),
  );
}

/// 下载（进度条 + 可取消）→ 校验 → 调起安装，全程在这一个对话框里。
Future<void> _downloadAndInstall(BuildContext context, UpdateMeta meta) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _UpdateProgressDialog(meta: meta),
  );
}

class _UpdateProgressDialog extends StatefulWidget {
  const _UpdateProgressDialog({required this.meta});

  final UpdateMeta meta;

  @override
  State<_UpdateProgressDialog> createState() => _UpdateProgressDialogState();
}

class _UpdateProgressDialogState extends State<_UpdateProgressDialog> {
  double? _fraction; // null = 总长度未知，转圈
  int _received = 0;
  int _total = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() => _error = null);
    try {
      final asset = await _pickAsset();
      if (asset == null) {
        setState(() => _error = '版本清单里没有可用的安装包');
        return;
      }
      final path = await UpdateService.downloadApk(
        asset,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _received = received;
            _total = total;
            _fraction = total > 0 ? received / total : null;
          });
        },
      );
      final result = await UpdateService.install(path);
      if (!mounted) return;
      Navigator.of(context).pop();
      if (result == 'needPermission') {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('请在设置中允许「安装未知应用」，返回后重新点一次更新即可安装'),
          duration: Duration(seconds: 5),
        ));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e is UpdateException ? e.message : '下载失败：$e');
    }
  }

  /// 下载前确定设备 ABI 并挑 APK（异步查一次即可，失败有兜底）。
  Future<UpdateAsset?> _pickAsset() async {
    final abis = await UpdateService.deviceAbis();
    return UpdateService.pickAsset(widget.meta.assets, abis);
  }

  String get _progressText {
    if (_total <= 0) return '已下载 ${_mb(_received)}';
    return '${_mb(_received)} / ${_mb(_total)}'
        '（${((_fraction ?? 0) * 100).toStringAsFixed(0)}%）';
  }

  static String _mb(int bytes) =>
      bytes < 1024 * 1024 ? '${(bytes / 1024).toStringAsFixed(0)} KB' : '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('正在下载更新'),
      content: _error != null
          ? Text(_error!, style: TextStyle(color: theme.colorScheme.error))
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_fraction == null)
                  const LinearProgressIndicator()
                else
                  LinearProgressIndicator(value: _fraction!.clamp(0.0, 1.0)),
                const SizedBox(height: 8),
                Text(
                  _progressText,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
              ],
            ),
      actions: [
        if (_error != null)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        if (_error != null)
          FilledButton(onPressed: _start, child: const Text('重试')),
        if (_error == null)
          TextButton(
            onPressed: () {
              UpdateService.cancelDownload();
              Navigator.of(context).pop();
            },
            child: const Text('取消'),
          ),
      ],
    );
  }
}
