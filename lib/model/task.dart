import 'package:celechron/model/period.dart';
import 'package:celechron/utils/utils.dart';
// ===== MOD: 循环保护（防卡死）=====
import 'package:celechron/mod/loop_guard.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:uuid/uuid.dart';
import 'package:hive/hive.dart';
import 'package:quiver/time.dart';

enum TaskType {
  deadline, // 只有结束时间固定的《真DDL》
  fixed, // 开始和结束时间都固定的《日程》
  fixedlegacy // 已过的《日程》
}

enum TaskStatus { running, suspended, completed, failed, deleted, outdated }

enum TaskRepeatType { norepeat, days, month, year, weekday }

const Map<TaskType, String> deadlineTypeName = {
  TaskType.deadline: 'DDL',
  TaskType.fixed: '日程',
  TaskType.fixedlegacy: '过去日程',
};

const Map<TaskStatus, String> deadlineStatusName = {
  TaskStatus.running: '进行中',
  TaskStatus.suspended: '已暂停',
  TaskStatus.completed: '完成',
  TaskStatus.failed: '已过期', // DDL 失败
  TaskStatus.deleted: '已删除',
  TaskStatus.outdated: '已过期',
};

const Map<TaskRepeatType, String> deadlineRepeatTypeName = {
  TaskRepeatType.norepeat: '不重复',
  TaskRepeatType.days: '每隔几天',
  TaskRepeatType.month: '每月的这一天',
  TaskRepeatType.year: '每年的这一天',
  TaskRepeatType.weekday: '每周工作日',
};

/// 「无限重复」的哨兵值：没有结束日期的重复统一存这个日期。
final DateTime kRepeatEndlessDate = DateTime(2099, 12, 31);

bool isRepeatEndless(DateTime endsTime) =>
    !endsTime.isBefore(kRepeatEndlessDate);

enum TaskPriority { low, normal, high, urgent }

const Map<TaskPriority, String> taskPriorityName = {
  TaskPriority.low: '低',
  TaskPriority.normal: '普通',
  TaskPriority.high: '高',
  TaskPriority.urgent: '紧急',
};

/// 子待办：用「跟正常待办一样的新建窗口」创建，因此保留了主要字段。
@HiveType(typeId: 14)
class SubTask {
  @HiveField(0)
  String uid;
  @HiveField(1)
  String title;
  @HiveField(2)
  bool done;
  // ===== 以下 4 个字段（timeSpent/timeNeeded/isBreakable/blockArrangements）
// 属于已移除的「时间规划」功能。**只保留字段，不删** —— 它们是 Hive 按序号存储的，
// 删掉会让后面所有字段的序号前移，导致已有待办数据被读错。等数据迁移时再清理。=====
  @HiveField(3)
  String description;
  @HiveField(4)
  DateTime? endTime;
  @HiveField(5)
  TaskPriority priority;
  @HiveField(6)
  List<String> tags;
  @HiveField(7)
  List<TaskAttachment> attachments;
  @HiveField(8)
  String location;

  SubTask({
    String? uid,
    this.title = '',
    this.done = false,
    this.description = '',
    this.endTime,
    this.priority = TaskPriority.normal,
    List<String>? tags,
    List<TaskAttachment>? attachments,
    this.location = '',
  })  : uid = uid ?? const Uuid().v4(),
        tags = tags ?? <String>[],
        attachments = attachments ?? <TaskAttachment>[];

  SubTask copyWith({
    String? title,
    bool? done,
    String? description,
    DateTime? endTime,
    TaskPriority? priority,
    List<String>? tags,
    List<TaskAttachment>? attachments,
    String? location,
  }) =>
      SubTask(
        uid: uid,
        title: title ?? this.title,
        done: done ?? this.done,
        description: description ?? this.description,
        endTime: endTime ?? this.endTime,
        priority: priority ?? this.priority,
        tags: tags ?? List<String>.of(this.tags),
        attachments: attachments ?? List<TaskAttachment>.of(this.attachments),
        location: location ?? this.location,
      );

  /// 由「新建窗口」返回的 Task 生成子待办
  factory SubTask.fromTask(Task task) => SubTask(
        title: task.summary,
        description: task.description,
        endTime: task.endTime,
        priority: task.priority,
        tags: List<String>.of(task.tags),
        attachments: List<TaskAttachment>.of(task.attachments),
        location: task.location,
      );

  void applyFromTask(Task task) {
    title = task.summary;
    description = task.description;
    endTime = task.endTime;
    priority = task.priority;
    tags = List<String>.of(task.tags);
    attachments = List<TaskAttachment>.of(task.attachments);
    location = task.location;
  }

  /// 反向装回一个 Task，供新建/编辑窗口预填
  Task toTask() {
    final end = endTime ?? DateTime.now().add(const Duration(days: 1));
    final task = Task(
      summary: title,
      description: description,
      endTime: end,
      startTime: end,
      repeatEndsTime: dateOnly(end),
      location: location,
    );
    task.reset();
    task.summary = title;
    task.description = description;
    task.location = location;
    task.startTime = end;
    task.endTime = end;
    task.repeatEndsTime = dateOnly(end);
    task.priority = priority;
    task.tags = List<String>.of(tags);
    task.attachments = List<TaskAttachment>.of(attachments);
    return task;
  }
}

/// 附件：仅保存本地文件引用（选中的文件会被复制到应用目录）。
@HiveType(typeId: 15)
class TaskAttachment {
  @HiveField(0)
  String name;
  @HiveField(1)
  String path;
  @HiveField(2)
  int size;

  TaskAttachment({this.name = '', this.path = '', this.size = 0});
}

/// 评论/备注：本地记录，不涉及多人协作。
@HiveType(typeId: 16)
class TaskComment {
  @HiveField(0)
  String content;
  @HiveField(1)
  DateTime time;

  TaskComment({this.content = '', required this.time});
}

class DateTimePair {
  DateTime first, second;
  DateTimePair({required this.first, required this.second});
}

DateTimePair? chopDatePeriod(
    DateTime startTime, DateTime endTime, DateTime date) {
  DateTime startDate = dateOnly(startTime);
  DateTime endDate = dateOnly(endTime);
  date = dateOnly(date);

  if (date.isBefore(startDate) || date.isAfter(endDate)) {
    return null;
  }
  DateTime l = dateOnly(date);
  DateTime r = dateOnly(date, hour: 24, minute: 00);
  if (isSameDay(date, startDate)) {
    l = dateOnly(date, hour: startTime.hour, minute: startTime.minute);
  }
  if (isSameDay(date, endDate)) {
    r = dateOnly(date, hour: endTime.hour, minute: endTime.minute);
  }
  if (l == r) return null;
  return DateTimePair(first: l, second: r);
}

@HiveType(typeId: 6)
class Task {
  @HiveField(0)
  String uid;
  @HiveField(1)
  TaskStatus status;
  @HiveField(2)
  String description;
  // ===== 以下 4 个字段（timeSpent/timeNeeded/isBreakable/blockArrangements）
// 属于已移除的「时间规划」功能。**只保留字段，不删** —— 它们是 Hive 按序号存储的，
// 删掉会让后面所有字段的序号前移，导致已有待办数据被读错。等数据迁移时再清理。=====
  @HiveField(3)
  Duration timeSpent;
  @HiveField(4)
  Duration timeNeeded;
  @HiveField(5)
  DateTime endTime;
  @HiveField(6)
  String location;
  @HiveField(7)
  String summary;
  @HiveField(8)
  bool isBreakable;

  @HiveField(9)
  TaskType type;
  @HiveField(10)
  DateTime startTime;
  @HiveField(11)
  TaskRepeatType repeatType;
  @HiveField(12)
  int repeatPeriod; // 固定日程重复的周期（单位为天）。
  @HiveField(13)
  DateTime repeatEndsTime; // 固定日程重复的截止日期（没有时间）。晚于这个日期的话就不再重复。
  @HiveField(14)
  bool blockArrangements;
  @HiveField(15)
  String? fromUid;
  @HiveField(16)
  List<SubTask> subtasks;
  @HiveField(17)
  TaskPriority priority;
  @HiveField(18)
  bool reminderEnabled;
  @HiveField(19)
  DateTime? reminderTime;
  @HiveField(20)
  List<TaskAttachment> attachments;
  @HiveField(21)
  List<TaskComment> comments;
  @HiveField(22)
  List<String> tags;
  @HiveField(23)
  bool starred;
  @HiveField(24)
  DateTime? createdAt;
  @HiveField(25)
  DateTime? updatedAt;

  Task({
    this.uid = '114514',
    this.status = TaskStatus.running,
    this.description = '',
    this.timeSpent = const Duration(minutes: 0),
    this.timeNeeded = const Duration(hours: 1),
    required this.endTime,
    this.location = '',
    this.summary = '',
    this.isBreakable = false,
    this.type = TaskType.deadline,
    required this.startTime,
    this.repeatType = TaskRepeatType.norepeat,
    this.repeatPeriod = 1,
    required this.repeatEndsTime,
    this.blockArrangements = true,
    this.fromUid,
    List<SubTask>? subtasks,
    this.priority = TaskPriority.normal,
    this.reminderEnabled = false,
    this.reminderTime,
    List<TaskAttachment>? attachments,
    List<TaskComment>? comments,
    List<String>? tags,
    this.starred = false,
    this.createdAt,
    this.updatedAt,
  })  : subtasks = subtasks ?? <SubTask>[],
        attachments = attachments ?? <TaskAttachment>[],
        comments = comments ?? <TaskComment>[],
        tags = tags ?? <String>[];

  int get subtaskDoneCount => subtasks.where((e) => e.done).length;

  double get subtaskProgress =>
      subtasks.isEmpty ? 0.0 : subtaskDoneCount / subtasks.length;

  /// 排序用的创建时间（老数据没有就退回截止时间）
  DateTime get sortableCreatedAt => createdAt ?? endTime;

  /// 排序用的更新时间
  DateTime get sortableUpdatedAt => updatedAt ?? sortableCreatedAt;

  /// 提醒触发时间：没单独设过就用截止时间。
  DateTime get reminderTargetTime => reminderTime ?? endTime;

  /// 距离截止的剩余时间，已过期则为负。
  Duration get remainingTime => endTime.difference(DateTime.now());

  /// 统一的「待办」：显式设了开始时间（早于截止时间）就按带时段的任务处理，
  /// 否则就是只有截止时间的普通待办。界面不再暴露类型选择。
  void normalizeType() {
    if (type == TaskType.fixedlegacy) return;
    type = startTime.isBefore(endTime) ? TaskType.fixed : TaskType.deadline;
  }

  /// 是否是带时段的任务（显示为「开始于 / 结束于」）。
  bool get hasTimeRange => startTime.isBefore(endTime);

  void reset() {
    genUid();
    status = TaskStatus.deleted;
    description = "";
    timeSpent = const Duration(minutes: 0);
    timeNeeded = const Duration(hours: 1);
    endTime = DateTime.now();
    endTime = DateTime(
        endTime.year, endTime.month, endTime.day, endTime.hour, endTime.minute);
    location = "";
    summary = "";
    isBreakable = true;

    type = TaskType.deadline;
    startTime = endTime;
    repeatType = TaskRepeatType.norepeat;
    repeatPeriod = 1;
    repeatEndsTime = DateTime(startTime.year, startTime.month, startTime.day);
    blockArrangements = true;
    fromUid = null;
    subtasks = <SubTask>[];
    priority = TaskPriority.normal;
    reminderEnabled = false;
    reminderTime = null;
    attachments = <TaskAttachment>[];
    comments = <TaskComment>[];
    tags = <String>[];
    starred = false;
    createdAt = DateTime.now();
    updatedAt = DateTime.now();
  }

  void copy(Task another) {
    uid = another.uid;
    status = another.status;
    description = another.description;
    timeSpent = another.timeSpent;
    timeNeeded = another.timeNeeded;
    endTime = another.endTime;
    location = another.location;
    summary = another.summary;
    isBreakable = another.isBreakable;
    type = another.type;
    startTime = another.startTime;
    repeatType = another.repeatType;
    repeatPeriod = another.repeatPeriod;
    repeatEndsTime = another.repeatEndsTime;
    blockArrangements = another.blockArrangements;
    fromUid = another.fromUid;
    subtasks = another.subtasks.map((e) => e.copyWith()).toList();
    priority = another.priority;
    reminderEnabled = another.reminderEnabled;
    reminderTime = another.reminderTime;
    attachments = List<TaskAttachment>.of(another.attachments);
    comments = List<TaskComment>.of(another.comments);
    tags = List<String>.of(another.tags);
    starred = another.starred;
    createdAt = another.createdAt;
    updatedAt = another.updatedAt;
  }

  Task copyWith({
    String? uid,
    TaskStatus? status,
    String? description,
    Duration? timeSpent,
    Duration? timeNeeded,
    DateTime? endTime,
    String? location,
    String? summary,
    bool? isBreakable,
    TaskType? type,
    DateTime? startTime,
    TaskRepeatType? repeatType,
    int? repeatPeriod,
    DateTime? repeatEndsTime,
    bool? blockArrangements,
    String? fromUid,
    List<SubTask>? subtasks,
    TaskPriority? priority,
    bool? reminderEnabled,
    DateTime? reminderTime,
    List<TaskAttachment>? attachments,
    List<TaskComment>? comments,
    List<String>? tags,
    bool? starred,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Task(
      uid: uid ?? this.uid,
      status: status ?? this.status,
      description: description ?? this.description,
      timeSpent: timeSpent ?? this.timeSpent,
      timeNeeded: timeNeeded ?? this.timeNeeded,
      endTime: endTime ?? this.endTime,
      location: location ?? this.location,
      summary: summary ?? this.summary,
      isBreakable: isBreakable ?? this.isBreakable,
      type: type ?? this.type,
      startTime: startTime ?? this.startTime,
      repeatType: repeatType ?? this.repeatType,
      repeatPeriod: repeatPeriod ?? this.repeatPeriod,
      repeatEndsTime: repeatEndsTime ?? this.repeatEndsTime,
      blockArrangements: blockArrangements ?? this.blockArrangements,
      fromUid: fromUid ?? this.fromUid,
      subtasks: subtasks ?? this.subtasks.map((e) => e.copyWith()).toList(),
      priority: priority ?? this.priority,
      reminderEnabled: reminderEnabled ?? this.reminderEnabled,
      reminderTime: reminderTime ?? this.reminderTime,
      attachments: attachments ?? List<TaskAttachment>.of(this.attachments),
      comments: comments ?? List<TaskComment>.of(this.comments),
      tags: tags ?? List<String>.of(this.tags),
      starred: starred ?? this.starred,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  void genUid() {
    uid = const Uuid().v4();
  }

  bool checkTimeValid() {
    startTime = DateTime(startTime.year, startTime.month, startTime.day,
        startTime.hour, startTime.minute);
    endTime = DateTime(
        endTime.year, endTime.month, endTime.day, endTime.hour, endTime.minute);
    if (!startTime.isBefore(endTime)) {
      return false;
    }
    return true;
  }

  double getProgress() {
    double progress = 0;
    if (type == TaskType.fixed) {
      if (DateTime.now().isBefore(startTime)) {
        progress = 0;
      } else if (DateTime.now().isAfter(endTime)) {
        progress = 1;
      } else {
        progress = (DateTime.now().difference(startTime).inSeconds) /
            (endTime.difference(startTime).inSeconds);
      }
    } else if (type == TaskType.deadline) {
      progress = timeSpent.inSeconds / timeNeeded.inSeconds;
    }
    if (progress > 1) {
      progress = 1;
    }
    if (progress < 0) {
      progress = 0;
    }
    return progress;
  }

  void refreshStatus() {
    if (type == TaskType.deadline) {
      // 完成只由「打钩」决定（界面已移除时间安排，不再按用时自动完成）
      if (status == TaskStatus.completed) return;
      if (endTime.isBefore(DateTime.now())) {
        status = TaskStatus.failed;
      }
    } else if (type == TaskType.fixed) {
      // 手动打钩完成的日程保持完成状态，不被每秒的状态刷新覆盖
      if (status == TaskStatus.completed) return;
      if (dateOnly(startTime).isAfter(repeatEndsTime)) {
        status = TaskStatus.outdated;
      } else {
        status = TaskStatus.running;
      }
    }
  }

  void forceRefreshStatus() {
    if (type == TaskType.deadline) {
      if (status == TaskStatus.completed) return;
      if (endTime.isBefore(DateTime.now())) {
        status = TaskStatus.failed;
      } else {
        status = TaskStatus.running;
      }
    } else if (type == TaskType.fixed) {
      if (status == TaskStatus.completed) return;
      if (dateOnly(startTime).isAfter(repeatEndsTime)) {
        status = TaskStatus.outdated;
      } else {
        status = TaskStatus.running;
      }
    }
  }

  /// 按重复规则把 startTime / endTime 推进一个周期（不区分任务类型）。
  ///
  /// 返回是否推进成功；推进后若已越过重复截止日期，会把状态置为 outdated。
  bool advanceRepeatPeriod() {
    if (repeatType == TaskRepeatType.norepeat) return false;

    if (repeatType == TaskRepeatType.days) {
      if (repeatPeriod < 1) repeatPeriod = 1;
      if (repeatPeriod > 400) repeatPeriod = 400;
      startTime = startTime.add(Duration(days: repeatPeriod));
      endTime = endTime.add(Duration(days: repeatPeriod));
    } else if (repeatType == TaskRepeatType.weekday) {
      // 每周工作日：跳到下一个非周末的日子
      var next = startTime.add(const Duration(days: 1));
      while (next.weekday == DateTime.saturday ||
          next.weekday == DateTime.sunday) {
        next = next.add(const Duration(days: 1));
      }
      final difference = next.difference(startTime);
      startTime = next;
      endTime = endTime.add(difference);
    } else if (repeatType == TaskRepeatType.month) {
      final months =
          repeatPeriod < 1 ? 1 : (repeatPeriod > 120 ? 120 : repeatPeriod);
      DateTime nex = DateTime(startTime.year, startTime.month + months, 1);
      while (daysInMonth(nex.year, nex.month) < startTime.day) {
        nex = DateTime(nex.year, nex.month + months, 1);
      }
      nex = DateTime(nex.year, nex.month, startTime.day);
      // 用「日期」而不是「含时刻的时间」算天数差，否则非零点任务会少推一天
      int difference = nex.difference(dateOnly(startTime)).inDays;
      startTime = startTime.add(Duration(days: difference));
      endTime = endTime.add(Duration(days: difference));
    } else if (repeatType == TaskRepeatType.year) {
      final years =
          repeatPeriod < 1 ? 1 : (repeatPeriod > 50 ? 50 : repeatPeriod);
      DateTime nex = DateTime(startTime.year + years, startTime.month, 1);
      while (daysInMonth(nex.year, nex.month) < startTime.day) {
        nex = DateTime(nex.year + years, nex.month, 1);
      }
      nex = DateTime(nex.year, startTime.month, startTime.day);
      int difference = nex.difference(dateOnly(startTime)).inDays;
      startTime = startTime.add(Duration(days: difference));
      endTime = endTime.add(Duration(days: difference));
    }

    if (dateOnly(startTime).isAfter(dateOnly(repeatEndsTime))) {
      status = TaskStatus.outdated;
    }
    return true;
  }

  bool setToNextPeriod() {
    if (type != TaskType.fixed || status == TaskStatus.outdated) {
      return false;
    }
    if (repeatType == TaskRepeatType.norepeat) {
      status = TaskStatus.outdated;
      return false;
    }
    return advanceRepeatPeriod();
  }

  Period? deadlineOfTime(DateTime refTime, {bool predicting = false}) {
    if (type != TaskType.fixed) {
      return null;
    }

    Period period = Period(
      fromUid: uid,
      type: PeriodType.user,
      description: description,
      startTime: startTime,
      endTime: endTime,
      location: location,
      lastUpdateTime: DateTime.now(),
      summary: summary,
    );

    if (refTime.isBefore(startTime)) {
      if (predicting) {
        return period.copyWith(
          startTime: startTime.copyWith(),
          endTime: endTime.copyWith(),
        );
      }
      return null;
    }

    if (repeatType == TaskRepeatType.norepeat) {
      if ((predicting || !startTime.isAfter(refTime)) &&
          !endTime.isBefore(refTime)) {
        return period.copyWith(
          startTime: startTime.copyWith(),
          endTime: endTime.copyWith(),
        );
      }
      return null;
    } else {
      Task dummy = copyWith();
      final predictGuard = LoopGuard('预测下一次日程');
      while ((predicting || !dummy.startTime.isAfter(refTime)) &&
          dummy.status != TaskStatus.outdated) {
        if (predictGuard.tick()) return null;
        if (!dummy.endTime.isBefore(refTime)) {
          return period.copyWith(
              startTime: dummy.startTime.copyWith(),
              endTime: dummy.endTime.copyWith());
        }
        dummy.setToNextPeriod();
      }
      return null;
    }
  }

  List<Period> getPeriodOfDay(DateTime date) {
    if (type != TaskType.fixed && type != TaskType.fixedlegacy) {
      return [];
    }

    date = dateOnly(date);
    DateTime startDate = dateOnly(startTime);
    if (date.isBefore(startDate)) {
      return [];
    }

    Period period = Period(
      fromUid: uid,
      type: PeriodType.user,
      description: description,
      startTime: startTime.copyWith(),
      endTime: endTime.copyWith(),
      location: location,
      lastUpdateTime: DateTime.now(),
      summary: summary,
      fromFromUid: type == TaskType.fixed ? null : fromUid,
    );
    List<Period> ans = <Period>[];

    DateTimePair? pair;
    if (repeatType == TaskRepeatType.norepeat) {
      pair = chopDatePeriod(startTime, endTime, date);
      if (pair != null) {
        ans.add(period.copyWith(
          startTime: pair.first,
          endTime: pair.second,
        ));
      }
    } else {
      Task dummy = copyWith();
      final dayGuard = LoopGuard('按日拆解日程');
      while (!dateOnly(dummy.startTime).isAfter(date) &&
          dummy.status != TaskStatus.outdated) {
        if (dayGuard.tick()) break;
        if (!dateOnly(dummy.endTime).isBefore(date)) {
          pair = chopDatePeriod(dummy.startTime, dummy.endTime, date);
          if (pair != null) {
            ans.add(period.copyWith(
              startTime: pair.first,
              endTime: pair.second,
            ));
          }
        }
        dummy.setToNextPeriod();
      }
    }

    return ans;
  }

  bool differentForFlow(Task another) {
    if (type != another.type ||
        timeSpent != another.timeSpent ||
        timeNeeded != another.timeNeeded ||
        (type == TaskType.fixed && endTime != another.endTime) ||
        endTime != another.endTime ||
        status != another.status ||
        isBreakable != another.isBreakable ||
        repeatType != another.repeatType ||
        repeatPeriod != another.repeatPeriod ||
        repeatEndsTime != another.repeatEndsTime ||
        (type == TaskType.fixed &&
            blockArrangements != another.blockArrangements)) {
      return true;
    }
    return false;
  }
}
