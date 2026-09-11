import 'package:celechron/database/database_helper.dart';
import 'package:celechron/mod/database_mod.dart';
import 'package:celechron/model/task.dart';
import 'package:celechron/utils/task_alarm_center.dart';
import 'package:celechron/utils/task_reminder.dart';
import 'package:get/get.dart';

/// ============ 待办魔改：从 task_controller.dart 里抽出来的逻辑 ============
///
/// 这个文件里的东西全部属于魔改，**上游不会碰**，所以放在这里而不是塞进
/// `lib/page/task/task_controller.dart`——那个文件上游在持续维护，我们留在
/// 里面的东西越多，将来跟版冲突就越多。
///
/// 接缝只保留几个一行的调用点，用 `// ===== MOD =====` 标记。
class TaskAlarmCoordinator {
  TaskAlarmCoordinator._();

  /// 已经弹过的待办，避免同一分钟反复弹
  static final Set<String> _fired = <String>{};

  /// 每秒调用：闹钟模式下，前台到点就弹出全屏闹钟
  static void tick(List<Task> taskList) {
    if (TaskAlarmCenter.current.value == null) {
      _fired.clear();
    }
    if (TaskReminder.mode != TaskReminder.modeAlarm) return;
    if (TaskAlarmCenter.current.value != null) return;

    final now = DateTime.now();
    for (final task in taskList) {
      // ===== P1：活动 / 截止 / 提醒 都要能在闹钟模式下弹出来（备忘不调度）=====
      if (!task.schedulesReminder) continue;
      if (task.status != TaskStatus.running &&
          task.status != TaskStatus.suspended) {
        continue;
      }
      // 刚点过「延迟提醒」：延后时间之前不再弹（否则延迟完立刻又响）
      final snoozedUntil = TaskReminder.snoozedUntil(task.uid);
      if (snoozedUntil != null && snoozedUntil.isAfter(now)) continue;

      final fireAt = task.reminderTargetTime;
      if (fireAt.isAfter(now)) continue;
      if (now.difference(fireAt).inMinutes >= 1) continue;
      if (_fired.contains(task.uid)) continue;
      _fired.add(task.uid);
      TaskAlarmCenter.fire(task);
      return;
    }
  }
}

/// 兼容旧数据：普通待办不该有开始时间（早期版本会写成「截止前 1 分钟」）。
///
/// 返回是否改动过（上游用 changed 门控写库，所以要如实汇报）。
bool normalizeLegacyTask(Task task) {
  if (task.type != TaskType.deadline) return false;
  if (task.startTime == task.endTime) return false;
  task.startTime = task.endTime;
  return true;
}

/// 周期性待办：完成之后自动生成下一次。
///
/// 用 `fromUid` 标记，避免每秒重复生成；带时段的重复待办同样会生成下一期。
/// 返回是否有新增（供上游的 changed 门控使用）。
bool spawnNextOccurrences(List<Task> taskList) {
  final spawnedFrom = taskList
      .where((element) => element.fromUid != null)
      .map((element) => element.fromUid!)
      .toSet();
  final nextOccurrences = <Task>[];
  for (final task in taskList) {
    if (task.type == TaskType.fixedlegacy) continue;
    if (task.status != TaskStatus.completed) continue;
    if (task.repeatType == TaskRepeatType.norepeat) continue;
    if (spawnedFrom.contains(task.uid)) continue;

    final next = task.copyWith();
    next.genUid();
    next.fromUid = task.uid;
    next.status = TaskStatus.running;
    if (!next.advanceRepeatPeriod()) continue;
    if (next.status == TaskStatus.outdated) continue;
    next.forceRefreshStatus();
    if (next.status != TaskStatus.running) continue;
    nextOccurrences.add(next);
    spawnedFrom.add(task.uid);
  }
  if (nextOccurrences.isEmpty) return false;
  taskList.addAll(nextOccurrences);
  return true;
}

/// 同步本地提醒（内部有签名缓存，未变化时不会重复调度）。
void syncTaskReminders(List<Task> taskList) {
  TaskReminder.mode = Get.find<DatabaseHelper>(tag: 'db').getReminderMode();
  TaskReminder.syncAll(taskList);
}

/// 删除待办时留墓碑：同步合并时才知道这条是被删的，而不是新加的。
class TaskTombstoneStore {
  TaskTombstoneStore._();

  /// 移除列表里所有 `status == deleted` 的待办并记墓碑；返回是否有删除动作
  static bool removeDeleted(List<Task> taskList) {
    final deleted =
        taskList.where((element) => element.status == TaskStatus.deleted);
    return remove(taskList, deleted);
  }

  static bool remove(List<Task> taskList, Iterable<Task> tasks) {
    final list = tasks.toList();
    if (list.isEmpty) return false;
    final uids = <String>[];
    for (final task in list) {
      if (task.uid.isEmpty) continue;
      // legacy 的《过去日程》副本属于本地派生数据，不留墓碑
      // （它们挂在原日程的 fromUid 上，原日程被删时合并逻辑会一并清掉）。
      if (task.type != TaskType.fixedlegacy) uids.add(task.uid);
    }
    if (uids.isNotEmpty) {
      Get.find<DatabaseHelper>(tag: 'db').addTombstones(uids);
    }
    taskList.removeWhere((element) => list.contains(element));
    return true;
  }
}
