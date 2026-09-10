import 'package:celechron/model/task.dart';
import 'package:flutter/cupertino.dart';

/// 完成待办前的检查：如果还有没勾完的子待办，弹窗二次确认；
/// 用户确认后把所有子待办一起勾上。
///
/// 返回 true 表示可以完成（可能已经顺手勾完子待办），false 表示用户取消了。
Future<bool> confirmCompleteTask(BuildContext context, Task task) async {
  if (task.subtasks.isEmpty) return true;
  final done = task.subtaskDoneCount;
  if (done == task.subtasks.length) return true;

  final rest = task.subtasks.length - done;
  final ok = await showCupertinoDialog<bool>(
    context: context,
    builder: (BuildContext context) => CupertinoAlertDialog(
      title: const Text('还有子待办没完成'),
      content: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text('这个待办还有 $rest 个子待办未完成，确定要一起完成吗？'),
      ),
      actions: [
        CupertinoDialogAction(
          child: const Text('取消'),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        CupertinoDialogAction(
          isDefaultAction: true,
          child: const Text('全部完成'),
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    ),
  );

  if (ok != true) return false;
  for (final subtask in task.subtasks) {
    subtask.done = true;
  }
  return true;
}
