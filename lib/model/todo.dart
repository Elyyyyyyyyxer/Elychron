import 'package:celechron/utils/json_utils.dart';

class Todo {
  String id;
  String name;
  String course;
  DateTime? endTime;

  Todo.fromJson(Map<String, dynamic> json)
      : id = asString(json["id"]) ?? '',
        name = asString(json["title"]) ?? '未命名作业',
        course = asString(json["course_name"]) ?? '未知课程',
        // 服务端给的是 UTC（学在浙大 / PTA 都是 "...Z"），这里**立刻转成本地时间**。
      //
      // 不转的话，读原始字段的地方就会差 8 小时：2026-10-01 实测同一份作业
      // 在学业页显示 23:59（那里走了 toStringHumanReadable → toLocal()），
      // 在接下来页却显示 15:59（那里直接读了 hour/minute）。
      // 归一到本地之后，下游谁都不用再操心时区。
      endTime = DateTime.tryParse(asString(json["end_time"]) ?? '')?.toLocal();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': name,
        'course_name': course,
        'end_time': endTime?.toIso8601String(),
      };

  static List<Todo> getAllFromCourses(Map<String, dynamic> json) {
    final rawTodos = asDynamicList(json["todo_list"]) ?? const [];
    final todos = <Todo>[];
    for (final rawTodo in rawTodos) {
      final todoMap = asStringMap(rawTodo);
      if (todoMap == null || asBool(todoMap["is_student"]) != true) continue;
      try {
        final todo = Todo.fromJson(todoMap);
        if (todo.id.isNotEmpty) todos.add(todo);
      } catch (_) {
        // 单条作业字段异常不影响其它作业。
      }
    }
    return todos;
  }

  // TODO: 对于助教/老师，是否需要将批改作业当作 todo 来显示？

  bool isInOneDay() => endTime != null
      ? endTime!.subtract(const Duration(days: 1)).isBefore(DateTime.now())
      : false;

  bool isInOneWeek() => endTime != null
      ? endTime!.subtract(const Duration(days: 7)).isBefore(DateTime.now())
      : false;
}
