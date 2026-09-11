import 'package:celechron/model/task.dart';
import 'package:celechron/page/task/task_controller.dart';
import 'package:celechron/page/task/task_edit_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';

/// 从任何地方打开一条待办的详情页，并**把编辑结果写回任务列表**。
///
/// 为什么需要它：原来的两个入口（待办页卡片、日历卡片）都在 `await` 之后
/// 自己 `task.copy(res)`；而「点通知进来」这条路径**没有调用方**，
/// 用户改完东西一 pop，结果就丢了。统一走这里之后三条路径行为一致。
///
/// [highlightSubtaskUid] 用来高亮某一步（点子待办通知进来时用）。
Future<void> openTaskDetail(
  BuildContext context,
  Task task, {
  String? highlightSubtaskUid,
}) async {
  final res = await Navigator.of(context, rootNavigator: true).push<Task>(
    CupertinoPageRoute<Task>(
      builder: (BuildContext context) => TaskEditPage(
        task,
        highlightSubtaskUid: highlightSubtaskUid,
      ),
    ),
  );
  if (res == null) return;

  if (res.status == TaskStatus.deleted) {
    task.status = TaskStatus.deleted;
  } else {
    task.copy(res);
  }
  try {
    final controller = Get.find<TaskController>();
    controller.updateDeadlineList();
    controller.updateDeadlineListTime();
    controller.taskList.refresh();
  } catch (_) {
    // 控制器还没起来（极早期启动）时不必刷界面
  }
}
