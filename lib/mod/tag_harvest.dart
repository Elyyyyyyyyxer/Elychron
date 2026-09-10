import 'package:celechron/database/database_helper.dart';
import 'package:celechron/mod/database_mod.dart';
import 'package:celechron/model/task.dart';
import 'package:get/get.dart';

/// ============ 标签库自愈 ============
///
/// 背景：标签库（`getTagLibrary()`）原本只在用户通过标签选择器新建标签时才写入。
/// 于是这些情况下会出现「待办身上有标签，但标签库里没有」：
///   - AI 生成待办时直接给任务设了标签
///   - 从 JSON 导入 / 局域网同步合并进来的待办
///   - 早期版本留下的数据
/// 表现就是：筛选器能看到标签（它取的是「标签库 ∪ 待办上的标签」），
/// 但标签管理页和标签选择器是空的（它们只读标签库）。
///
/// 所以这里做两件事：把待办上的标签补进标签库，以及记住 AI 新产生的标签。
class TagHarvest {
  TagHarvest._();

  /// 把待办（含子待办）身上的标签补进标签库。返回值表示是否有变化。
  static Future<bool> harvest(Iterable<Task> tasks) async {
    final collected = <String>[];
    for (final task in tasks) {
      collected.addAll(task.tags);
      for (final subtask in task.subtasks) {
        collected.addAll(subtask.tags);
      }
    }
    return remember(collected);
  }

  /// 把若干标签补进标签库（已存在的跳过，保持原有顺序）
  static Future<bool> remember(Iterable<String> tags) async {
    final incoming = <String>[];
    for (final tag in tags) {
      final text = tag.trim();
      if (text.isEmpty) continue;
      if (!incoming.contains(text)) incoming.add(text);
    }
    if (incoming.isEmpty) return false;

    final DatabaseHelper db;
    try {
      if (!Get.isRegistered<DatabaseHelper>(tag: 'db')) return false;
      db = Get.find<DatabaseHelper>(tag: 'db');
    } catch (_) {
      return false;
    }

    final library = db.getTagLibrary();
    final merged = <String>[...library];
    var changed = false;
    for (final tag in incoming) {
      if (merged.contains(tag)) continue;
      merged.add(tag);
      changed = true;
    }
    if (!changed) return false;

    try {
      await db.setTagLibrary(merged, allowEmpty: true);
      return true;
    } catch (_) {
      return false;
    }
  }
}
