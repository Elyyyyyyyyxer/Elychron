import 'package:celechron/database/database_helper.dart';
import 'package:celechron/model/course_mount.dart';
import 'package:celechron/model/period.dart';
import 'package:celechron/model/task.dart';

/// 课程挂载（资料 / 评论 / 关联待办）的读写入口。
///
/// 设计背景与三条拍板决定见 `docs/BACKLOG.md` #24 和 `CourseMount` 的注释。
/// 这里只管"存哪里、怎么取"，不管界面。
extension CourseMountStore on DatabaseHelper {
  /// 取一门课挂载的东西；没有就返回空对象（**永远不返回 null**，
  /// 这样界面不用到处判空）。
  CourseMount courseMount(String courseId) {
    if (courseId.isEmpty) return CourseMount(courseId: courseId);
    final raw = courseMountBox.get(courseId);
    return CourseMount.fromMap(
      courseId,
      raw is Map ? raw : null,
    );
  }

  /// 存回去。空挂载**不占空间**：两项都空了就把这条记录删掉
  /// （用户把资料和评论都删完时，盒子里不该留一条空壳）。
  Future<void> saveCourseMount(CourseMount mount) async {
    if (mount.courseId.isEmpty) return;
    if (mount.isEmpty) {
      await courseMountBox.delete(mount.courseId);
      return;
    }
    await courseMountBox.put(mount.courseId, mount.toMap());
  }

  /// 这门课挂了哪些待办 —— **查出来的**，不是存出来的。
  ///
  /// 课程挂载的三件事里，"评论/资料"以课程代码为键存在 [DatabaseHelper.courseMountBox]，
  /// 而"关联待办"是给 `Task` 追加一个 `courseId` 字段（Hive 只追加、不插队），
  /// 所以这里按字段筛一遍即可，避免同一份关系存两处、两边还不一致。
  ///
  /// 具体筛选见顶层函数 [tasksForCourse]（抽出去是为了能纯单测，不依赖盒子）。
  List<Task> tasksForCourseOf(Iterable<Task> tasks, String courseId) =>
      tasksForCourse(tasks, courseId);
}

/// 从一堆待办里挑出挂在这门课上的那些。
/// 规则：
/// - 只认 `courseId` 完全相等的；
/// - **跳过已删除与已作废**（那是"这条记录不该再出现"，与课程无关）；
/// - **保留已完成** —— 课程页要能看到"这门课我做完过什么"，
///   要不要把完成项折叠/隐藏交给界面决定，别在数据层替它决定。
///
/// 纯函数、无 IO：这样能单测（见 `test/course_mount_test.dart`）。
List<Task> tasksForCourse(Iterable<Task> tasks, String courseId) {
  if (courseId.isEmpty) return const <Task>[];
  return [
    for (final task in tasks)
      if (task.courseId == courseId &&
          task.status != TaskStatus.deleted &&
          task.status != TaskStatus.outdated)
        task,
  ];
}

/// 这次专注算在哪门课上（用户 2026-09-14 拍板的口径）。
///
/// 优先级从高到低：
/// 1. **待办自带课程归属时直接用它** —— 用户建待办时明确选过，比按时间猜准；
/// 2. 否则看**开始时间**落在哪一节的时段里（`[startTime, endTime)` 半开区间：
///    连续两节课的边界只会命中后一节，不会一次算进两门课）；
/// 3. 只认 [PeriodType.classes]（真课程）—— 考试、日程、虚拟占位都不算；
/// 4. 找不到就算自由专注，返回 null（不硬塞给某门课）。
///
/// 为什么按"开始时间"而不是按重叠比例：一次专注被拆成两半记到两门课上，
/// 统计页会变得没法看；按开始时间则永远只记一门（用户明确选了这个口径）。
///
/// 纯函数、无 IO，可单测（见 `test/focus_attribution_test.dart`）。
String? courseIdForFocusStart({
  required DateTime startedAt,
  required Iterable<Period> periodsOfDay,
  String? explicitCourseId,
}) {
  if (explicitCourseId != null && explicitCourseId.isNotEmpty) {
    return explicitCourseId;
  }
  for (final period in periodsOfDay) {
    if (period.type != PeriodType.classes) continue;
    final courseId = period.fromUid;
    if (courseId == null || courseId.isEmpty) continue;
    if (!startedAt.isBefore(period.startTime) &&
        startedAt.isBefore(period.endTime)) {
      return courseId;
    }
  }
  return null;
}
