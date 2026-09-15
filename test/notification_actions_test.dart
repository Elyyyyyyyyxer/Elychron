import 'package:celechron/utils/task_reminder.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

/// 通知按钮的声明 —— 钉住一个真机反馈抓出来的 bug。
///
/// 用户原话：「横幅通知点划掉没有反应，只能点击延迟」。
/// 原因是「划掉」声明成了 `showsUserInterface: false`：这种按钮**不会把 App
/// 拉到前台**，响应只会送到后台 isolate，而后台 isolate 碰不到前台界面 ——
/// 于是通知是取消了，但**全屏闹钟照样响**。「延迟提醒」是 `true`，所以一直能用。
void main() {
  AndroidNotificationAction actionNamed(List<AndroidNotificationAction> list,
      String id) {
    return list.firstWhere((a) => a.id == id);
  }

  test('★ 闹钟模式下「划掉」必须走前台（否则闹钟停不下来）', () {
    final actions = TaskReminder.actionsFor(TaskReminder.modeAlarm);
    expect(actionNamed(actions, 'dismiss').showsUserInterface, isTrue);
    // 取消通知这件事两种模式都要
    expect(actionNamed(actions, 'dismiss').cancelNotification, isTrue);
  });

  test('通知模式下「划掉」保持纯后台（不必把 App 弹出来）', () {
    final actions = TaskReminder.actionsFor(TaskReminder.modeNotification);
    expect(actionNamed(actions, 'dismiss').showsUserInterface, isFalse);
    expect(actionNamed(actions, 'dismiss').cancelNotification, isTrue);
  });

  test('「延迟提醒」两种模式都要能拉起 App（它要改时间、落库）', () {
    for (final mode in [TaskReminder.modeAlarm, TaskReminder.modeNotification]) {
      final actions = TaskReminder.actionsFor(mode);
      expect(actionNamed(actions, 'snooze').showsUserInterface, isTrue);
    }
  });

  test('两种模式都提供「延迟提醒」与「划掉」两个按钮', () {
    for (final mode in [TaskReminder.modeAlarm, TaskReminder.modeNotification]) {
      final ids = TaskReminder.actionsFor(mode).map((a) => a.id).toList();
      expect(ids, containsAll(<String>['snooze', 'dismiss']));
      expect(ids.length, 2);
    }
  });
}
