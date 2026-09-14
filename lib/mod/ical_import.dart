import 'package:celechron/model/task.dart';
import 'package:celechron/utils/utils.dart';

/// ============ iCal（.ics）导入 ============
///
/// 只有**导入**这一半：把别人的 .ics（课程表、会议邀请、系统日历导出）
/// 变成 Elychron 的待办。按用户要求**不写系统日历**。
///
/// 设计要点：
/// - 解析是**纯函数**（[parseIcal]），便于单测；不碰数据库、不碰界面。
/// - 去重靠 iCal 自带的 `UID`：同一个文件重复导入不会产生重复待办
///   （uid 取 `ical-<原UID的哈希>`，稳定且不会与本地 uid 撞车）。
/// - 字段映射：
///   DTSTART + DTEND → **活动**（占时段）
///   只有 DTSTART     → **提醒**（单个时刻）
///   只有 DTEND       → **截止**
///   都没有            → **备忘**
class IcalImporter {
  IcalImporter._();

  /// 本地 uid 前缀，便于一眼看出这条是从 iCal 来的
  static const String uidPrefix = 'ical-';

  /// 解析 .ics 文本，取出所有 VEVENT（忽略 VTODO / 其它组件）
  static List<IcalEvent> parseIcal(String text) {
    final events = <IcalEvent>[];
    final lines = _unfold(text);

    Map<String, String> current = {};
    var inEvent = false;
    for (final line in lines) {
      final upper = line.toUpperCase();
      if (upper.startsWith('BEGIN:VEVENT')) {
        inEvent = true;
        current = {};
        continue;
      }
      if (upper.startsWith('END:VEVENT')) {
        if (inEvent) {
          final event = _buildEvent(current);
          if (event != null) events.add(event);
        }
        inEvent = false;
        current = {};
        continue;
      }
      if (!inEvent) continue;
      final colon = line.indexOf(':');
      if (colon <= 0) continue;
      final rawKey = line.substring(0, colon);
      final value = line.substring(colon + 1);
      // 形如 `DTSTART;TZID=Asia/Shanghai` / `DTSTART;VALUE=DATE`
      final key = rawKey.split(';').first.trim().toUpperCase();
      // 同名属性只取第一条（SUMMARY / DTSTART 等重复出现没有意义）
      current.putIfAbsent(key, () => value);
      // 参数信息（TZID / VALUE）另外留着，解析时间要用
      current.putIfAbsent('$key@params', () => rawKey);
    }
    return events;
  }

  /// iCal 允许把长行折成多行：续行以一个空格或制表符开头
  static List<String> _unfold(String text) {
    final raw = text.split(RegExp(r'\r\n|\n|\r'));
    final out = <String>[];
    for (final line in raw) {
      if (line.isEmpty) continue;
      if ((line.startsWith(' ') || line.startsWith('\t')) && out.isNotEmpty) {
        out[out.length - 1] = out.last + line.substring(1);
      } else {
        out.add(line);
      }
    }
    return out;
  }

  static IcalEvent? _buildEvent(Map<String, String> props) {
    final summary = _unescape(props['SUMMARY'] ?? '').trim();
    final uid = (props['UID'] ?? '').trim();
    final start = _parseDate(props['DTSTART'], props['DTSTART@params']);
    final end = _parseDate(props['DTEND'], props['DTEND@params']);
    // 既没标题也没时间的，导进来也没意义
    if (summary.isEmpty && start == null && end == null) return null;
    return IcalEvent(
      uid: uid,
      summary: summary,
      description: _unescape(props['DESCRIPTION'] ?? '').trim(),
      location: _unescape(props['LOCATION'] ?? '').trim(),
      start: start,
      end: end,
    );
  }

  /// 解析 iCal 时间：`20260914T133000` / `20260914T053000Z` / `20260914`（全天）
  static DateTime? _parseDate(String? value, String? params) {
    if (value == null) return null;
    final text = value.trim();
    if (text.isEmpty) return null;

    final isDateOnly = (params?.toUpperCase().contains('VALUE=DATE') ?? false) ||
        !text.contains('T');
    final match = RegExp(r'^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})?)?(Z)?$')
        .firstMatch(text);
    if (match == null) return null;
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    if (isDateOnly || match.group(4) == null) {
      // 全天事件：按当天 23:59 处理（与「只给日期」的待办语义一致）
      return DateTime(year, month, day, 23, 59);
    }
    final hour = int.parse(match.group(4)!);
    final minute = int.parse(match.group(5)!);
    final second = match.group(6) == null ? 0 : int.parse(match.group(6)!);
    final utc = match.group(7) == 'Z';
    final parsed = utc
        ? DateTime.utc(year, month, day, hour, minute, second)
        : DateTime(year, month, day, hour, minute, second);
    return utc ? parsed.toLocal() : parsed;
  }

  /// iCal 里的转义：`\,` `\;` `\\` `\n`
  static String _unescape(String value) {
    var out = value;
    out = out.replaceAll(r'\n', '\n');
    out = out.replaceAll(r'\N', '\n');
    out = out.replaceAll(r'\,', ',');
    out = out.replaceAll(r'\;', ';');
    out = out.replaceAll(r'\\', r'\');
    return out;
  }

  /// 稳定的本地 uid：同一个 iCal 事件重复导入会命中同一条
  static String localUidFor(IcalEvent event) {
    final seed = event.uid.isNotEmpty
        ? event.uid
        : '${event.summary}|${event.start?.toIso8601String() ?? ''}|'
            '${event.end?.toIso8601String() ?? ''}';
    return '$uidPrefix${seed.hashCode.toRadixString(16)}';
  }

  /// 一条 iCal 事件 → 一条待办
  static Task toTask(IcalEvent event) {
    final start = event.start;
    final end = event.end;
    final now = DateTime.now();

    TaskType type;
    DateTime? taskStart;
    DateTime? taskEnd;

    if (start != null && end != null && end.isAfter(start)) {
      // 有起止 → 活动
      type = TaskType.fixed;
      taskStart = start;
      taskEnd = end;
    } else if (start != null) {
      // 只有开始 → 提醒（单时刻）
      type = TaskType.remind;
      taskStart = start;
      taskEnd = start;
    } else if (end != null) {
      // 只有结束 → 截止
      type = TaskType.deadline;
      taskStart = end;
      taskEnd = end;
    } else {
      // 都没有 → 备忘（不提醒、不进日历）
      type = TaskType.memo;
      final today = DateTime(now.year, now.month, now.day, 23, 59);
      taskStart = today;
      taskEnd = today;
    }

    final task = Task(
      uid: localUidFor(event),
      summary: event.summary.isEmpty ? '（来自 iCal 的日程）' : event.summary,
      endTime: taskEnd,
      startTime: taskStart,
      repeatEndsTime: dateOnly(taskEnd),
      description: event.description,
      location: event.location,
      type: type,
      createdAt: now,
      updatedAt: now,
    );
    task.applyKind(type);
    // 提醒锚点：活动锚开始、截止/提醒锚自身时刻，提前量沿用设置
    if (type != TaskType.memo) {
      task.reminderEnabled = true;
      task.reminderTime = task.reminderTargetTime;
    }
    // 过去的事件也照常导入（用户可能想留着记录），但状态交给状态机判定
    task.forceRefreshStatus();
    return task;
  }

  /// 导入结果汇总（给界面显示）
  static IcalImportPlan plan(
    List<IcalEvent> events, {
    required Set<String> existingUids,
  }) {
    final tasks = <Task>[];
    final skipped = <String>[];
    final seen = <String>{};
    for (final event in events) {
      final uid = localUidFor(event);
      if (existingUids.contains(uid) || seen.contains(uid)) {
        skipped.add(event.summary.isEmpty ? '(无标题)' : event.summary);
        continue;
      }
      seen.add(uid);
      tasks.add(toTask(event));
    }
    return IcalImportPlan(tasks: tasks, skipped: skipped);
  }
}

/// 解析出来的一条 iCal 事件
class IcalEvent {
  final String uid;
  final String summary;
  final String description;
  final String location;
  final DateTime? start;
  final DateTime? end;

  const IcalEvent({
    required this.uid,
    required this.summary,
    required this.description,
    required this.location,
    this.start,
    this.end,
  });
}

/// 导入计划：哪些要新建、哪些因为已存在被跳过
class IcalImportPlan {
  final List<Task> tasks;
  final List<String> skipped;

  const IcalImportPlan({required this.tasks, required this.skipped});

  bool get isEmpty => tasks.isEmpty;

  /// 一句话摘要（给确认弹层用）
  String get summary {
    final parts = <String>[];
    if (tasks.isNotEmpty) parts.add('识别到 ${tasks.length} 条日程');
    if (skipped.isNotEmpty) parts.add('${skipped.length} 条已存在，将跳过');
    return parts.isEmpty ? '没有识别到可导入的日程' : parts.join('；');
  }
}
