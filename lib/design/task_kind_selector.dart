import 'package:celechron/model/task.dart';
import 'package:flutter/cupertino.dart';

/// ===== P1：四种时间语义的选择器 =====
///
/// 创建页、详情页、「其他日期」面板三处共用同一份 UI 与同一份切换逻辑
/// （逻辑在 [Task.applyKind] 里），避免三处各写一套渐渐走样。
///
/// 用法：放进自己页面的卡片里 ——
/// ```dart
/// _card(children: [taskKindControl(now, (kind) => setState(() => now.applyKind(kind)))])
/// ```
Widget taskKindControl(
  Task task,
  ValueChanged<TaskType> onChanged, {
  bool showHint = true,
}) {
  return Builder(
    builder: (BuildContext context) {
      final labelColor = CupertinoDynamicColor.resolve(
          CupertinoColors.secondaryLabel, context);
      // fixedlegacy（内部值）在界面上当成「活动」显示
      final current =
          task.type == TaskType.fixedlegacy ? TaskType.fixed : task.type;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: CupertinoSlidingSegmentedControl<TaskType>(
              groupValue: current,
              children: const {
                TaskType.fixed: Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Text('活动')),
                TaskType.deadline: Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Text('截止')),
                TaskType.remind: Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Text('提醒')),
                TaskType.memo: Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Text('备忘')),
              },
              onValueChanged: (value) {
                if (value != null && value != current) onChanged(value);
              },
            ),
          ),
          if (showHint)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                taskKindHint[current] ?? '',
                style: TextStyle(fontSize: 12, color: labelColor),
              ),
            ),
        ],
      );
    },
  );
}
