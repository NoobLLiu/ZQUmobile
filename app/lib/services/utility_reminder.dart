/// 水电余额提醒服务。
///
/// 开启后每整点与半点自动查询一次水电余额，余额从充足变为低于阈值
/// （见 models/utility.dart 的 kLowElectricity / kLowWater）时发系统通知。
///
/// 限制：定时器依赖应用进程存活。进程被系统清理或用户从最近任务划掉后
/// 提醒即失效，需要用户在系统设置里允许自启动/后台运行（无跨厂商 API，
/// 由「我的」页的指引弹窗说明）。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/utility.dart';
import 'profile_repository.dart';
import 'utility_provider.dart';

/// 一次检查产出的告警计划（纯数据，决策逻辑可单测）。
class UtilityAlertPlan {
  const UtilityAlertPlan({
    required this.shouldNotify,
    required this.elecLowNow,
    required this.waterLowNow,
    required this.lines,
  });

  /// 是否需要发通知。
  final bool shouldNotify;

  /// 本次检查后电费是否处于低余额状态。
  final bool elecLowNow;

  /// 本次检查后水费是否处于低余额状态。
  final bool waterLowNow;

  /// 通知正文（每个房间每个不足项一行）。
  final List<String> lines;

  Map<String, bool> toState() =>
      {'elecLow': elecLowNow, 'waterLow': waterLowNow};
}

/// 根据「上次状态 + 本次查询结果」计算告警计划。
///
/// 只在状态由充足转为不足时提醒（上次状态为 null 视为充足），
/// 避免持续低余额时每半小时重复轰炸；恢复正常后状态复位，
/// 再次变低会重新提醒。
UtilityAlertPlan planUtilityAlert({
  required bool? prevElecLow,
  required bool? prevWaterLow,
  required List<UtilityRoom> rooms,
}) {
  final elecLowNow = rooms.any((r) => isElectricityLow(r.electricity));
  final waterLowNow = rooms.any((r) => isWaterLow(r.water));

  final lines = <String>[];
  for (final room in rooms) {
    if (isElectricityLow(room.electricity)) {
      lines.add('⚡ ${room.roomName} 电费剩 ${_fmt(room.electricity)} 度'
          '（低于 ${_trim(kLowElectricity)} 度）');
    }
    if (isWaterLow(room.water)) {
      lines.add('💧 ${room.roomName} 水费剩 ${_fmt(room.water)} 吨'
          '（低于 ${_trim(kLowWater)} 吨）');
    }
  }

  final shouldNotify =
      (elecLowNow && prevElecLow != true) || (waterLowNow && prevWaterLow != true);

  return UtilityAlertPlan(
    shouldNotify: shouldNotify,
    elecLowNow: elecLowNow,
    waterLowNow: waterLowNow,
    lines: lines,
  );
}

String _fmt(double v) {
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  return v.toStringAsFixed(1);
}

String _trim(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

/// 提醒服务入口（全部静态，风格与本项目其他仓库一致）。
class UtilityReminder {
  UtilityReminder._();

  /// 开关存储键。
  static const String prefsKey = 'zsy_utility_reminder_enabled';

  /// 低余额状态存储键（json：{elecLow, waterLow}）。
  static const String _stateKey = 'zsy_utility_alert_state';

  static const int _notificationId = 1001;
  static const String _channelId = 'utility_low_balance';

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static Timer? _timer;

  static DateTime? _lastCheck;

  static bool _initialized = false;

  /// 初始化通知插件（幂等）。
  static Future<void> ensureInitialized() async {
    if (_initialized) return;
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _plugin.initialize(settings: settings);
    _initialized = true;
  }

  /// 请求 Android 13+ 的通知权限；返回是否授予。
  static Future<bool> requestNotificationPermission() async {
    final impl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final granted = await impl?.requestNotificationsPermission();
    return granted ?? true;
  }

  /// 当前开关状态。
  static Future<bool> isEnabled() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getBool(prefsKey) ?? false;
  }

  /// 开启：请求权限（由调用方先做）、立即补查一次并排定下个整点/半点。
  static Future<void> enable() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(prefsKey, true);
    await ensureInitialized();
    await checkNow();
    _scheduleNext();
  }

  /// 关闭：取消定时器，保留开关为 false。
  static Future<void> disable() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(prefsKey, false);
    _timer?.cancel();
    _timer = null;
  }

  /// App 启动时若开关已开，恢复定时与补查。
  static Future<void> startIfEnabled() async {
    if (!await isEnabled()) return;
    await ensureInitialized();
    await checkNow();
    _scheduleNext();
  }

  /// 回到前台时调用：后台被冻结错过边界则补查，并重新对齐定时器。
  static Future<void> onAppResumed() async {
    if (!await isEnabled()) return;
    final last = _lastCheck;
    final now = DateTime.now();
    if (last == null ||
        now.difference(last) > const Duration(minutes: 20)) {
      await checkNow();
    }
    _scheduleNext();
  }

  /// 立即查一次并按结果决定是否通知。
  ///
  /// 失败静默，等下个周期再试；同时刷新水电缓存供看板/查询页使用。
  static Future<void> checkNow() async {
    _lastCheck = DateTime.now();
    final profile = await ProfileRepository.load();
    if (profile.studentId.isEmpty) return;
    try {
      final snap = await UtilityDataProvider.refresh(profile.studentId);
      final rooms = snap.rooms;
      if (rooms == null || rooms.isEmpty) return;
      await _evaluate(rooms);
    } catch (_) {
      // 查询失败不打扰用户，下个整点/半点会再试。
    }
  }

  static Future<void> _evaluate(List<UtilityRoom> rooms) async {
    final sp = await SharedPreferences.getInstance();
    final prev = _decodeState(sp.getString(_stateKey));
    final plan = planUtilityAlert(
      prevElecLow: prev['elecLow'],
      prevWaterLow: prev['waterLow'],
      rooms: rooms,
    );
    await sp.setString(_stateKey, jsonEncode(plan.toState()));
    if (!plan.shouldNotify || plan.lines.isEmpty) return;
    await _showNotification(plan.lines);
  }

  static Future<void> _showNotification(List<String> lines) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        '水电余额提醒',
        channelDescription: '宿舍水电余额低于阈值时的提醒',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        styleInformation: BigTextStyleInformation(''),
      ),
    );
    await _plugin.show(
      id: _notificationId,
      title: '水电余额不足，请尽快充值',
      body: lines.join('\n'),
      notificationDetails: details,
    );
  }

  /// 对齐到下一个 :00 / :30 边界。
  static void _scheduleNext() {
    _timer?.cancel();
    final now = DateTime.now();
    final next = now.minute < 30
        ? DateTime(now.year, now.month, now.day, now.hour, 30)
        : DateTime(now.year, now.month, now.day, now.hour + 1);
    _timer = Timer(next.difference(now), () async {
      await checkNow();
      _scheduleNext();
    });
  }

  static Map<String, bool?> _decodeState(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return {
          'elecLow': decoded['elecLow'] as bool?,
          'waterLow': decoded['waterLow'] as bool?,
        };
      }
    } catch (_) {
      /* 损坏视为无历史状态 */
    }
    return const {};
  }
}
