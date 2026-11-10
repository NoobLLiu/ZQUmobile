/// 水电余额提醒：开关 + 规则说明 + 后台权限入口。
///
/// 说明与「水电费查询」页共用 widgets/utility_notes.dart 的同一套文案，
/// 避免两处说法不一致。
library;

import 'package:flutter/material.dart';

import '../services/profile_repository.dart';
import '../services/utility_reminder.dart';
import '../widgets/utility_notes.dart';
import 'autostart_page.dart';
import 'profile_page.dart';

/// 水电余额提醒设置页。
class UtilityAlertPage extends StatefulWidget {
  const UtilityAlertPage({super.key});

  @override
  State<UtilityAlertPage> createState() => _UtilityAlertPageState();
}

class _UtilityAlertPageState extends State<UtilityAlertPage> {
  bool _loading = true;
  bool _enabled = false;
  String _studentId = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final enabled = await UtilityReminder.isEnabled();
    final profile = await ProfileRepository.load();
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _studentId = profile.studentId;
      _loading = false;
    });
  }

  /// 开/关提醒。开启前先确认有学号、并请求通知权限。
  Future<void> _toggle(bool value) async {
    final messenger = ScaffoldMessenger.of(context);
    if (value) {
      if (_studentId.isEmpty) {
        messenger.showSnackBar(
          SnackBar(
            content: const Text('请先填写学号，才能查询到宿舍水电'),
            action: SnackBarAction(
              label: '去填写',
              onPressed: () async {
                await Navigator.of(context).push<void>(
                  MaterialPageRoute(builder: (_) => const ProfilePage()),
                );
                if (mounted) await _load();
              },
            ),
          ),
        );
        return;
      }
      final granted = await UtilityReminder.requestNotificationPermission();
      await UtilityReminder.enable();
      if (!mounted) return;
      setState(() => _enabled = true);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            granted ? '已开启提醒，正在查询一次当前余额' : '已开启提醒，但未授予通知权限，通知将无法弹出',
          ),
        ),
      );
      return;
    }
    await UtilityReminder.disable();
    if (!mounted) return;
    setState(() => _enabled = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('水电余额提醒')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Card(
                  color: scheme.surfaceContainerLow,
                  child: SwitchListTile(
                    title: const Text('余额不足时通知'),
                    value: _enabled,
                    onChanged: _toggle,
                  ),
                ),
                const SizedBox(height: 12),
                // 与查询页共用同一组件、同一文案
                const UtilityNotesCard(),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 6),
                  child: Text(
                    '后台运行',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.outline,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                Card(
                  color: scheme.surfaceContainerLow,
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    leading: const Icon(Icons.tune),
                    title: const Text('自启动与后台权限'),
                    subtitle: const Text('按机型单独开启，否则提醒会失效'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const AutostartPage(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
