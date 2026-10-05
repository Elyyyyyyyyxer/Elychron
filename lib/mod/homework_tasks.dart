import 'dart:convert';

import 'package:celechron/database/database_helper.dart';
import 'package:celechron/model/scholar.dart';
import 'package:celechron/model/task.dart';
import 'package:celechron/model/todo.dart';
import 'package:celechron/mod/data_change.dart';
import 'package:get/get.dart';

/// ===== 作业自动进日程（v1.5.0）=====
///
/// 用户要求（2026-09-21）：
/// 「我希望作业像课程一样自动变成日程一部分，并且默认优先级比较高，
///   存在作业时在待办页面优先展示作业」
///
/// 数据来源是现成的：学在浙大的 api/todos（每次完整刷新都会拉，见
/// http/zjuServices/courses.dart 的 getTodo），结果挂在 Scholar.todos 上。
/// 以前它**只是显示**，从来没变成待办 —— 这里补上。
///
/// 三个设计点：
/// 1. **稳定 uid**：hw-<作业 id> —— 同一份作业反复刷新只会更新那一条，
///    不会每次刷新长出一堆重复待办（这是最容易写坏的地方）。
/// 2. **默认优先级高 + 打一个「作业」标签**：优先级按用户要求给 high；
///    标签是给界面用的（待办页据此置顶，见 task_controller 的排序）。
/// 3. **删掉就不复活**：用户把自动生成的作业删了，说明他不想看见它，
///    所以记一个「已忽略」集合（optionsBox，和墓碑同一套做法，不动 Hive 结构）。
const String kHomeworkTag = '作业';
const String kHomeworkUidPrefix = 'hw-';

/// 作业的来源（写进待办的描述里）。
///
/// PTA 的作业 id 带 pta: 前缀（见 http/pta_spider.dart）—— 原来这里写死
/// "来自学在浙大"，PTA 的作业建出来的待办就会挂着错的来源。
String _sourceLabelOf(Todo todo) =>
    todo.id.startsWith('pta:') ? '来自 PTA 拼题A：' : '来自学在浙大：';
const String _kDismissedKey = 'homeworkDismissed';

bool taskIsHomework(Task task) => task.tags.contains(kHomeworkTag);

/// 已忽略的作业 id（用户在待办里删掉过的）
Set<String> homeworkDismissed() {
  try {
    final raw =
        Get.find<DatabaseHelper>(tag: 'db').optionsBox.get(_kDismissedKey);
    if (raw is String && raw.isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is List)
        return decoded.map((item) => item.toString()).toSet();
    }
  } catch (_) {}
  return <String>{};
}

Future<void> _rememberDismissed(String todoId) async {
  try {
    final db = Get.find<DatabaseHelper>(tag: 'db');
    final all = homeworkDismissed()..add(todoId);
    await db.optionsBox.put(_kDismissedKey, jsonEncode(all.toList()));
  } catch (_) {}
}

/// 作业置顶：先按「是不是作业」，再按截止时间
int homeworkFirst(Task a, Task b) {
  final rank = (taskIsHomework(a) ? 0 : 1).compareTo(taskIsHomework(b) ? 0 : 1);
  if (rank != 0) return rank;
  return a.endTime.compareTo(b.endTime);
}

/// 把作业同步成待办（幂等：可以随便多调几次）
///
/// 返回这次有没有改动（用来决定要不要落库 + 推同步）。
Future<bool> syncHomeworkTasks({
  required DatabaseHelper db,
  required RxList<Task> taskList,
  required List<Todo> todos,
  DateTime? now,
}) async {
  if (todos.isEmpty) return false;
  final at = now ?? DateTime.now();
  final dismissed = homeworkDismissed();
  var changed = false;

  for (final todo in todos) {
    if (todo.id.isEmpty) continue;
    if (dismissed.contains(todo.id)) continue;
    final deadline = todo.endTime;
    if (deadline == null) continue; // 没截止时间的作业进不了日程
    if (!todo.name.trim().isEmpty && todo.name.contains('已批阅')) continue;
    final uid = kHomeworkUidPrefix + todo.id;

    final index = taskList.indexWhere((task) => task.uid == uid);
    if (index < 0) {
      // (1) 新作业 → 建一条待办
      final task = Task(
        summary: todo.name,
        startTime: at.isAfter(deadline) ? deadline : at,
        endTime: deadline,
        repeatEndsTime: deadline,
      );
      task.uid = uid;
      task.priority = TaskPriority.high; // 用户要求：默认优先级比较高
      task.tags = <String>[kHomeworkTag];
      if (todo.course.isNotEmpty) {
        task.description = _sourceLabelOf(todo) + todo.course;
      }
      taskList.add(task);
      changed = true;
      continue;
    }

    // (2) 已有 → 只更新会变的那两项（标题可能被老师改，截止时间也会变）
    final existing = taskList[index];
    var touched = false;
    if (existing.summary != todo.name) {
      existing.summary = todo.name;
      touched = true;
    }
    if (!existing.endTime.isAtSameMomentAs(deadline)) {
      existing.endTime = deadline;
      existing.repeatEndsTime = deadline;
      touched = true;
    }
    if (!existing.tags.contains(kHomeworkTag)) {
      existing.tags = <String>[...existing.tags, kHomeworkTag];
      touched = true;
    }
    // 来源可能搞错过（PTA 的作业一度被写成"来自学在浙大"）。
    // 只动我们自己生成的那种（以"来自"开头），不碰用户手写的描述。
    if (todo.course.isNotEmpty && existing.description.startsWith('来自')) {
      final expected = _sourceLabelOf(todo) + todo.course;
      if (existing.description != expected) {
        existing.description = expected;
        touched = true;
      }
    }
    if (touched) {
      existing.updatedAt = at;
      changed = true;
    }
  }

  if (!changed) return false;
  await db.setTaskList(taskList);
  taskList
    ..sort(homeworkFirst)
    ..refresh();
  // 作业也是用户数据，同步出去（用户要求"每次操作都同步"）
  notifyDataChanged();
  return true;
}

/// 用户在待办里删掉自动生成的作业时调它 —— 免得下次刷新又长回来
Future<void> dismissHomeworkFor(Task task) async {
  if (!task.uid.startsWith(kHomeworkUidPrefix)) return;
  await _rememberDismissed(task.uid.substring(kHomeworkUidPrefix.length));
}

/// 挂到 scholar 上：每次刷新完自动同步一次
///
/// 为什么监听 Rx 而不是去改刷新流程：刷新有前台/后台两条路（还有 isolate），
/// 在它们各自的落库点上插钩子容易漏；而「作业列表变了」是唯一事实，
/// 盯着它就够了（和局域网那套盯 taskList 是同一个思路）。
void startHomeworkSync(DatabaseHelper db, RxList<Task> taskList) {
  try {
    final scholar = Get.find<Rx<Scholar>>(tag: 'scholar');
    void run() {
      final todos = scholar.value.todos;
      if (todos.isEmpty) return;
      syncHomeworkTasks(db: db, taskList: taskList, todos: todos);
    }

    scholar.listen((_) => run());
    run(); // 启动时先来一次（上次刷新留下的作业也补进来）
  } catch (_) {
    // 拿不到 scholar 就算了，不影响其它功能
  }
}
