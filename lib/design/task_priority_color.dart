import 'package:celechron/model/task.dart';
import 'package:flutter/cupertino.dart';

/// 优先级的展示色：低=灰，普通=蓝，高=橙，紧急=红。
Color taskPriorityColor(TaskPriority priority) {
  switch (priority) {
    case TaskPriority.low:
      return CupertinoColors.systemGrey;
    case TaskPriority.normal:
      return CupertinoColors.systemBlue;
    case TaskPriority.high:
      return CupertinoColors.systemOrange;
    case TaskPriority.urgent:
      return CupertinoColors.systemRed;
  }
}
