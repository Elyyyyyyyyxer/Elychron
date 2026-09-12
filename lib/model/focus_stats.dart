import 'package:celechron/model/focus_session.dart';

/// 一天的专注合计（柱状图用）
class FocusDayTotal {
  final DateTime day;
  final Duration focused;
  final int rounds;

  const FocusDayTotal({
    required this.day,
    required this.focused,
    required this.rounds,
  });
}

/// 按「专注对象」聚合的合计（任务名 / 自由专注名）
class FocusLabelTotal {
  final String label;
  final String? taskUid;
  final Duration focused;
  final int sessions;

  const FocusLabelTotal({
    required this.label,
    required this.taskUid,
    required this.focused,
    required this.sessions,
  });
}

/// ===== P4：专注统计（纯函数，方便单测）=====
///
/// 口径：**按会话的开始时间归档**。跨午夜的会话整段算在开始的那一天
/// （每小时切一刀反而会让「昨天今天各半小时」这种数字看不懂）。
class FocusStats {
  FocusStats._();

  /// 只要专注时长为正的会话
  static List<FocusSession> _real(List<FocusSession> sessions) =>
      sessions.where((s) => s.focusedTime > Duration.zero).toList();

  /// 某个区间内的总专注时长（含起点、不含终点）
  static Duration totalBetween(
    List<FocusSession> sessions,
    DateTime from,
    DateTime to,
  ) {
    var total = Duration.zero;
    for (final s in _real(sessions)) {
      final at = s.startedAt;
      if (at.isBefore(from) || !at.isBefore(to)) continue;
      total += s.focusedTime;
    }
    return total;
  }

  static Duration total(List<FocusSession> sessions) {
    var total = Duration.zero;
    for (final s in _real(sessions)) {
      total += s.focusedTime;
    }
    return total;
  }

  static DateTime dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

  /// 本周（周一为一周之始）的零点
  static DateTime startOfWeek(DateTime now) {
    final today = dayOf(now);
    return today.subtract(Duration(days: today.weekday - 1));
  }

  static DateTime startOfMonth(DateTime now) => DateTime(now.year, now.month);

  static DateTime startOfToday(DateTime now) => dayOf(now);

  /// 从 [fromDay] 起连续 [days] 天的每日合计（没有记录的那天也会出现，值为 0）
  static List<FocusDayTotal> daily(
    List<FocusSession> sessions, {
    required DateTime fromDay,
    required int days,
  }) {
    final start = dayOf(fromDay);
    final result = <FocusDayTotal>[];
    for (var i = 0; i < days; i++) {
      final day = start.add(Duration(days: i));
      var focused = Duration.zero;
      var rounds = 0;
      for (final s in _real(sessions)) {
        if (dayOf(s.startedAt) != day) continue;
        focused += s.focusedTime;
        rounds += s.rounds;
      }
      result.add(FocusDayTotal(day: day, focused: focused, rounds: rounds));
    }
    return result;
  }

  /// 按专注对象聚合（任务名 / 自由专注名），时长从多到少。
  ///
  /// [from] 为 null 表示统计全部历史。
  static List<FocusLabelTotal> byLabel(
    List<FocusSession> sessions, {
    DateTime? from,
  }) {
    final buckets = <String, FocusLabelTotal>{};
    for (final s in _real(sessions)) {
      if (from != null && s.startedAt.isBefore(from)) continue;
      final key = s.taskUid ?? 'free:${s.displayName}';
      final existing = buckets[key];
      buckets[key] = FocusLabelTotal(
        label: s.displayName,
        taskUid: s.taskUid,
        focused: (existing?.focused ?? Duration.zero) + s.focusedTime,
        sessions: (existing?.sessions ?? 0) + 1,
      );
    }
    final list = buckets.values.toList()
      ..sort((a, b) => b.focused.compareTo(a.focused));
    return list;
  }

  /// 没有正常结束的会话数（崩溃留下的）—— 统计页用它提示一句
  static int interruptedCount(List<FocusSession> sessions) =>
      _real(sessions).where((s) => !s.completed).length;

  static int roundCount(List<FocusSession> sessions) {
    var rounds = 0;
    for (final s in _real(sessions)) {
      rounds += s.rounds;
    }
    return rounds;
  }

  /// 完整走完（用户主动结束）的会话占比，0..1；没有会话时返回 null。
  static double? completionRate(List<FocusSession> sessions) {
    final list = _real(sessions);
    if (list.isEmpty) return null;
    final done = list.where((s) => s.completed).length;
    return done / list.length;
  }

  /// 平均每轮专注时长（一轮 = 一个走完的工作段）。
  static Duration? averageRound(List<FocusSession> sessions) {
    final rounds = roundCount(sessions);
    if (rounds <= 0) return null;
    return Duration(seconds: total(sessions).inSeconds ~/ rounds);
  }

  /// 「未打标签」这一档的名字 —— 自由专注、以及关联待办没有标签的会话都归这里，
  /// 免得它们的时长在标签视图里凭空消失。
  static const String untaggedLabel = '未打标签';

  /// 按标签聚合。
  ///
  /// ⚠️ 口径：一条会话会**计入它关联待办的每一个标签**，
  /// 所以分项之和通常大于总时长（一条待办挂两个标签就贡献两次）——
  /// 界面上必须把这句话写出来，否则用户会以为数字算错了。
  ///
  /// [tagsOfTask] 是 taskUid → 标签列表；查不到的（自由专注）算「未打标签」。
  static List<FocusLabelTotal> byTag(
    List<FocusSession> sessions, {
    required Map<String, List<String>> tagsOfTask,
    DateTime? from,
  }) {
    final buckets = <String, FocusLabelTotal>{};
    void add(String label, Duration focused) {
      final existing = buckets[label];
      buckets[label] = FocusLabelTotal(
        label: label,
        taskUid: null,
        focused: (existing?.focused ?? Duration.zero) + focused,
        sessions: (existing?.sessions ?? 0) + 1,
      );
    }

    for (final s in _real(sessions)) {
      if (from != null && s.startedAt.isBefore(from)) continue;
      final uid = s.taskUid;
      final tags =
          uid == null ? const <String>[] : (tagsOfTask[uid] ?? const <String>[]);
      if (tags.isEmpty) {
        add(untaggedLabel, s.focusedTime);
        continue;
      }
      for (final tag in tags) {
        final name = tag.trim();
        add(name.isEmpty ? untaggedLabel : name, s.focusedTime);
      }
    }

    final list = buckets.values.toList()
      ..sort((a, b) => b.focused.compareTo(a.focused));
    return list;
  }
}
