import 'dart:async';
import 'package:get/get.dart';
import 'package:celechron/database/database_helper.dart';
// ===== MOD: 分类/排序/筛选逻辑在 lib/mod/task_list_filter_mod.dart =====
import 'package:celechron/mod/task_list_filter_mod.dart';
import 'package:celechron/model/task.dart';
// ===== MOD: 魔改逻辑集中在 lib/mod/ 下，本文件只留调用点 =====
import 'package:celechron/mod/loop_guard.dart';
import 'package:celechron/mod/task_runtime_mod.dart';
import 'package:celechron/utils/utils.dart';

class TaskController extends GetxController with TaskListFilterMod {
  // ===== MOD: 标签页名字（static 不能放 mixin，留着也是魔改的一部分）=====
  static const List<String> tabNames = ['待我处理', '优先处理', '我已处理', '星标'];
  final taskList = Get.find<RxList<Task>>(tag: 'taskList');
  final taskListLastUpdate = Get.find<Rx<DateTime>>(tag: 'taskListLastUpdate');
  final _db = Get.find<DatabaseHelper>(tag: 'db');
  Timer? _timer;
  // 上一次 tick 还没跑完就跳过这一次，避免堆积把界面拖死
  bool _ticking = false;

  /// 未完成的待办（含带时段的任务），先按优先级从高到低，再按截止时间从近到远。

  @override
  void onInit() {
    updateDeadlineList();
    _timer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      // 上一次还没跑完就跳过，避免堆积把界面拖死
      if (_ticking) return;
      _ticking = true;
      final watch = SlowWatch('每秒 tick', thresholdMs: 300);
      watch.start();
      try {
        updateDeadlineList();
        TaskAlarmCoordinator.tick(taskList);
      } finally {
        watch.stop(detail: '任务数 ${taskList.length}');
        _ticking = false;
      }
    });
    super.onInit();
  }

  @override
  void onClose() {
    _timer?.cancel();
    super.onClose();
  }

  Future<void> saveDeadlineListToDb() async {
    await _db.setTaskList(taskList);
    await _db.setTaskListUpdateTime(taskListLastUpdate.value);
  }

  void loadDeadlineListLastUpdate() {
    taskListLastUpdate.value = _db.getTaskListUpdateTime();
  }

  void updateDeadlineListTime() {
    taskListLastUpdate.value = DateTime.now();
    // 所有改字段不改列表结构的用户操作（标记完成、暂停/继续等）都经过这里，即时落盘
    saveDeadlineListToDb();
  }

  /// 刷新任务状态（过期判定、固定日程滚动等）。返回是否有数据变化。
  /// 只在真正有变化时执行 RxList 操作和写库，避免每秒空转通知 UI、全量写 Hive。
  bool updateDeadlineList() {
    var changed = false;

    // ===== MOD: 删除前先留墓碑（实现见 lib/mod/task_runtime_mod.dart）=====
    if (TaskTombstoneStore.removeDeleted(taskList)) changed = true;

    Set<String> existingUid = {};
    List<Task> newDeadlineList = [];
    for (var deadline in taskList) {
      // ===== MOD: 兼容旧数据（早期版本会把 DDL 写成「截止前 1 分钟」）=====
      if (normalizeLegacyTask(deadline)) changed = true;
      final oldStatus = deadline.status;
      final oldEndTime = deadline.endTime;
      deadline.refreshStatus();
      if (deadline.type == TaskType.deadline) {
        // 不再按「用时」自动完成；完成只由打钩决定
        if (deadline.status != TaskStatus.completed &&
            deadline.endTime.isBefore(DateTime.now())) {
          deadline.status = TaskStatus.failed;
        }
      } else if (deadline.type == TaskType.fixed) {
        deadline.refreshStatus();
        existingUid.add(deadline.uid);
        final rollGuard = LoopGuard('日程滚动生成过去日程');
        while (deadline.endTime.isBefore(DateTime.now()) &&
            !rollGuard.tick() &&
            deadline.status != TaskStatus.outdated &&
            deadline.status != TaskStatus.completed) {
          Task temp = deadline.copyWith(
            summary: '${deadline.summary}（过去日程）',
            type: TaskType.fixedlegacy,
            repeatType: TaskRepeatType.norepeat,
            fromUid: deadline.uid,
          );
          if (deadline.setToNextPeriod()) {
            temp.genUid();
            newDeadlineList.add(temp);
          } else {
            break;
          }
        }
      }
      if (deadline.status != oldStatus || deadline.endTime != oldEndTime) {
        changed = true;
      }

      // ===== P1：活动结束后自动归档到「我已处理」=====
      // 不重复的活动一旦过了 endTime 就不再挂在「待我处理」里：
      // 没做完的子待办由详情页/卡片单独标出来（不新增存储字段）。
      if (deadline.needsAutoArchive) {
        deadline.status = TaskStatus.completed;
        changed = true;
      }
    }
    if (newDeadlineList.isNotEmpty) {
      taskList.addAll(newDeadlineList);
      changed = true;
    }

    // ===== MOD: 周期性待办完成即生成下一次（实现见 lib/mod/task_runtime_mod.dart）=====
    if (spawnNextOccurrences(taskList)) changed = true;

    if (taskList.any((element) =>
        element.type == TaskType.fixedlegacy &&
        !existingUid.contains(element.fromUid))) {
      taskList.removeWhere((element) =>
          element.type == TaskType.fixedlegacy &&
          !existingUid.contains(element.fromUid));
      changed = true;
    }

    // 视图可能直接 taskList.add 了新任务或改了 endTime，用顺序守卫兜底
    if (!changed) {
      changed = !_isSortedByEndTime();
    }

    if (changed) {
      // sort 无条件通知，兼作纯状态翻转（无 RxList 结构操作）时的 UI 通知
      taskList.sort((a, b) => a.endTime.compareTo(b.endTime));
      saveDeadlineListToDb();
    }

    // ===== MOD: 同步本地提醒 =====
    syncTaskReminders(taskList);

    return changed;
  }

  bool _isSortedByEndTime() {
    for (var i = 1; i < taskList.length; i++) {
      if (taskList[i - 1].endTime.isAfter(taskList[i].endTime)) {
        return false;
      }
    }
    return true;
  }

  void removeCompletedDeadline(context) {
    // ===== P1：待办 / 提醒 / 备忘 完成后都能一键清掉（活动日程不算）=====
    TaskTombstoneStore.remove(
        taskList,
        taskList.where((element) =>
            !element.isEvent && element.status == TaskStatus.completed));
    saveDeadlineListToDb();
  }

  void removeFailedDeadline(context) {
    TaskTombstoneStore.remove(
        taskList,
        taskList.where((element) =>
            element.type == TaskType.deadline &&
            element.status == TaskStatus.failed));
    saveDeadlineListToDb();
  }

  int suspendAllDeadline(context) {
    int count = 0;
    for (var x in taskList) {
      if (x.type == TaskType.deadline && x.status == TaskStatus.running) {
        x.status = TaskStatus.suspended;
        count++;
      }
    }
    return count;
  }

  int continueAllDeadline(context) {
    int count = 0;
    for (var x in taskList) {
      if (x.type == TaskType.deadline && x.status == TaskStatus.suspended) {
        x.status = TaskStatus.running;
        count++;
      }
    }
    return count;
  }
}
