import 'package:celechron/design/app_accent.dart';
import 'package:celechron/database/database_helper.dart';
import 'package:celechron/model/focus_engine.dart';
import 'package:celechron/model/focus_session.dart';
import 'package:celechron/model/focus_stats.dart';
import 'package:celechron/model/task.dart';
import 'package:celechron/page/focus/focus_entry.dart';
import 'package:celechron/page/task/task_controller.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';

/// ===== P4：专注记录 / 统计页 =====
///
/// 回答「我的时间去哪了」：今日 / 本周 / 本月总时长、最近七天的柱子、
/// 按专注对象（任务名或自由专注的名字）的分布，以及每一次的记录明细。
///
/// 数据全部来自 `dbFocus`，口径见 [FocusStats]（按会话**开始时间**归档）。
class FocusStatsPage extends StatefulWidget {
  const FocusStatsPage({super.key});

  @override
  State<FocusStatsPage> createState() => _FocusStatsPageState();
}

class _FocusStatsPageState extends State<FocusStatsPage> {
  DatabaseHelper? get _db {
    if (!Get.isRegistered<DatabaseHelper>(tag: 'db')) return null;
    return Get.find<DatabaseHelper>(tag: 'db');
  }

  List<FocusSession> get _sessions => _db?.getFocusSessions() ?? const [];

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final sessions = _sessions;
    final todayStart = FocusStats.startOfToday(now);
    final weekStart = FocusStats.startOfWeek(now);
    final monthStart = FocusStats.startOfMonth(now);
    final tomorrow = todayStart.add(const Duration(days: 1));

    final today = FocusStats.totalBetween(sessions, todayStart, tomorrow);
    final week = FocusStats.totalBetween(sessions, weekStart, tomorrow);
    final month = FocusStats.totalBetween(sessions, monthStart, tomorrow);
    final all = FocusStats.total(sessions);

    final last7 = FocusStats.daily(sessions,
        fromDay: todayStart.subtract(const Duration(days: 6)), days: 7);
    final byTask = FocusStats.byLabel(sessions, from: monthStart);
    final byTag = FocusStats.byTag(sessions,
        tagsOfTask: _tagsOfTasks(), from: monthStart);
    final list = sessions.where((s) => s.focusedTime > Duration.zero).toList();

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      navigationBar: CupertinoNavigationBar(
        middle: const Text('专注记录'),
        border: null,
      ),
      child: SafeArea(
        child: sessions.isEmpty
            ? _empty(context)
            : ListView(
                padding: const EdgeInsets.only(top: 12, bottom: 40),
                children: [
                  _totals(context, today: today, week: week, month: month),
                  _habit(context, sessions),
                  _weekChart(context, last7),
                  if (byTask.isNotEmpty) _byTask(context, byTask),
                  if (byTag.isNotEmpty) _byTag(context, byTag),
                  _sessionList(context, list, all),
                ],
              ),
      ),
    );
  }

  /// 任务 uid → 标签，用来把专注记录按标签归类。
  ///
  /// 拿不到任务列表（极早期启动）就返回空表 —— 那样所有会话都会落进
  /// 「未打标签」，数字仍然对，只是没法按标签细分。
  Map<String, List<String>> _tagsOfTasks() {
    final result = <String, List<String>>{};
    try {
      final list = Get.find<RxList<Task>>(tag: 'taskList');
      for (final task in list) {
        result[task.uid] = List<String>.of(task.tags);
      }
    } catch (_) {}
    return result;
  }

  /// 习惯指标：完整走完占比 + 平均每轮时长 + 未正常结束次数
  Widget _habit(BuildContext context, List<FocusSession> sessions) {
    final rate = FocusStats.completionRate(sessions);
    final avg = FocusStats.averageRound(sessions);
    if (rate == null) return const SizedBox.shrink();
    final labelColor =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    final interrupted = FocusStats.interruptedCount(sessions);
    final rounds = FocusStats.roundCount(sessions);
    return _card(
      children: [
        Row(
          children: [
            _stat(context, '完整走完', '${(rate * 100).round()}%'),
            _stat(context, '平均每轮',
                avg == null ? '—' : focusHuman(avg)),
            _stat(context, '总轮数', '$rounds'),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          interrupted == 0
              ? '每一次专注都是主动结束的 ✓'
              : '有 $interrupted 次没有正常结束（App 被系统杀掉或中途退出），时长按最后记录结算',
          style: TextStyle(fontSize: 11, color: labelColor),
        ),
      ],
    );
  }

  Widget _stat(BuildContext context, String title, String value) {
    final textColor = CupertinoTheme.of(context).textTheme.textStyle.color;
    final labelColor =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: textColor,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          Text(title, style: TextStyle(fontSize: 11, color: labelColor)),
        ],
      ),
    );
  }

  /// 按标签分布（口径要写清楚：一条会话计入它的每个标签）
  Widget _byTag(BuildContext context, List<FocusLabelTotal> totals) {
    final labelColor =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    final textColor = CupertinoTheme.of(context).textTheme.textStyle.color;
    final shown = totals.take(6).toList();
    final max = shown.first.focused.inMinutes;
    final sum = totals.fold(Duration.zero, (a, b) => a + b.focused);

    return _card(
      children: [
        const Text('本月按标签',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(
          '一条待办挂多个标签时，这段专注会分别计入每个标签，'
          '所以下面加起来（${focusHuman(sum)}）可能大于实际总时长',
          style: TextStyle(fontSize: 11, color: labelColor),
        ),
        const SizedBox(height: 10),
        ...shown.map((item) {
          final ratio = max == 0 ? 0.0 : item.focused.inMinutes / max;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '#${item.label}',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14, color: textColor),
                      ),
                    ),
                    Text(
                      '${focusHuman(item.focused)} · ${item.sessions} 次',
                      style: TextStyle(fontSize: 13, color: labelColor),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Stack(
                  children: [
                    Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: CupertinoDynamicColor.resolve(
                            CupertinoColors.systemFill, context),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: ratio.clamp(0.02, 1.0),
                      child: Container(
                        height: 6,
                        decoration: BoxDecoration(
                          color: CupertinoColors.systemIndigo,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  // ------------------------------------------------------------------ 空态

  Widget _empty(BuildContext context) {
    final labelColor =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(CupertinoIcons.timer,
                size: 44, color: AppAccent.primary),
            const SizedBox(height: 14),
            const Text('还没有专注记录',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
              '在待办详情页点「开始专注」，或者到待办页右上角点计时器图标开一段自由专注。'
              '结束后这里就会有记录和统计。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: labelColor),
            ),
            const SizedBox(height: 20),
            CupertinoButton(
              color: AppAccent.primary,
              borderRadius: BorderRadius.circular(22),
              padding:
                  const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
              onPressed: () async {
                await startFreeFocus(context);
                if (mounted) setState(() {});
              },
              child: const Text('开始一次自由专注',
                  style: TextStyle(color: CupertinoColors.white)),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ 删除

  /// 长按一条记录 → 删掉它。
  ///
  /// 连带把这条记录占用的时长从任务的 `timeSpent` 里减掉 ——
  /// 否则「删了记录但待办上还挂着 40 分钟」，账对不上。
  Future<void> _confirmDelete(BuildContext context, FocusSession session) async {
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (BuildContext context) => CupertinoAlertDialog(
        title: const Text('删除这条记录？'),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            '${session.displayName} · ${focusHuman(session.focusedTime)}\n'
            '${session.taskUid != null ? '对应待办已累计的时长会一起减掉。' : ''}',
            style: const TextStyle(fontSize: 14),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('取消'),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('删除'),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final uid = session.taskUid;
    if (uid != null && session.focusedTime > Duration.zero) {
      try {
        final list = Get.find<RxList<Task>>(tag: 'taskList');
        for (final task in list) {
          if (task.uid != uid) continue;
          final left = task.timeSpent - session.focusedTime;
          task.timeSpent = left.isNegative ? Duration.zero : left;
          task.updatedAt = DateTime.now();
          break;
        }
        if (Get.isRegistered<TaskController>()) {
          final controller = Get.find<TaskController>();
          controller.updateDeadlineList();
          controller.taskList.refresh();
        }
      } catch (_) {
        // 任务列表不在也不影响删记录
      }
    }
    await _db?.deleteFocusSession(session.uid);
    if (mounted) setState(() {});
  }

  // ------------------------------------------------------------------ 汇总

  Widget _card({required List<Widget> children}) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: CupertinoDynamicColor.resolve(
              CupertinoColors.secondarySystemGroupedBackground, context),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      );

  Widget _totals(
    BuildContext context, {
    required Duration today,
    required Duration week,
    required Duration month,
  }) {
    final labelColor =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    return _card(
      children: [
        Row(
          children: [
            _bigStat(context, '今天', today),
            _bigStat(context, '本周', week),
            _bigStat(context, '本月', month),
          ],
        ),
        const SizedBox(height: 8),
        Text('本周从周一算起；跨午夜的会话整段算在开始的那天',
            style: TextStyle(fontSize: 11, color: labelColor)),
      ],
    );
  }

  Widget _bigStat(BuildContext context, String title, Duration value) {
    final textColor = CupertinoTheme.of(context).textTheme.textStyle.color;
    final labelColor =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    // 不到一分钟就显示秒，别写成「0 分钟」让人以为没记上
    final String big;
    final String sub;
    if (value.inSeconds <= 0) {
      big = '0';
      sub = '还没开始';
    } else if (value.inMinutes < 1) {
      big = '${value.inSeconds}';
      sub = '${value.inSeconds} 秒';
    } else if (value.inHours < 1) {
      big = '${value.inMinutes}';
      sub = '${value.inMinutes} 分钟';
    } else {
      big = '${value.inHours}';
      sub = '${value.inHours} 小时 ${value.inMinutes % 60} 分';
    }
    return Expanded(
      child: Column(
        children: [
          Text(title, style: TextStyle(fontSize: 13, color: labelColor)),
          const SizedBox(height: 4),
          Text(
            big,
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w600,
              color: textColor,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Text(
            sub,
            style: TextStyle(fontSize: 11, color: AppAccent.primary),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ 柱状图

  Widget _weekChart(BuildContext context, List<FocusDayTotal> days) {
    final labelColor =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    final maxMinutes = days
        .map((d) => d.focused.inMinutes)
        .fold<int>(0, (a, b) => a > b ? a : b);
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];

    return _card(
      children: [
        const Text('最近七天',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        SizedBox(
          height: 120,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: days.map((d) {
              final ratio = maxMinutes == 0
                  ? 0.0
                  : d.focused.inMinutes / maxMinutes;
              return Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (d.focused > Duration.zero)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Text(
                          // 不到一分钟显示秒，别写成 0m
                          d.focused.inMinutes < 1
                              ? '${d.focused.inSeconds}s'
                              : (d.focused.inMinutes >= 60
                                  ? '${(d.focused.inMinutes / 60).toStringAsFixed(1)}h'
                                  : '${d.focused.inMinutes}m'),
                          style: TextStyle(
                              fontSize: 10, color: labelColor),
                        ),
                      ),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 5),
                      height: 6 + 74 * ratio,
                      decoration: BoxDecoration(
                        color: d.focused > Duration.zero
                            ? AppAccent.primary
                            : CupertinoDynamicColor.resolve(
                                CupertinoColors.systemFill, context),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      weekdays[d.day.weekday - 1],
                      style: TextStyle(fontSize: 11, color: labelColor),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------ 分布

  Widget _byTask(
    BuildContext context,
    List<FocusLabelTotal> totals,
  ) {
    final labelColor =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    final textColor = CupertinoTheme.of(context).textTheme.textStyle.color;
    final shown = totals.take(6).toList();
    final max = shown.first.focused.inMinutes;

    return _card(
      children: [
        const Text('本月专注对象',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        ...shown.map((item) {
          final ratio = max == 0 ? 0.0 : item.focused.inMinutes / max;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14, color: textColor),
                      ),
                    ),
                    Text(
                      focusHuman(item.focused),
                      style: TextStyle(fontSize: 13, color: labelColor),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Stack(
                  children: [
                    Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: CupertinoDynamicColor.resolve(
                            CupertinoColors.systemFill, context),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: ratio.clamp(0.02, 1.0),
                      child: Container(
                        height: 6,
                        decoration: BoxDecoration(
                          color: AppAccent.primary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }),
        if (totals.length > shown.length)
          Text('……还有 ${totals.length - shown.length} 个对象，看下面的记录明细',
              style: TextStyle(fontSize: 11, color: labelColor)),
      ],
    );
  }

  // ------------------------------------------------------------------ 明细

  Widget _sessionList(
    BuildContext context,
    List<FocusSession> sessions,
    Duration all,
  ) {
    final labelColor =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    final textColor = CupertinoTheme.of(context).textTheme.textStyle.color;

    return _card(
      children: [
        Row(
          children: [
            const Text('每一次',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const Spacer(),
            Text('累计 ${focusHuman(all)}',
                style: TextStyle(fontSize: 12, color: labelColor)),
          ],
        ),
        const SizedBox(height: 6),
        ...sessions.take(60).map((s) {
          final started = s.startedAt;
          final hh = started.hour.toString().padLeft(2, '0');
          final mm = started.minute.toString().padLeft(2, '0');
          final meta = <String>[
            focusHuman(s.focusedTime),
            if (s.restedOrZero > Duration.zero) '休息 ${focusHuman(s.restTime)}',
            if (s.rounds > 0) '${s.rounds} 轮',
            if (!s.completed) '未正常结束',
          ];
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onLongPress: () => _confirmDelete(context, s),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 46,
                    child: Text('${started.month}-${started.day}',
                        style: TextStyle(fontSize: 12, color: labelColor)),
                  ),
                  SizedBox(
                    width: 42,
                    child: Text('$hh:$mm',
                        style: TextStyle(fontSize: 12, color: labelColor)),
                  ),
                  Expanded(
                    child: Text(
                      s.displayName,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, color: textColor),
                    ),
                  ),
                  Text(
                    meta.join(' · '),
                    style: TextStyle(fontSize: 12, color: labelColor),
                  ),
                ],
              ),
            ),
          );
        }),
        if (sessions.length > 60)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('只显示最近 60 次',
                style: TextStyle(fontSize: 11, color: labelColor)),
          ),
      ],
    );
  }
}

extension on FocusSession {
  /// 休息时长（老数据可能没有，这里兜底）
  Duration get restedOrZero => restTime;
}
