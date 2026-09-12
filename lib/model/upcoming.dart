import 'package:celechron/model/period.dart';
import 'package:celechron/model/task.dart';

/// 「接下来」列表里一条的性质 —— 决定图标与配色。
enum UpcomingKind {
  /// 课程（来自教务网课表）
  course,

  /// 考试
  exam,

  /// 自己安排的日程（`PeriodType.user` 或活动型待办）
  activity,

  /// 截止型待办（排序用它的**提醒时间**）
  deadline,

  /// 提醒型待办（就是那一刻）
  remind,
}

/// 「接下来」列表里的一条。
///
/// **排序索引**（用户定的口径）：
/// - 课程 / 考试 / 日程 → 它们的**开始时间**
/// - 除备忘外的待办 → 它的**提醒时间**
///
/// 备忘型待办**永远不出现**（它本来就不提醒、也没有时间）。
class UpcomingItem {
  final UpcomingKind kind;

  /// 排序与显示用的时刻
  final DateTime at;

  /// 结束时刻（课程/活动有；截止型与提醒型为 null）
  final DateTime? until;

  final String title;

  /// 地点（没有就是空字符串）
  final String location;

  /// 备注里的一行（课程显示教师/课程代码里的有用部分，待办显示描述首行）
  final String detail;

  /// 属于待办时带上它 —— 点这条就打开待办的详情页
  final Task? task;

  /// 属于日程（课程/考试/自己安排的日程）时带上它
  final Period? period;

  const UpcomingItem({
    required this.kind,
    required this.at,
    required this.title,
    this.until,
    this.location = '',
    this.detail = '',
    this.task,
    this.period,
  });

  /// 正在进行中（已经开始了但还没结束）
  bool isRunningAt(DateTime now) {
    final end = until;
    return end != null && !at.isAfter(now) && end.isAfter(now);
  }

  /// 同一条在数据里可能既有待办又有生成的日程 —— 用来去重
  String get dedupeKey {
    final own = task?.uid;
    if (own != null) return 'task:$own';
    final mine = period?.uid;
    return 'period:${mine ?? '$title@${at.toIso8601String()}'}';
  }
}

/// 「接下来」的**纯逻辑**：过滤 + 排序 + 限量。界面只负责画。
///
/// - [horizon] 时间上取多远（默认 7 天）
/// - [limit] 最多几条（默认 8 条）
/// - 进行中的一条**保留**（否则正在上课时会显示「下一节」，反直觉）
List<UpcomingItem> buildUpcoming({
  required List<Period> periods,
  required List<Task> tasks,
  required DateTime now,
  Duration horizon = const Duration(days: 7),
  int limit = 8,
}) {
  final deadline = now.add(horizon);
  final items = <UpcomingItem>[];

  // ---------------------------------------------- 课程 / 考试 / 日程
  for (final period in periods) {
    if (period.type == PeriodType.virtual) continue;
    // 已经结束的不看；进行中的保留
    if (!period.endTime.isAfter(now)) continue;
    if (period.startTime.isAfter(deadline)) continue;
    items.add(UpcomingItem(
      kind: switch (period.type) {
        PeriodType.test => UpcomingKind.exam,
        PeriodType.classes => UpcomingKind.course,
        _ => UpcomingKind.activity,
      },
      at: period.startTime,
      until: period.endTime,
      title: period.summary.trim().isEmpty ? '(未命名)' : period.summary.trim(),
      location: period.location.trim(),
      detail: _courseDetail(period.description),
      period: period,
    ));
  }

  // ------------------------------------------------------------ 待办
  for (final task in tasks) {
    if (task.status == TaskStatus.completed ||
        task.status == TaskStatus.deleted) {
      continue;
    }
    if (task.isMemo) continue; // 备忘永远不进「接下来」
    if (task.type == TaskType.fixedlegacy && task.fromUid != null) {
      // 《过去日程》副本不是「接下来」，跳过
      continue;
    }

    // 活动型：按开始时间排（有起止，属于日程）
    if (task.isEvent) {
      if (!task.endTime.isAfter(now)) continue;
      if (task.startTime.isAfter(deadline)) continue;
      items.add(UpcomingItem(
        kind: UpcomingKind.activity,
        at: task.startTime,
        until: task.endTime,
        title: _taskTitle(task),
        location: task.location.trim(),
        detail: _firstLine(task.description),
        task: task,
      ));
      continue;
    }

    // 截止型 / 提醒型：按**提醒时间**排；提醒时间早于现在就不用再提示了
    final at = task.reminderTargetTime;
    if (!at.isAfter(now)) continue;
    if (at.isAfter(deadline)) continue;
    items.add(UpcomingItem(
      kind: task.isRemind ? UpcomingKind.remind : UpcomingKind.deadline,
      at: at,
      title: _taskTitle(task),
      location: task.location.trim(),
      detail: _firstLine(task.description),
      task: task,
    ));
  }

  items.sort((a, b) => a.at.compareTo(b.at));

  // 去重（同一个 uid 只留最早的一条 —— 比如活动型待办的多个生成块）
  final seen = <String>{};
  final result = <UpcomingItem>[];
  for (final item in items) {
    if (!seen.add(item.dedupeKey)) continue;
    result.add(item);
    if (result.length >= limit) break;
  }
  return result;
}

String _taskTitle(Task task) =>
    task.summary.trim().isEmpty ? '(未命名待办)' : task.summary.trim();

String _firstLine(String text) {
  final line = text.trim().split('\n').first.trim();
  return line.length > 40 ? '${line.substring(0, 40)}…' : line;
}

/// 课程备注里第一行通常是「教师: xxx」；课程代码那一行对「接下来」没用，丢掉。
String _courseDetail(String description) {
  for (final raw in description.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('课程代码')) continue;
    if (line.startsWith('教学时间安排')) continue;
    return line;
  }
  return '';
}

/// 大字那条的倒计时文案。
///
/// - 进行中 → 「进行中」
/// - 不到一分钟 → 「马上开始」
/// - 否则 → 「还有 3 小时 20 分」
String upcomingCountdown(UpcomingItem item, DateTime now) {
  if (item.isRunningAt(now)) return '进行中';
  final gap = item.at.difference(now);
  if (gap.inMinutes < 1) return '马上开始';
  if (gap.inHours < 1) return '还有 ${gap.inMinutes} 分钟';
  final hours = gap.inHours;
  final minutes = gap.inMinutes % 60;
  if (hours < 24) {
    return minutes > 0 ? '还有 $hours 小时 $minutes 分' : '还有 $hours 小时';
  }
  final days = gap.inDays;
  final restHours = hours % 24;
  return restHours > 0 ? '还有 $days 天 $restHours 小时' : '还有 $days 天';
}

/// 「今天 14:30」/「明天 08:00」/「9 月 15 日 13:30」这种一眼能读的时刻
String upcomingWhen(UpcomingItem item, DateTime now) {
  final at = item.at;
  String two(int value) => value.toString().padLeft(2, '0');
  final clock = '${two(at.hour)}:${two(at.minute)}';
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(at.year, at.month, at.day);
  final diff = day.difference(today).inDays;
  if (diff == 0) return '今天 $clock';
  if (diff == 1) return '明天 $clock';
  if (diff == 2) return '后天 $clock';
  return '${at.month} 月 ${at.day} 日 $clock';
}
