import 'package:celechron/database/database_helper.dart';
import 'package:celechron/mod/tag_harvest.dart';
import 'package:celechron/mod/database_mod.dart';
import 'package:celechron/model/task.dart';
import 'package:celechron/utils/utils.dart';
import 'package:get/get.dart';

/// ============ 任务页的分类 / 排序 / 筛选状态 ============
///
/// 这段逻辑原本写在 `lib/page/task/task_controller.dart` 里，但那个文件上游在
/// 持续维护（1.3 就重构过它），我们留在里面的代码越多，跟版冲突就越多。
/// 改成 mixin 之后，任务控制器里只剩类声明上的一个 `with`。
mixin TaskListFilterMod on GetxController {
  RxList<Task> get _tasks => Get.find<RxList<Task>>(tag: 'taskList');

  DatabaseHelper get _modDb => Get.find<DatabaseHelper>(tag: 'db');

  @override
  void onInit() {
    super.onInit();
    // 标签库自愈：AI 生成的标签、导入/同步合并进来的标签、旧数据里的标签
    // 可能只存在于待办身上，这里补进标签库，避免「筛选器有、选择器空」。
    TagHarvest.harvest(_tasks);
  }

  List<Task> get todoDeadlineList {
    final list = _tasks
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
  List<Task> get doneDeadlineList => _tasks
      .where((element) =>
          element.type != TaskType.fixedlegacy &&
          element.status == TaskStatus.completed)
      .toList();

  // ---------------------------------------------------- 任务页的分类/排序/筛选

  /// 当前标签页：0 待我处理 1 优先处理 2 我已处理 3 星标
  final selectedTab = 0.obs;

  /// 标签筛选（多选）：空集合 = 不按标签筛
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

  /// ===== P1：按四种时间语义筛选（多选，空 = 全部类型）=====
  ///
  /// 筛选行原本只有标签这一维（那枚「全部分类」chip 已按用户建议删除），
  /// 现在补上类型：活动 / 截止 / 提醒 / 备忘。
  final filterKinds = <TaskType>{}.obs;

  bool get hasActiveFilters =>
      filterCompleted.value != null ||
      filterPriorities.isNotEmpty ||
      filterDue.value != null ||
      filterRangeStart.value != null ||
      filterRangeEnd.value != null ||
      filterKinds.isNotEmpty;

  static bool _isDone(Task task) => task.status == TaskStatus.completed;

  List<Task> _allTasks() => _tasks
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

    // 四种时间语义：固定值 fixedlegacy 按「活动」算，别让它漏出筛子
    if (filterKinds.isNotEmpty) {
      list = list.where((t) {
        final kind =
            t.type == TaskType.fixedlegacy ? TaskType.fixed : t.type;
        return filterKinds.contains(kind);
      }).toList();
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
      set.addAll(_modDb.getTagLibrary());
    } catch (_) {}
    for (final task in _tasks) {
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
    filterKinds.clear();
  }

  /// 当前选中的时间类型（界面上那一排 chip 的文案用）。
  String get kindFilterLabel {
    if (filterKinds.isEmpty) return '全部类型';
    final names = filterKinds.map((k) => taskKindName[k] ?? '').toList()..sort();
    return names.join('·');
  }
}
