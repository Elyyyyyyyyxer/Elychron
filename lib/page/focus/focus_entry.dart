import 'package:celechron/model/task.dart';
import 'package:celechron/page/focus/focus_page.dart';
import 'package:flutter/cupertino.dart';

/// ===== P3：专注的两个入口 =====
///
/// ① 待办详情页的「开始专注」—— 把这条待办和专注时长绑在一起；
/// ② 待办页右上角的计时器图标 —— 自由专注（敲代码、看书…），不挂任务。
///
/// 两个入口都进同一个 [FocusPage]，返回值表示这次专注是否正常结束。
Future<bool?> startFocusFor(
  BuildContext context, {
  Task? task,
  String? freeLabel,
}) {
  return Navigator.of(context, rootNavigator: true).push<bool>(
    CupertinoPageRoute<bool>(
      builder: (BuildContext context) =>
          FocusPage(task: task, freeLabel: freeLabel),
    ),
  );
}

/// 自由专注：先问一句「这次专注叫什么」，再开始。
///
/// 不填也能开始（就叫「专注」），不强迫用户先起名。
Future<bool?> startFreeFocus(BuildContext context) async {
  final controller = TextEditingController();
  final name = await showCupertinoDialog<String>(
    context: context,
    builder: (BuildContext context) => CupertinoAlertDialog(
      title: const Text('自由专注'),
      content: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('给这次专注起个名字（可以留空）：',
                style: TextStyle(fontSize: 13)),
            const SizedBox(height: 8),
            CupertinoTextField(
              controller: controller,
              placeholder: '敲代码 / 看书 / 写报告…',
              autofocus: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (value) => Navigator.of(context).pop(value),
            ),
          ],
        ),
      ),
      actions: [
        CupertinoDialogAction(
          child: const Text('取消'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        CupertinoDialogAction(
          isDefaultAction: true,
          child: const Text('开始'),
          onPressed: () => Navigator.of(context).pop(controller.text),
        ),
      ],
    ),
  );
  controller.dispose();
  if (name == null || !context.mounted) return null;
  return startFocusFor(context, freeLabel: name);
}
