import 'package:celechron/design/dingtalk_sheet.dart';
import 'package:celechron/page/task/task_controller.dart';
import 'package:celechron/model/task.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';

/// ============ 待办的批量编辑 ============
///
/// 入口在待办页右上角 ⋯ 菜单里的「批量编辑」：进入后每张卡片左边出现勾选框，
/// 点卡片是选中/取消（**不是**打开详情），底部出现操作栏：
/// **删除 / 完成 / 未完成**。
///
/// 为什么单独一个文件：`task_view.dart` 是上游文件，批量编辑的逻辑（选中集合、
/// 三种批量操作、确认弹层）全放这里，上游那份只留几行 `// ===== MOD =====` 接缝。
class TaskBatchEdit {
  TaskBatchEdit._();

  /// 是否处在批量编辑模式
  static final RxBool active = false.obs;

  /// 已选中的待办 uid（用 uid 而不是 Task 对象：刷新后对象会被替换）
  static final RxList<String> selected = <String>[].obs;

  static bool isSelected(Task task) => selected.contains(task.uid);

  static void enter() {
    selected.clear();
    active.value = true;
  }

  static void exit() {
    active.value = false;
    selected.clear();
  }

  static void toggle(Task task) {
    if (selected.contains(task.uid)) {
      selected.remove(task.uid);
    } else {
      selected.add(task.uid);
    }
  }

  /// 当前选中了几条
  static int get count => selected.length;

  /// 选中集合对应的任务（同时过滤掉已经不存在的）
  static List<Task> resolve(List<Task> all) => [
        for (final task in all)
          if (selected.contains(task.uid)) task,
      ];

  /// 有子待办没勾完的那些（批量完成前要合并成一次确认）
  static List<Task> withUnfinishedSubtasks(List<Task> tasks) => [
        for (final task in tasks)
          if (task.subtasks.isNotEmpty &&
              task.subtaskDoneCount < task.subtasks.length)
            task,
      ];

  /// 写库 + 刷新的统一收尾（与单条操作走同一条路）
  static void _persist(TaskController controller) {
    controller.updateDeadlineList();
    controller.updateDeadlineListTime();
    controller.taskList.refresh();
  }

  // ---------------------------------------------------------------- 批量删除

  static Future<void> deleteSelected(
    BuildContext context,
    TaskController controller,
    List<Task> all,
  ) async {
    final tasks = resolve(all);
    if (tasks.isEmpty) return;

    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (BuildContext context) => CupertinoAlertDialog(
        title: Text('删除 ${tasks.length} 条待办'),
        content: const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('这些待办连同它们的子待办、附件都会被删除，且无法恢复。'),
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('取消'),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('删除'),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (ok != true) return;

    for (final task in tasks) {
      task.status = TaskStatus.deleted;
    }
    // 复用控制器：它会移出列表、记墓碑（多端合并时才知道这是"删掉"而不是"新加"）
    _persist(controller);
    exit();
  }

  // ------------------------------------------------------- 批量完成 / 未完成

  ///
  /// ===== MOD: 活动/日程也允许批量完成 =====
  ///
  /// 原来这里用 `splitCompletable` 把活动型剔除（理由写的是"活动不算完成"），
  /// 但用户要求活动类也能右滑完成/恢复之后，两条路的规则就该一致：
  /// 详情页的完成按钮、列表右滑、批量完成 —— 四种类型一视同仁。
  /// 这个函数以前是个纯函数（为了单测钉住那条规则），现在规则没了，
  /// 直接返回 `resolve` 的结果，也就顺手把那个函数删掉了。
  static Future<void> setCompleted(
    BuildContext context,
    TaskController controller,
    List<Task> all, {
    required bool completed,
  }) async {
    final tasks = resolve(all);
    if (tasks.isEmpty) {
      await showDingTalkPanel(
        context: context,
        title: completed ? '没有可完成的待办' : '没有可恢复的待办',
        subtitle: null,
        children: const [],
        primaryLabel: '好',
        onPrimary: () => Navigator.of(context).pop(),
      );
      return;
    }

    // 有子待办没勾完的：**只确认一次**（而不是每条弹一次）
    if (completed) {
      final unfinished = withUnfinishedSubtasks(tasks);
      if (unfinished.isNotEmpty) {
        final ok = await showCupertinoDialog<bool>(
          context: context,
          builder: (BuildContext context) => CupertinoAlertDialog(
            title: const Text('还有子待办没完成'),
            content: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '其中 ${unfinished.length} 条还有子待办未完成，确定要一起完成吗？',
              ),
            ),
            actions: [
              CupertinoDialogAction(
                child: const Text('取消'),
                onPressed: () => Navigator.of(context).pop(false),
              ),
              CupertinoDialogAction(
                isDefaultAction: true,
                child: const Text('一起完成'),
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ],
          ),
        );
        if (ok != true) return;
      }
    }

    for (final task in tasks) {
      task.status =
          completed ? TaskStatus.completed : TaskStatus.running;
    }
    _persist(controller);
    exit();
  }

  // ---------------------------------------------------------------- 底部操作栏

  /// 底部操作栏（批量模式下贴在页面底部）
  static Widget bar(BuildContext context, TaskController controller) {
    return Obx(() {
      if (!active.value) return const SizedBox.shrink();
      final n = count;
      final textColor = CupertinoTheme.of(context).textTheme.textStyle.color;
      final enabled = n > 0;

      return Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: CupertinoDynamicColor.resolve(
              CupertinoColors.systemBackground, context),
          border: Border(
            top: BorderSide(
              width: 0.5,
              color: CupertinoDynamicColor.resolve(
                  CupertinoColors.separator, context),
            ),
          ),
        ),
        child: Row(
          children: [
            CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(52, 34),
              onPressed: exit,
              child: Text('取消', style: TextStyle(color: textColor, fontSize: 15)),
            ),
            Expanded(
              child: Text(
                enabled ? '已选 $n 条' : '点待办来选择',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: CupertinoDynamicColor.resolve(
                      CupertinoColors.secondaryLabel, context),
                ),
              ),
            ),
            _action(
              context,
              label: '未完成',
              icon: CupertinoIcons.arrow_counterclockwise,
              enabled: enabled,
              onTap: () => setCompleted(context, controller, _allTasks(),
                  completed: false),
            ),
            _action(
              context,
              label: '完成',
              icon: CupertinoIcons.check_mark_circled_solid,
              enabled: enabled,
              onTap: () => setCompleted(context, controller, _allTasks(),
                  completed: true),
            ),
            _action(
              context,
              label: '删除',
              icon: CupertinoIcons.delete,
              enabled: enabled,
              destructive: true,
              onTap: () => deleteSelected(context, controller, _allTasks()),
            ),
          ],
        ),
      );
    });
  }

  /// 复用控制器的任务列表（避免各处传参）
  static List<Task> _allTasks() {
    try {
      return Get.find<TaskController>().taskList.toList();
    } catch (_) {
      return const <Task>[];
    }
  }

  static Widget _action(
    BuildContext context, {
    required String label,
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
    bool destructive = false,
  }) {
    final color = !enabled
        ? CupertinoDynamicColor.resolve(CupertinoColors.tertiaryLabel, context)
        : (destructive
            ? CupertinoColors.systemRed
            : CupertinoColors.systemBlue);
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      minimumSize: const Size(56, 34),
      onPressed: enabled ? onTap : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 11.5, color: color)),
        ],
      ),
    );
  }
}
