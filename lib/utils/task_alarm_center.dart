import 'package:celechron/model/task.dart';
import 'package:flutter/foundation.dart';

/// 全局闹钟事件：应用在前台时由 [TaskController] 触发，
/// 通知被点击时由 [TaskReminder] 触发，界面层监听它弹出全屏闹钟。
///
/// ## 为什么要在这里记「已经弹过的提醒时刻」
///
/// 修的是一个真实反馈：**把闹钟弹窗关掉之后，它会一直重复弹**。
/// 原因是原来的去重记在 `TaskAlarmCoordinator` 里，而且写成
/// 「没有弹窗在显示时就把记录清空」——用户一点掉弹窗，下一秒记录就没了，
/// 而那条待办的提醒时刻仍在"同一分钟内"，于是又弹一次，循环不止。
///
/// 现在的规则：**按「提醒时刻」去重**（`uid@毫秒`），而且**不再因为弹窗被关闭而清空**。
/// 这样：
/// - 同一时刻弹过一次，之后无论怎么关、怎么重开 App，都不会再弹；
/// - 而改时间、或者「延迟提醒」推到的新时刻是一个**新的时刻**，自然会重新弹。
class TaskAlarmCenter {
  TaskAlarmCenter._();

  static final ValueNotifier<Task?> current = ValueNotifier<Task?>(null);

  /// 已经弹过的提醒时刻：key 是 [occurrenceKey]，value 是记录时间（用于清理旧记录）。
  static final Map<String, DateTime> _firedOccurrences = <String, DateTime>{};

  /// 一条待办 + 一个时刻 = 一次「提醒发生」
  static String occurrenceKey(Task task, DateTime at) =>
      '${task.uid}@${at.millisecondsSinceEpoch}';

  /// 这次提醒是否已经弹过
  static bool hasFired(Task task, DateTime at) =>
      _firedOccurrences.containsKey(occurrenceKey(task, at));

  /// 标记这次提醒已经弹过
  static void markFired(Task task, DateTime at) {
    _firedOccurrences[occurrenceKey(task, at)] = DateTime.now();
    prune();
  }

  /// 用户主动改过时间/延迟时，允许同一任务重新提醒：
  /// 旧的时刻记录留着无害（key 里带时间戳），这里只是把很久以前的清掉，
  /// 避免长期运行后这个 Map 无限增长。
  static void prune({Duration keep = const Duration(days: 2)}) {
    if (_firedOccurrences.length < 200) return;
    final threshold = DateTime.now().subtract(keep);
    _firedOccurrences.removeWhere((_, at) => at.isBefore(threshold));
  }

  /// 仅供测试：看当前记录条数
  @visibleForTesting
  static int get firedCount => _firedOccurrences.length;

  /// 仅供测试：清空记录
  @visibleForTesting
  static void resetForTest() => _firedOccurrences.clear();

  /// 弹全屏闹钟。**这里是唯一的入口**，所以在这里统一记「弹过了」——
  /// 前台 tick 触发、以及点通知触发，两条路都会被记上，不会互相重复弹。
  static void fire(Task task, {DateTime? occurrenceAt}) {
    markFired(task, occurrenceAt ?? task.reminderTargetTime);
    current.value = task;
  }

  static void clear() {
    current.value = null;
  }
}
