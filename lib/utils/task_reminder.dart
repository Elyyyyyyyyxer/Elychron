import 'dart:io';

import 'package:celechron/database/database_helper.dart';
import 'package:celechron/design/task_detail_nav.dart';
import 'package:celechron/model/task.dart';
import 'package:celechron/utils/task_alarm_center.dart';
import 'package:celechron/utils/global.dart';
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
    // 注意：Android 的通知渠道一旦创建就**不可修改**（重要度/声音/音量流都锁死）。
    // 早期版本建的渠道被系统降过级（实测 mOriginalImp=5 但 effective=3），
    // 所以这里换新渠道名，才能拿到正确的重要度与音量流。
    'task_reminder_v3',
    '待办提醒',
    channelDescription: '待办截止提醒：横幅弹出 + 响铃',
    importance: Importance.max,
    priority: Priority.high,
    category: AndroidNotificationCategory.reminder,
    actions: _actions,
  );

  static const AndroidNotificationDetails _alarmDetails =
      AndroidNotificationDetails(
    'task_reminder_alarm_v2',
    '待办闹钟',
    channelDescription: '闹钟模式：全屏提醒 + 闹钟铃声，可延迟或划掉',
    importance: Importance.max,
    priority: Priority.max,
    category: AndroidNotificationCategory.alarm,
    fullScreenIntent: true,
    playSound: true,
    enableVibration: true,
    // 走「闹钟」音量流：否则默认用通知音量流，静音模式/音量低时就听不见，
    // 也不会像系统闹钟那样绕过免打扰
    audioAttributesUsage: AudioAttributesUsage.alarm,
    ongoing: true,
    autoCancel: false,
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

      // 冷启动路径：App 是被闹钟通知（全屏 Intent）拉起来的。
      // 这种情况 **不会** 走 onDidReceiveNotificationResponse，必须读这个接口，
      // 否则用户必须先手动打开 App 才会响 —— 这正是「不像系统闹钟」的原因。
      try {
        final launch = await _plugin.getNotificationAppLaunchDetails();
        final response = launch?.notificationResponse;
        if ((launch?.didNotificationLaunchApp ?? false) && response != null) {
          // 等首页把闹钟监听挂上（首页 initState 在启动后一小会儿才跑）
          Future<void>.delayed(const Duration(milliseconds: 900), () {
            _onResponse(response);
          });
        }
      } catch (_) {
        // 拿不到就算了，不影响正常提醒
      }
    } catch (_) {
      // 通知不可用时静默降级，不影响任务本身。
    }
  }

  /// 点通知 / 点通知上的按钮
  static Future<void> _onResponse(NotificationResponse response) async {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;

    // 「延迟 / 划掉」只可能来自任务级通知（子待办只走普通通知，没有按钮）
    if (response.actionId == 'snooze') {
      final task = _findTask(payload);
      if (task != null) await snooze(task, const Duration(minutes: 10));
      return;
    }
    if (response.actionId == 'dismiss') {
      TaskAlarmCenter.clear();
      return;
    }

    // ===== P2：子待办通知 → 进父任务详情页并高亮这一步 =====
    if (payload.startsWith(subtaskPayloadPrefix)) {
      final parts = payload.split(':');
      if (parts.length < 3) return;
      final task = _findTask(parts[1]);
      if (task != null) {
        await _openTaskDetail(task, highlightSubtaskUid: parts[2]);
      }
      return;
    }

    final task = _findTask(payload);
    if (task == null) return;
    // 闹钟模式：弹全屏闹钟；通知模式：直接进这条待办的详情页
    if (mode == modeAlarm) {
      TaskAlarmCenter.fire(task);
    } else {
      await _openTaskDetail(task);
    }
  }

  /// 从通知进详情页：这条路径没有调用方接返回值，所以结果由 openTaskDetail 写回。
  static Future<void> _openTaskDetail(
    Task task, {
    String? highlightSubtaskUid,
  }) async {
    try {
      final context = navigatorKey.currentContext;
      if (context == null || !context.mounted) return;
      await openTaskDetail(
        context,
        task,
        highlightSubtaskUid: highlightSubtaskUid,
      );
    } catch (_) {
      // 打不开就算了，通知本身已经起到提醒作用
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

  // ===== P2：行程型子待办的通知调度 =====
  //
  // 单独一套 key（`sub:<任务uid>:<子待办uid>`）与通知 id，避免和任务级撞车。
  // 子待办**只走普通通知**，不走全屏闹钟 —— 否则一上午会被闹钟连炸。

  static const String subtaskPayloadPrefix = 'sub:';

  static String _subKey(String taskUid, String subUid) =>
      '$subtaskPayloadPrefix$taskUid:$subUid';

  static String _subPayload(String taskUid, String subUid) =>
      '$subtaskPayloadPrefix$taskUid:$subUid';

  /// 设置里的「默认提醒提前量」（分钟）；拿不到就用 30。
  static int get _defaultLeadMinutes {
    try {
      if (Get.isRegistered<DatabaseHelper>(tag: 'db')) {
        return Get.find<DatabaseHelper>(tag: 'db').getReminderLeadMinutes();
      }
    } catch (_) {}
    return 30;
  }

  /// 这一步该在什么时候响；None（null）表示不用调度。
  static DateTime? _subFireTimeOf(Task task, SubTask sub) {
    if (task.status != TaskStatus.running &&
        task.status != TaskStatus.suspended) {
      return null;
    }
    final when = sub.reminderAt(_defaultLeadMinutes);
    if (when == null) return null;
    return when.isAfter(DateTime.now()) ? when : null;
  }

  static String _subSignatureOf(Task task, SubTask sub) => [
        task.status.index,
        sub.done,
        sub.title,
        sub.startTime?.millisecondsSinceEpoch,
        sub.endTime?.millisecondsSinceEpoch,
        sub.reminderMinutes,
        _defaultLeadMinutes,
      ].join('|');

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
    // 活动 / 截止 / 提醒 三类都调度；备忘型永不调度。
    // schedulesReminder 已内含 reminderEnabled 与备忘判定。
    if (!task.schedulesReminder) return false;
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
      if (_synced[task.uid] == signature) {
        // 任务级没变化，但子待办可能变了：仍然走一遍（下面的签名判断很快）
      } else {
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

      // ===== P2：行程型子待办各自提醒 =====
      for (final sub in task.subtasks) {
        final key = _subKey(task.uid, sub.uid);
        alive.add(key);
        final subSignature = _subSignatureOf(task, sub);
        if (_synced[key] == subSignature) continue;
        final subId = _idOf(key);
        try {
          await _plugin.cancel(subId);
          final when = _subFireTimeOf(task, sub);
          if (when != null) {
            await _requestExactAlarmOnce();
            await _scheduleSubtask(task, sub, subId, when);
          }
        } catch (_) {
          // 同上：失败也记签名，别每秒重试
        } finally {
          _synced[key] = subSignature;
        }
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

  /// 行程型子待办的通知：只有「通知」这一条路，永远不用闹钟那套详情。
  static Future<void> _scheduleSubtask(
    Task task,
    SubTask sub,
    int id,
    DateTime when,
  ) async {
    final fireAt = tz.TZDateTime.from(when, tz.local);
    final title = sub.title.isEmpty
        ? (task.summary.isEmpty ? '下一步' : task.summary)
        : sub.title;
    final bodyParts = <String>[];
    if (task.summary.isNotEmpty) bodyParts.add(task.summary);
    if (sub.anchorTime != null) {
      bodyParts.add(TimeHelper.chineseDateTime(sub.anchorTime!));
    }
    if (sub.location.isNotEmpty) bodyParts.add(sub.location);
    final body = bodyParts.isEmpty ? '到点了，这一步该开始了' : bodyParts.join(' · ');
    final payload = _subPayload(task.uid, sub.uid);
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
        payload: payload,
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
        payload: payload,
      );
    }
  }

  /// ===== P3：专注休息提示 =====
  ///
  /// 工作段走完、进入休息时弹一条普通通知，提醒起来走走。
  /// 刻意**不走闹钟那套**（休息提示不该像闹钟一样炸），也刻意不走
  /// 「待办提醒」渠道 —— 它是另一件事，用户想单独静音也方便。
  static const NotificationDetails _focusDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'focus_rest_v1',
      '专注休息提醒',
      channelDescription: '专注计时进入休息时提醒起来走走',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
    ),
    iOS: DarwinNotificationDetails(),
  );

  /// 休息提示的固定通知 id：一次专注只该有一条，新的覆盖旧的、不堆一屏
  static const int focusRestNoticeId = 0x5f0c5;

  /// **预先把「该休息了」排进系统**（专注页进入工作段时调用）。
  ///
  /// 为什么不能「等页面 tick 到点再弹」：锁屏 / 切后台之后 Dart 定时器会被
  /// 系统挂起，那一秒根本不会到来 —— 等用户回到前台才补弹，已经错过时机。
  /// 而专注最典型的用法恰好就是**扣在桌上锁屏**。
  ///
  /// [at] 已经过去（比如剩余不到一秒）时就直接弹一条。
  static Future<void> scheduleFocusRestNotice({
    required DateTime at,
    String? label,
  }) async {
    try {
      await _ensureInit();
      await _plugin.cancel(focusRestNoticeId);
      final body = (label == null || label.trim().isEmpty)
          ? '这一轮工作了 ${_focusWorkLabel()}，起来走走、喝口水。'
          : '「${label.trim()}」这一轮结束了，起来走走、喝口水。';
      if (!at.isAfter(DateTime.now())) {
        await _plugin.show(focusRestNoticeId, '该休息了', body, _focusDetails);
        return;
      }
      await _requestExactAlarmOnce();
      final fireAt = tz.TZDateTime.from(at, tz.local);
      try {
        await _plugin.zonedSchedule(
          focusRestNoticeId,
          '该休息了',
          body,
          fireAt,
          _focusDetails,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      } catch (_) {
        await _plugin.zonedSchedule(
          focusRestNoticeId,
          '该休息了',
          body,
          fireAt,
          _focusDetails,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      }
    } catch (_) {
      // 通知不可用时静默降级：专注本身照常计时
    }
  }

  /// 撤销还没到点的「该休息了」（暂停 / 跳过休息 / 提前结束 / 离开页面时用）
  static Future<void> cancelFocusRestNotice() async {
    try {
      await _ensureInit();
      await _plugin.cancel(focusRestNoticeId);
    } catch (_) {}
  }

  /// 立刻弹一条休息提示（排程不可用时的兜底）
  static Future<void> showFocusRestNotice({String? label}) async {
    try {
      await _ensureInit();
      final body = (label == null || label.trim().isEmpty)
          ? '这一轮工作了 ${_focusWorkLabel()}，起来走走、喝口水。'
          : '「${label.trim()}」这一轮结束了，起来走走、喝口水。';
      await _plugin.show(focusRestNoticeId, '该休息了', body, _focusDetails);
    } catch (_) {
      // 通知不可用时静默降级：专注本身照常计时
    }
  }

  static String _focusWorkLabel() {
    try {
      if (Get.isRegistered<DatabaseHelper>(tag: 'db')) {
        final minutes = Get.find<DatabaseHelper>(tag: 'db').getFocusWorkMinutes();
        if (minutes % 60 == 0) return '${minutes ~/ 60} 小时';
        return '$minutes 分钟';
      }
    } catch (_) {}
    return '一段时间';
  }

  /// 延迟提醒：推迟 [delay] 后再响一次。
  /// 是否处于「已延迟」状态（前台每秒检查要用它，否则刚延迟完又会立刻弹）
  static DateTime? snoozedUntil(String uid) => _snoozed[uid];

  static Future<void> snooze(Task task, Duration delay) async {
    await _ensureInit();
    final until = DateTime.now().add(delay);
    _snoozed[task.uid] = until;
    _synced.remove(task.uid);
    // 关键：把待办**真实的提醒时间**也往后挪。
    // 原来只改了通知调度，Task.reminderTargetTime 还停在过去，
    // 于是闹钟页一关（前台去重集合被清空）下一秒就立刻再弹一次。
    // 改字段之后：前台检查、通知调度、下次启动三处看到的是同一个未来时间。
    task.reminderEnabled = true;
    task.reminderTime = until;
    task.updatedAt = DateTime.now();
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
