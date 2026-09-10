import 'dart:async';
import 'package:get/get.dart';
import 'package:celechron/database/database_helper.dart';
import 'package:celechron/model/task.dart';
import 'package:celechron/utils/task_alarm_center.dart';
import 'package:celechron/utils/task_reminder.dart';
import 'package:celechron/utils/utils.dart';

class TaskController extends GetxController {
  final taskList = Get.find<RxList<Task>>(tag: 'taskList');
  final taskListLastUpdate = Get.find<Rx<DateTime>>(tag: 'taskListLastUpdate');
  final _db = Get.find<DatabaseHelper>(tag: 'db');
  Timer? _timer;

  /// 未完成的待办（含带时段的任务），先按优先级从高到低，再按截止时间从近到远。
  List<Task> get todoDeadlineList {
    final list = taskList
        .where((element) =>
            element.type != TaskType.fixedlegacy &&
            element.status != TaskStatus.completed &&
            element.status != TaskStatus.deleted &&
            element.status != TaskStatus.outdated)
        .toList();
    list.sort((a, b) {
      if (a.priority != b.priority) {
        return b.priority.index.compareTo(a.priority.index);
      }
      return a.endTime.compareTo(b.endTime);
    });
    return list;
  }

  /// 已完成的待办
  List<Task> get doneDeadlineList => taskList
      .where((element) =>
          element.type != TaskType.fixedlegacy &&
          element.status == TaskStatus.completed)
      .toList();

  // ---------------------------------------------------- 任务页的分类/排序/筛选

  static const List<String> tabNames = ['待我处理', '优先处理', '我已处理', '星标'];

  /// 当前标签页：0 待我处理 1 优先处理 2 我已处理 3 星标
  final selectedTab = 0.obs;

  /// 标签筛选（多选）：空集合 = 全部分类
  final selectedTags = <String>{}.obs;

  /// 排序：endTime / createdAt / updatedAt / priority
  final sortKey = 'createdAt'.obs;
  final sortAscending = false.obs;

  /// 筛选
  final filterCompleted = Rxn<bool>();
  final filterPriorities = <TaskPriority>{}.obs;
  final filterDue = Rxn<String>();
  final filterRangeStart = Rxn<DateTime>();
  final filterRangeEnd = Rxn<DateTime>();

  bool get hasActiveFilters =>
      filterCompleted.value != null ||
      filterPriorities.isNotEmpty ||
      filterDue.value != null ||
      filterRangeStart.value != null ||
      filterRangeEnd.value != null;

  static bool _isDone(Task task) => task.status == TaskStatus.completed;

  List<Task> _allTasks() => taskList
      .where((t) =>
          t.type != TaskType.fixedlegacy && t.status != TaskStatus.deleted)
      .toList();

  /// 某个标签页的原始列表（不含筛选）
  List<Task> _tasksOfTab(int tab) {
    final list = _allTasks();
    switch (tab) {
      case 1:
        return list
            .where((t) =>
                !_isDone(t) &&
                (t.priority == TaskPriority.high ||
                    t.priority == TaskPriority.urgent))
            .toList();
      case 2:
        return list.where(_isDone).toList();
      case 3:
        return list.where((t) => t.starred).toList();
      default:
        return list
            .where((t) => !_isDone(t) && t.status != TaskStatus.outdated)
            .toList();
    }
  }

  int tabCount(int tab) => _tasksOfTab(tab).length;

  /// 当前标签页 + 分类 + 筛选 + 排序后的列表
  List<Task> get visibleTaskList {
    var list = _tasksOfTab(selectedTab.value);

    // 标签多选：命中任意一个选中的标签即保留
    if (selectedTags.isNotEmpty) {
      list = list
          .where((t) => t.tags.any((tag) => selectedTags.contains(tag)))
          .toList();
    }

    final completed = filterCompleted.value;
    if (completed != null) {
      list = list.where((t) => _isDone(t) == completed).toList();
    }

    if (filterPriorities.isNotEmpty) {
      list = list.where((t) => filterPriorities.contains(t.priority)).toList();
    }

    final due = filterDue.value;
    if (due != null) {
      list = list.where((t) => _matchDue(t, due)).toList();
    }

    final start = filterRangeStart.value;
    if (start != null) {
      list = list
          .where((t) => !dateOnly(t.endTime).isBefore(dateOnly(start)))
          .toList();
    }
    final end = filterRangeEnd.value;
    if (end != null) {
      list = list
          .where((t) => !dateOnly(t.endTime).isAfter(dateOnly(end)))
          .toList();
    }

    list.sort(_compare);
    return list;
  }

  int _compare(Task a, Task b) {
    int result;
    switch (sortKey.value) {
      case 'endTime':
        result = a.endTime.compareTo(b.endTime);
        break;
      case 'updatedAt':
        result = a.sortableUpdatedAt.compareTo(b.sortableUpdatedAt);
        break;
      case 'priority':
        result = a.priority.index.compareTo(b.priority.index);
        break;
      default:
        result = a.sortableCreatedAt.compareTo(b.sortableCreatedAt);
    }
    return sortAscending.value ? result : -result;
  }

  bool _matchDue(Task task, String due) {
    final today = dateOnly(DateTime.now());
    final day = dateOnly(task.endTime);
    switch (due) {
      case 'overdue':
        return day.isBefore(today) && !_isDone(task);
      case 'today':
        return day == today;
      case 'tomorrow':
        return day == today.add(const Duration(days: 1));
      case 'week':
        return !day.isBefore(today) &&
            !day.isAfter(today.add(const Duration(days: 7)));
      case 'none':
        return false; // 本应用的任务都有截止时间
    }
    return true;
  }

  /// 标签库版本号：标签管理里增删改后自增，用来触发界面刷新
  final tagVersion = 0.obs;

  /// 所有标签：标签库 + 任务里用过的
  List<String> get allTags {
    final set = <String>{};
    try {
      set.addAll(_db.getTagLibrary());
    } catch (_) {}
    for (final task in taskList) {
      set.addAll(task.tags);
    }
    final list = set.toList()..sort();
    return list;
  }

  void resetFilters() {
    filterCompleted.value = null;
    filterPriorities.clear();
    filterDue.value = null;
    filterRangeStart.value = null;
    filterRangeEnd.value = null;
  }

  @override
  void onInit() {
    updateDeadlineList();
    _timer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      updateDeadlineList();
      checkAlarms();
    });
    super.onInit();
  }

  /// 闹钟模式下，前台到点就弹出全屏闹钟
  final Set<String> _firedAlarms = <String>{};

  void checkAlarms() {
    if (TaskAlarmCenter.current.value == null) {
      _firedAlarms.clear();
    }
    if (TaskReminder.mode != TaskReminder.modeAlarm) return;
    if (TaskAlarmCenter.current.value != null) return;

    final now = DateTime.now();
    for (final task in taskList) {
      if (!task.reminderEnabled) continue;
      if (task.type != TaskType.deadline) continue;
      if (task.status != TaskStatus.running &&
          task.status != TaskStatus.suspended) {
        continue;
      }
      final fireAt = task.reminderTargetTime;
      if (fireAt.isAfter(now)) continue;
      if (now.difference(fireAt).inMinutes >= 1) continue;
      if (_firedAlarms.contains(task.uid)) continue;
      _firedAlarms.add(task.uid);
      TaskAlarmCenter.fire(task);
      return;
    }
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

    if (taskList.any((element) => element.status == TaskStatus.deleted)) {
      // ===== MOD: 删除前先留墓碑，同步时才知道这条是被删的而不是新加的 =====
      _removeWithTombstone(
          taskList.where((element) => element.status == TaskStatus.deleted));
      changed = true;
    }

    Set<String> existingUid = {};
    List<Task> newDeadlineList = [];
    for (var deadline in taskList) {
      // ===== MOD: 兼容旧数据——普通待办不该有开始时间（早期版本写成「截止前 1 分钟」）=====
      if (deadline.type == TaskType.deadline &&
          deadline.startTime != deadline.endTime) {
        deadline.startTime = deadline.endTime;
        changed = true;
      }
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
        while (deadline.endTime.isBefore(DateTime.now()) &&
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
    }
    if (newDeadlineList.isNotEmpty) {
      taskList.addAll(newDeadlineList);
      changed = true;
    }

    // ===== MOD BEGIN: 周期性待办完成之后自动生成下一次 =====
    // 用 fromUid 标记，避免每秒重复生成；带时段的重复待办同样会生成下一期。
    final spawnedFrom = taskList
        .where((element) => element.fromUid != null)
        .map((element) => element.fromUid!)
        .toSet();
    final nextOccurrences = <Task>[];
    for (var deadline in taskList) {
      if (deadline.type == TaskType.fixedlegacy) continue;
      if (deadline.status != TaskStatus.completed) continue;
      if (deadline.repeatType == TaskRepeatType.norepeat) continue;
      if (spawnedFrom.contains(deadline.uid)) continue;

      final next = deadline.copyWith();
      next.genUid();
      next.fromUid = deadline.uid;
      next.status = TaskStatus.running;
      next.timeSpent = const Duration(minutes: 0);
      if (!next.advanceRepeatPeriod()) continue;
      if (next.status == TaskStatus.outdated) continue;
      next.forceRefreshStatus();
      if (next.status != TaskStatus.running) continue;
      nextOccurrences.add(next);
      spawnedFrom.add(deadline.uid);
    }
    if (nextOccurrences.isNotEmpty) {
      taskList.addAll(nextOccurrences);
      changed = true;
    }
    // ===== MOD END =====

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

    // ===== MOD: 把开启提醒的任务同步成本地通知（内部有签名缓存，未变化不重复调度）=====
    TaskReminder.mode = _db.getReminderMode();
    TaskReminder.syncAll(taskList);

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

  /// ===== MOD: 移除待办并留下删除墓碑 =====
  /// legacy 的《过去日程》副本属于本地派生数据，不留墓碑（它们挂在原日程的
  /// fromUid 上，原日程被删时合并逻辑会一并清掉）。
  void _removeWithTombstone(Iterable<Task> tasks) {
    final list = tasks.toList();
    if (list.isEmpty) return;
    final uids = <String>[];
    for (final task in list) {
      if (task.uid.isEmpty) continue;
      if (task.type != TaskType.fixedlegacy) uids.add(task.uid);
    }
    if (uids.isNotEmpty) {
      _db.addTombstones(uids);
    }
    taskList.removeWhere((element) => list.contains(element));
  }

  void removeCompletedDeadline(context) {
    _removeWithTombstone(taskList.where((element) =>
        element.type == TaskType.deadline &&
        element.status == TaskStatus.completed));
    saveDeadlineListToDb();
  }

  void removeFailedDeadline(context) {
    _removeWithTombstone(taskList.where((element) =>
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
