import 'dart:io';

import 'package:celechron/model/task.dart';
import 'package:celechron/utils/task_alarm_center.dart';
import 'package:celechron/utils/time_helper.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get/get.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// 任务截止提醒：把开启提醒的任务同步成本地通知。
///
/// 两种形态（由设置里的「提醒方式」决定）：
/// - [modeNotification]：横幅通知 + 响铃（类似钉钉）
/// - [modeAlarm]：闹钟模式，全屏提醒，可「延迟提醒 / 划掉」
class TaskReminder {
  TaskReminder._();

  static const int modeNotification = 0;
  static const int modeAlarm = 1;

  /// 当前提醒方式（由 TaskController 每次同步时写入）
  static int mode = modeNotification;

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _askedExactAlarm = false;
  static Future<void>? _initFuture;

  /// uid -> 上次同步时的签名
  static final Map<String, String> _synced = <String, String>{};

  /// uid -> 延迟提醒到什么时候
  static final Map<String, DateTime> _snoozed = <String, DateTime>{};

  static const List<AndroidNotificationAction> _actions = [
    AndroidNotificationAction('snooze', '延迟提醒', showsUserInterface: true),
    AndroidNotificationAction('dismiss', '划掉',
        showsUserInterface: false, cancelNotification: true),
  ];

  static const AndroidNotificationDetails _notificationDetails =
      AndroidNotificationDetails(
    'task_reminder_v2',
    '待办提醒',
    channelDescription: '待办截止提醒：横幅弹出 + 响铃',
    importance: Importance.max,
    priority: Priority.high,
    category: AndroidNotificationCategory.reminder,
    actions: _actions,
  );

  static const AndroidNotificationDetails _alarmDetails =
      AndroidNotificationDetails(
    'task_reminder_alarm',
    '待办闹钟',
    channelDescription: '闹钟模式：全屏提醒 + 闹钟铃声，可延迟或划掉',
    importance: Importance.max,
    priority: Priority.max,
    category: AndroidNotificationCategory.alarm,
    fullScreenIntent: true,
    playSound: true,
    enableVibration: true,
    actions: _actions,
  );

  static NotificationDetails get _details => NotificationDetails(
        android: mode == modeAlarm ? _alarmDetails : _notificationDetails,
        iOS: const DarwinNotificationDetails(),
        macOS: const DarwinNotificationDetails(),
      );

  /// 只初始化一次；用 Future 缓存避免并发调用时插件还没初始化好就被使用。
  static Future<void> _ensureInit() => _initFuture ??= _doInit();

  static Future<void> _doInit() async {
    if (!Platform.isAndroid && !Platform.isIOS && !Platform.isMacOS) return;

    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
    } catch (_) {
      // 时区库异常时退回 UTC，避免启动崩溃。
    }

    const initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
      macOS: DarwinInitializationSettings(),
    );
    try {
      await _plugin.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: _onResponse,
      );
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();
    } catch (_) {
      // 通知不可用时静默降级，不影响任务本身。
    }
  }

  /// 点通知 / 点通知上的按钮
  static Future<void> _onResponse(NotificationResponse response) async {
    final uid = response.payload;
    if (uid == null || uid.isEmpty) return;
    final task = _findTask(uid);

    if (response.actionId == 'snooze') {
      if (task != null) {
        await snooze(task, const Duration(minutes: 10));
      }
      return;
    }
    if (response.actionId == 'dismiss') {
      TaskAlarmCenter.clear();
      return;
    }
    // 点通知本体：闹钟模式下弹出全屏闹钟
    if (task != null && mode == modeAlarm) {
      TaskAlarmCenter.fire(task);
    }
  }

  static Task? _findTask(String uid) {
    try {
      final list = Get.find<RxList<Task>>(tag: 'taskList');
      for (final task in list) {
        if (task.uid == uid) return task;
      }
    } catch (_) {}
    return null;
  }

  static int _idOf(String uid) => uid.hashCode & 0x7fffffff;

  static DateTime _fireTimeOf(Task task) =>
      _snoozed[task.uid] ?? task.reminderTargetTime;

  static String _signatureOf(Task task) => [
        task.reminderEnabled,
        _fireTimeOf(task).millisecondsSinceEpoch,
        task.status.index,
        task.summary,
        mode,
      ].join('|');

  static bool _shouldSchedule(Task task) {
    if (!task.reminderEnabled) return false;
    if (task.type != TaskType.deadline) return false;
    if (task.status != TaskStatus.running &&
        task.status != TaskStatus.suspended) {
      return false;
    }
    return _fireTimeOf(task).isAfter(DateTime.now());
  }

  static Future<void> _requestExactAlarmOnce() async {
    if (_askedExactAlarm) return;
    _askedExactAlarm = true;
    if (!Platform.isAndroid) return;
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestExactAlarmsPermission();
    } catch (_) {
      // 用户拒绝精确闹钟权限时走非精确调度。
    }
  }

  /// 把整个任务列表的提醒状态与系统通知对齐。
  static Future<void> syncAll(List<Task> tasks) async {
    if (tasks.isEmpty && _synced.isEmpty) return;
    await _ensureInit();

    final alive = <String>{};
    for (final task in tasks) {
      alive.add(task.uid);
      final signature = _signatureOf(task);
      if (_synced[task.uid] == signature) continue;

      final id = _idOf(task.uid);
      try {
        await _plugin.cancel(id);
        if (_shouldSchedule(task)) {
          await _requestExactAlarmOnce();
          await _schedule(task, id, _fireTimeOf(task));
        }
      } catch (_) {
        // 失败也记下签名，避免每秒重试刷屏；数据变化或下次启动时会重新同步。
      } finally {
        _synced[task.uid] = signature;
      }
    }

    // 清理已经不存在（被彻底删除）的任务的缓存与通知。
    final stale = _synced.keys.where((uid) => !alive.contains(uid)).toList();
    for (final uid in stale) {
      _synced.remove(uid);
      _snoozed.remove(uid);
      try {
        await _plugin.cancel(_idOf(uid));
      } catch (_) {}
    }
  }

  static Future<void> _schedule(Task task, int id, DateTime when) async {
    final fireAt = tz.TZDateTime.from(when, tz.local);
    final title = task.summary.isEmpty ? '待办提醒' : task.summary;
    final body = '截止于 ${TimeHelper.chineseDateTime(task.endTime)}';
    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        fireAt,
        _details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: task.uid,
      );
    } catch (_) {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        fireAt,
        _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: task.uid,
      );
    }
  }

  /// 延迟提醒：推迟 [delay] 后再响一次。
  static Future<void> snooze(Task task, Duration delay) async {
    await _ensureInit();
    _snoozed[task.uid] = DateTime.now().add(delay);
    _synced.remove(task.uid);
    try {
      await _plugin.cancel(_idOf(task.uid));
    } catch (_) {}
    await _schedule(task, _idOf(task.uid), _snoozed[task.uid]!);
  }

  /// 划掉：停掉这次提醒（不改任务本身的提醒设置）。
  static Future<void> dismissAlarm(Task task) async {
    await _ensureInit();
    _snoozed.remove(task.uid);
    _synced.remove(task.uid);
    try {
      await _plugin.cancel(_idOf(task.uid));
    } catch (_) {}
  }

  /// 任务被删除时立刻撤销提醒。
  static Future<void> cancel(Task task) async {
    _synced.remove(task.uid);
    _snoozed.remove(task.uid);
    await _ensureInit();
    try {
      await _plugin.cancel(_idOf(task.uid));
    } catch (_) {}
  }
}
