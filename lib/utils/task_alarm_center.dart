import 'package:celechron/model/task.dart';
import 'package:flutter/foundation.dart';

/// 全局闹钟事件：应用在前台时由 [TaskController] 触发，
/// 通知被点击时由 [TaskReminder] 触发，界面层监听它弹出全屏闹钟。
class TaskAlarmCenter {
  TaskAlarmCenter._();

  static final ValueNotifier<Task?> current = ValueNotifier<Task?>(null);

  static void fire(Task task) {
    current.value = task;
  }

  static void clear() {
    current.value = null;
  }
}
