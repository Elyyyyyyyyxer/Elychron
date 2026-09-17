import 'package:celechron/model/task.dart';

/// 课程挂载：挂在**课程总体**上的资料（附件）与评论。
///
/// ===== 为什么是这样一个结构 =====
///
/// 需求（用户口述 + 2026-09-14 拍板，见 `docs/BACKLOG.md` #24）：
/// 课程要能**加评论 / 挂附件 / 挂待办**，但**不能让课程跑进待办列表**。
///
/// 三条决定的落地方式：
/// 1. **评论与附件挂在课程总体**（不做"某一次课"的分级），
///    所以本结构以**课程代码**（`Session.id`）为键，一门课一份；
/// 2. **某个待办也可以挂到课程上**， 那件事走 `Task.courseId`（Hive 只追加字段，
///    不插队），所以这门课的"关联待办"是**查出来的**，不在这里冗余存一份；
/// 3. 走**折中路径**：资料/评论用独立轻量结构（就是本类），
///    "提醒/专注归属"那类需要复用管线的能力留给后续（专注侧给 `FocusSession`
///    追加课程 id 即可，同样只追加）。
///
/// ===== 为什么不写 @HiveType + adapter =====
///
/// 复用的两个结构（[TaskAttachment] / [TaskComment]）本身是 Hive 类型，
/// 但它们**只作为值**被塞进一个 Map 里存， 和 `CourseIdMap` 用的是同一招
/// （见 `database/adapters/course_id_map_adapter.dart`）：**存 JSON/Map，
/// 不新增 typeId**。好处是零 schema 风险、零 adapter 注册，
/// 而且以后加字段（比如"资料分组"）不用再动 Hive 编号。
class CourseMount {
  /// 课程代码（`Session.id`，也是 `CourseDetailPage` 的 courseId）
  final String courseId;

  /// 长期资料：课件、笔记、随手拍的板书……（文件会被复制进应用目录）
  List<TaskAttachment> attachments;

  /// 评论：这门课我记过什么
  List<TaskComment> comments;

  CourseMount({
    required this.courseId,
    List<TaskAttachment>? attachments,
    List<TaskComment>? comments,
  })  : attachments = attachments ?? <TaskAttachment>[],
        comments = comments ?? <TaskComment>[];

  bool get isEmpty => attachments.isEmpty && comments.isEmpty;

  // ------------------------------------------------------------ 序列化

  static Map<String, dynamic> _attachmentToMap(TaskAttachment item) => {
        'name': item.name,
        'path': item.path,
        'size': item.size,
      };

  static TaskAttachment _attachmentFromMap(Map<dynamic, dynamic> map) =>
      TaskAttachment(
        name: map['name'] as String? ?? '',
        path: map['path'] as String? ?? '',
        size: (map['size'] as num?)?.toInt() ?? 0,
      );

  static Map<String, dynamic> _commentToMap(TaskComment item) => {
        'content': item.content,
        'time': item.time.millisecondsSinceEpoch,
      };

  static TaskComment _commentFromMap(Map<dynamic, dynamic> map) => TaskComment(
        content: map['content'] as String? ?? '',
        time: DateTime.fromMillisecondsSinceEpoch(
            (map['time'] as num?)?.toInt() ?? 0),
      );

  Map<String, dynamic> toMap() => {
        'attachments': attachments.map(_attachmentToMap).toList(),
        'comments': comments.map(_commentToMap).toList(),
      };

  /// 从存下来的 Map 还原。**任何一项读不动就丢掉那一项，绝不让整门课报错**
  ///， 这是用户数据，宁可少显示一条评论，也不能让课程详情页崩掉。
  factory CourseMount.fromMap(String courseId, Map<dynamic, dynamic>? raw) {
    if (raw == null) return CourseMount(courseId: courseId);
    final attachments = <TaskAttachment>[];
    final comments = <TaskComment>[];
    try {
      for (final item in (raw['attachments'] as List? ?? const [])) {
        if (item is Map) attachments.add(_attachmentFromMap(item));
      }
    } catch (_) {}
    try {
      for (final item in (raw['comments'] as List? ?? const [])) {
        if (item is Map) comments.add(_commentFromMap(item));
      }
    } catch (_) {}
    return CourseMount(
      courseId: courseId,
      attachments: attachments,
      comments: comments,
    );
  }
}
