import 'package:celechron/model/period.dart';
import 'package:celechron/utils/utils.dart';
// ===== MOD: 循环保护（防卡死）=====
import 'package:celechron/mod/loop_guard.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:uuid/uuid.dart';
import 'package:hive/hive.dart';
import 'package:quiver/time.dart';

/// 任务的时间语义。前三个是历史值（内含一个内部值），后两个是 P1 新增。
///
/// ⚠️ 这个枚举以**序号**存进 Hive，所以只能往后追加，绝不能插入或调序，
/// 否则会读错用户已有数据。
enum TaskType {
  deadline, // 0 截止：只有截止时间
  fixed, // 1 活动：开始与结束都固定
  fixedlegacy, // 2 内部用：《过去日程》副本，界面上不暴露
  remind, // 3 提醒：单个时刻，到点响一次，过期不标红
  memo, // 4 备忘：不设时间、不提醒、永不逾期、不进日历
}

enum TaskStatus { running, suspended, completed, failed, deleted, outdated }

enum TaskRepeatType { norepeat, days, month, year, weekday }

/// 详情页 / 卡片上「时间状态」那一行的文案与颜色倾向。
///
/// 见 [Task.timeStatus]：四类时间语义在这里统一决定「显示什么、红不红」。
class TaskTimeStatus {
  final String text;

  /// 是否该标红（只有截止型已经过期才是 true）。
  final bool urgent;

  const TaskTimeStatus(this.text, this.urgent);
}

/// 把时长写成人话：「2 天 3 小时」「5 分钟」「不到 1 分钟」。
String humanDuration(Duration d) {
  d = d.isNegative ? -d : d;
  final days = d.inDays;
  final hours = d.inHours % 24;
  final minutes = d.inMinutes % 60;
  if (days > 0) return '$days 天 $hours 小时';
  if (hours > 0) return '$hours 小时 $minutes 分钟';
  if (minutes > 0) return '$minutes 分钟';
  return '不到 1 分钟';
}

const Map<TaskType, String> deadlineTypeName = {
  TaskType.deadline: 'DDL',
  TaskType.fixed: '日程',
  TaskType.fixedlegacy: '过去日程',
  TaskType.remind: '提醒',
  TaskType.memo: '备忘',
};

/// ===== P1：四种时间语义的显示名与一句话说明 =====
///
/// 只在「类型选择器」上用；`fixedlegacy` 是内部值，界面上不出现。
const Map<TaskType, String> taskKindName = {
  TaskType.fixed: '活动',
  TaskType.deadline: '截止',
  TaskType.remind: '提醒',
  TaskType.memo: '备忘',
};

/// 每种类型下方那句解释，帮人一眼明白选它会怎样。
const Map<TaskType, String> taskKindHint = {
  TaskType.fixed: '有开始和结束，占一段时间；提醒锚「开始」，日历里占时段',
  TaskType.deadline: '只有一个截止时刻，过期会标红；提醒锚「截止」',
  TaskType.remind: '单个时刻，到点提醒一次；过期不标红',
  TaskType.memo: '随手记下，不设时间、不提醒、永不逾期、不进日历',
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

  // ===== P2：行程型子待办（只追加序号，绝不能插入/调序）=====
  // 「这一步几点开始」+「提前几分钟提醒」。两个都为 null 的就是老式的
  // 「清单型」步骤（写论文 → 查文献 / 写提纲），行为跟以前完全一样。
  @HiveField(9)
  DateTime? startTime;
  @HiveField(10)
  int? reminderMinutes;

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
    this.startTime,
    this.reminderMinutes,
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
    DateTime? startTime,
    int? reminderMinutes,
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
        startTime: startTime ?? this.startTime,
        reminderMinutes: reminderMinutes ?? this.reminderMinutes,
      );

  // ---------------------------------------------------------- 行程型判定

  /// 行程型：这一步有自己的时间。清单型为 false（行为与以前一致）。
  bool get hasTime => startTime != null || endTime != null;

  /// 这一步的「那一刻」：只给了开始时间就用它，只给了结束时间也用它。
  DateTime? get anchorTime => startTime ?? endTime;

  /// 是不是一段（而不是一个时刻）。详情页里段显示成 `14:30-17:30`。
  bool get isSpan {
    final s = startTime;
    final e = endTime;
    return s != null && e != null && s.isBefore(e);
  }

  /// 现在正处在这一步里 —— 详情页高亮它（已经过去的时段不算）。
  bool isOngoingAt(DateTime now) {
    if (done || !isSpan) return false;
    return !now.isBefore(startTime!) && now.isBefore(endTime!);
  }

  /// 这一步已经过去了、而且没勾完 —— 详情页标红。
  bool isMissedAt(DateTime now) {
    if (done) return false;
    final due = endTime ?? startTime;
    if (due == null) return false;
    return due.isBefore(now);
  }

  /// 这一步该在什么时候提醒：`开始时间 − 提前量`。
  ///
  /// 没单独设提前量就用全局默认（设置里的「默认提醒提前量」）；
  /// 没有时间、或者已经勾完的步骤不提醒（返回 null）。
  DateTime? reminderAt(int defaultLeadMinutes) {
    if (done) return null;
    final anchor = anchorTime;
    if (anchor == null) return null;
    final lead = reminderMinutes ?? defaultLeadMinutes;
    return anchor.subtract(Duration(minutes: lead < 0 ? 0 : lead));
  }

  /// 由「新建窗口」返回的 Task 生成子待办
  factory SubTask.fromTask(Task task) => SubTask(
        title: task.summary,
        description: task.description,
        // 只有「活动」形态的时段才记开始时间；单时刻的步骤只留那一刻
        startTime: task.hasTimeRange ? task.startTime : null,
        endTime: task.endTime,
        priority: task.priority,
        tags: List<String>.of(task.tags),
        attachments: List<TaskAttachment>.of(task.attachments),
        location: task.location,
      );

  void applyFromTask(Task task) {
    title = task.summary;
    description = task.description;
    startTime = task.hasTimeRange ? task.startTime : null;
    endTime = task.endTime;
    priority = task.priority;
    tags = List<String>.of(task.tags);
    attachments = List<TaskAttachment>.of(task.attachments);
    location = task.location;
  }

  /// 反向装回一个 Task，供新建/编辑窗口预填
  ///
  /// 有开始时间就装成「活动」（时段），否则装成单时刻 —— 这就是这一步在
  /// 界面上的两种样子，类型胶囊会跟着停在对应的那一个上。
  Task toTask() {
    final end = endTime ?? DateTime.now().add(const Duration(days: 1));
    final start = startTime;
    final task = Task(
      summary: title,
      description: description,
      endTime: end,
      startTime: start ?? end,
      repeatEndsTime: dateOnly(end),
      location: location,
    );
    task.reset();
    task.summary = title;
    task.description = description;
    task.location = location;
    task.startTime = start ?? end;
    task.endTime = end;
    task.repeatEndsTime = dateOnly(end);
    task.priority = priority;
    task.tags = List<String>.of(tags);
    task.attachments = List<TaskAttachment>.of(attachments);
    task.type = (start != null && start.isBefore(end))
        ? TaskType.fixed
        : TaskType.deadline;
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
  // ===== P5：序号 4 / 8 / 14 已经废弃 =====
  // 它们本来是「时间规划」的 timeNeeded / isBreakable / blockArrangements。
  // Hive 的记录是**稀疏的「序号 → 值」映射**，所以只要**不再写、不再读**这几个
  // 序号就行 —— 其余序号一个都不用动，老数据零风险（不需要迁移脚本）。
  // 注意 timeSpent(3) 没有废弃：它现在表示**专注累计时长**（见 FocusSession）。
  @HiveField(3)
  Duration timeSpent;
  @HiveField(5)
  DateTime endTime;
  @HiveField(6)
  String location;
  @HiveField(7)
  String summary;

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
    required this.endTime,
    this.location = '',
    this.summary = '',
    this.type = TaskType.deadline,
    required this.startTime,
    this.repeatType = TaskRepeatType.norepeat,
    this.repeatPeriod = 1,
    required this.repeatEndsTime,
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

  // ===== P1：四种时间语义 =====
  // 活动（fixed，有起止）/ 截止（deadline，只要截止）/ 提醒（remind，单时刻）/
  // 备忘（memo，不设时间）。全部由 type 映射得到，**不新增存储字段**。

  /// 是否「活动」：有开始与结束时间。
  bool get isEvent => type == TaskType.fixed || type == TaskType.fixedlegacy;

  /// 是否「提醒」：单时刻，到点响一次。
  bool get isRemind => type == TaskType.remind;

  /// 是否「备忘」：不提醒、永不逾期、不进日历。
  bool get isMemo => type == TaskType.memo;

  /// 是否进日历：活动 / 截止 / 提醒都进，备忘不进。
  bool get showsInCalendar => !isMemo;

  /// 是否需要调度提醒（备忘永不调度）。
  bool get schedulesReminder => reminderEnabled && !isMemo;

  /// 提醒锚点：活动锚「开始」，截止与提醒锚「那一刻」（截止即 endTime）。
  DateTime get reminderAnchor => isEvent ? startTime : endTime;

  /// 提醒触发时间：显式设过就用它，否则用锚点。
  ///
  /// 注意这里是**锚点本身**，不含「提前量」；提前量由设置里的
  /// 默认值或用户显式设置的 reminderTime 决定。
  DateTime get reminderTargetTime => reminderTime ?? reminderAnchor;

  /// 距离截止的剩余时间，已过期则为负。
  Duration get remainingTime => endTime.difference(DateTime.now());

  /// 是否已过期：**只有截止型会过期**。
  ///
  /// 备忘型永不逾期；提醒型过了也不标红（它只是"响过一次"）；
  /// 活动型结束后由 P1 的自动归档处理，不算逾期。
  bool get isOverdue =>
      type == TaskType.deadline && endTime.isBefore(DateTime.now());

  /// 详情页 / 卡片上那行「时间状态」：文案 + 是否该标红。
  ///
  /// 备忘型返回 null（不显示这一行）。这是四类时间语义在界面上
  /// 唯一一处「红不红」的判定来源，避免各页面各写一套。
  TaskTimeStatus? get timeStatus {
    final now = DateTime.now();
    if (isMemo) return null;
    if (isRemind) {
      final d = endTime.difference(now);
      // 提醒型过期不标红
      return TaskTimeStatus(
        d.isNegative ? '提醒已过 ${humanDuration(-d)}' : '距提醒 ${humanDuration(d)}',
        false,
      );
    }
    if (isEvent) {
      if (now.isBefore(startTime)) {
        return TaskTimeStatus(
            '距开始 ${humanDuration(startTime.difference(now))}', false);
      }
      if (now.isBefore(endTime)) return const TaskTimeStatus('进行中', false);
      return TaskTimeStatus('已结束 ${humanDuration(now.difference(endTime))}', false);
    }
    final d = endTime.difference(now);
    return TaskTimeStatus(
      d.isNegative ? '已超时 ${humanDuration(-d)}' : '剩 ${humanDuration(d)}',
      d.isNegative,
    );
  }

  /// 依据起止时间在「活动 / 截止」之间推断类型。
  ///
  /// 提醒型与备忘型是用户的显式选择，**不参与自动翻转**；
  /// fixedlegacy 是内部值，同样不动。
  void normalizeType() {
    if (type == TaskType.fixedlegacy ||
        type == TaskType.remind ||
        type == TaskType.memo) {
      return;
    }
    type = startTime.isBefore(endTime) ? TaskType.fixed : TaskType.deadline;
  }

  /// 显式切换时间语义：把时间字段调整成该类型需要的样子。
  ///
  /// 与 [normalizeType] 不同，这里之后**不会**再被起止时间自动翻转：
  /// 用户选了「提醒」「备忘」就一直是它（见 normalizeType 的早退分支）。
  /// 创建页、详情页、「其他日期」面板共用这一处逻辑。
  void applyKind(TaskType kind) {
    switch (kind) {
      case TaskType.fixed:
        // 活动：必须有 开始 < 结束，否则给个 1 小时的默认时段
        if (!startTime.isBefore(endTime)) {
          startTime = endTime.subtract(const Duration(hours: 1));
        }
        break;
      case TaskType.deadline:
      case TaskType.remind:
      case TaskType.memo:
      case TaskType.fixedlegacy:
        // 单时刻：start 与 end 重合（备忘内部也存占位值以满足模型约束）
        startTime = endTime;
        break;
    }
    type = kind;
    if (kind == TaskType.remind) {
      // 提醒型「到点响一次」：默认打开提醒，且不提前（reminderTime 留空
      // 就会用锚点本身 = endTime 那一刻）
      reminderEnabled = true;
      reminderTime = null;
    }
    if (kind == TaskType.memo) {
      // 备忘永不提醒
      reminderEnabled = false;
      reminderTime = null;
    }
  }

  /// 该类型下「结束时间」这一行该怎么称呼。
  String get endTimeLabel {
    if (isMemo) return '时间';
    if (isRemind) return '提醒时刻';
    return isEvent ? '结束时间' : '截止时间';
  }

  /// 是否该「结束后自动归档」到「我已处理」。
  ///
  /// 只针对**不重复**的活动：重复日程会由 calendar/task_controller 的滚动逻辑
  /// 推进到下一期（并留一份《过去日程》），不需要归档；
  /// 截止型过期仍然留在「待我处理」（只是标红），提醒型过期也不归档。
  bool get needsAutoArchive =>
      isEvent &&
      type != TaskType.fixedlegacy &&
      repeatType == TaskRepeatType.norepeat &&
      status != TaskStatus.completed &&
      status != TaskStatus.deleted &&
      status != TaskStatus.outdated &&
      endTime.isBefore(DateTime.now());

  /// 活动已经结束、但还有没勾完的子待办 —— 详情页会红字提示一句。
  bool get hasUnfinishedSubtasks =>
      isEvent &&
      subtasks.isNotEmpty &&
      subtaskDoneCount < subtasks.length &&
      endTime.isBefore(DateTime.now());

  /// ===== P2：行程型待办的「下一步」 =====
  ///
  /// 第一个还没完成、且带时间的步骤（按时间排序）。
  /// 卡片上用它代替光秃秃的 `子待办 0/3`。
  SubTask? get nextItineraryStep {
    final pending = subtasks
        .where((s) => s.hasTime && !s.done && s.anchorTime != null)
        .toList()
      ..sort((a, b) => a.anchorTime!.compareTo(b.anchorTime!));
    return pending.isEmpty ? null : pending.first;
  }

  /// 这组子待办是不是「行程型」（有任何一步带时间）
  bool get hasItinerary => subtasks.any((s) => s.hasTime);

  /// 是否是带时段的任务（显示为「开始于 / 结束于」）。
  bool get hasTimeRange => startTime.isBefore(endTime);

  void reset() {
    genUid();
    status = TaskStatus.deleted;
    description = "";
    timeSpent = const Duration(minutes: 0);
    endTime = DateTime.now();
    endTime = DateTime(
        endTime.year, endTime.month, endTime.day, endTime.hour, endTime.minute);
    location = "";
    summary = "";

    type = TaskType.deadline;
    startTime = endTime;
    repeatType = TaskRepeatType.norepeat;
    repeatPeriod = 1;
    repeatEndsTime = DateTime(startTime.year, startTime.month, startTime.day);
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
    endTime = another.endTime;
    location = another.location;
    summary = another.summary;
    type = another.type;
    startTime = another.startTime;
    repeatType = another.repeatType;
    repeatPeriod = another.repeatPeriod;
    repeatEndsTime = another.repeatEndsTime;
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
    DateTime? endTime,
    String? location,
    String? summary,
    TaskType? type,
    DateTime? startTime,
    TaskRepeatType? repeatType,
    int? repeatPeriod,
    DateTime? repeatEndsTime,
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
      endTime: endTime ?? this.endTime,
      location: location ?? this.location,
      summary: summary ?? this.summary,
      type: type ?? this.type,
      startTime: startTime ?? this.startTime,
      repeatType: repeatType ?? this.repeatType,
      repeatPeriod: repeatPeriod ?? this.repeatPeriod,
      repeatEndsTime: repeatEndsTime ?? this.repeatEndsTime,
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
    } else if (type == TaskType.remind || type == TaskType.memo) {
      // 提醒型过了也不标红、备忘型永不逾期：两者都不会变成「已过期」
      if (status == TaskStatus.completed) return;
      status = TaskStatus.running;
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
    } else if (type == TaskType.remind || type == TaskType.memo) {
      // 提醒型过了也不标红、备忘型永不逾期：两者都不会变成「已过期」
      if (status == TaskStatus.completed) return;
      status = TaskStatus.running;
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
        (type == TaskType.fixed && endTime != another.endTime) ||
        endTime != another.endTime ||
        status != another.status ||
        repeatType != another.repeatType ||
        repeatPeriod != another.repeatPeriod ||
        repeatEndsTime != another.repeatEndsTime) {
      return true;
    }
    return false;
  }
}
