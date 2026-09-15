import 'package:celechron/design/app_accent.dart';
import 'package:celechron/design/round_rectangle_card.dart';
import 'package:celechron/design/task_detail_nav.dart';
import 'package:celechron/model/period.dart';
import 'package:celechron/model/upcoming.dart';
import 'package:flutter/cupertino.dart';

/// 「接下来」视图：最近的一条大字号，后面几条小字。
///
/// 排序逻辑全在 `model/upcoming.dart`（有单测），这里只负责画。
/// 卡片统一用应用里的 [RoundRectangleCard]，与日程/待办页保持同一套观感。
///
/// **同时有好几件在进行中时**（上课 + 组会撞在一起是真实场景）：顶层只放一张
/// 大卡，其余的折叠成一叠小卡排在它下面，并写明「同时还有 N 个进行中」。
/// 默认顶层是**课程**（见 [defaultTopRunningIndex]）；点折叠里的任意一条
/// 可以把它换到顶层 —— 换上去以后原来那张会落回折叠堆里，所以点错了能点回来。
class UpcomingView extends StatefulWidget {
  /// 已经排好序的条目（见 `buildUpcoming`）
  final List<UpcomingItem> items;

  /// 点「去添加待办」时回调（空状态用）
  final VoidCallback? onAddTask;

  const UpcomingView({
    super.key,
    required this.items,
    this.onAddTask,
  });

  @override
  State<UpcomingView> createState() => _UpcomingViewState();
}

class _UpcomingViewState extends State<UpcomingView> {
  /// 用户点着换到顶层的那一条，按 [UpcomingItem.dedupeKey] 记。
  ///
  /// **不能按 index 记**：这一页每 20 秒会跟着心跳重算一次，条目会随着时间
  /// 进出列表，下标随时会变（按 index 记的话过一会儿就指到别人身上）。
  String? _pinnedKey;

  @override
  void didUpdateWidget(UpcomingView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 被置顶的那条**不再进行中**（课上完了 / 待办被删）→ 忘掉它。
    //
    // 必须按「还在不在进行中」而不是「还在不在列表里」判断：课程/日程的 uid
    // 是一整套复用的（同一门课每天都是同一个 uid），所以那条会一直在 7 天窗口里，
    // 按「在不在列表里」判断的话，置顶会一直留到下次它开课 —— 好几天后
    // 莫名其妙又冒到顶层去。
    final key = _pinnedKey;
    if (key == null) return;
    final now = DateTime.now();
    final stillRunning = widget.items
        .any((item) => item.dedupeKey == key && item.isRunningAt(now));
    if (!stillRunning) _pinnedKey = null;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return _empty(context);
    final now = DateTime.now();
    final layout = layoutUpcoming(widget.items, now, pinnedKey: _pinnedKey)!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 110),
      children: [
        _headCard(context, layout.head, now),
        if (layout.otherRunning.isNotEmpty)
          _runningStack(context, layout),
        if (layout.later.isNotEmpty) ...[
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.only(left: 10, bottom: 6),
            child: Text(
              '之后还有',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: CupertinoDynamicColor.resolve(
                    CupertinoColors.secondaryLabel, context),
              ),
            ),
          ),
          ...layout.later.map((item) => _row(context, item, now)),
        ],
      ],
    );
  }

  // -------------------------------------------------- 折叠起来的「其它进行中」

  /// 除顶层之外的进行中条目：像**一叠卡片**那样，在顶层卡下面露出几条边。
  ///
  /// 用户纠正过我第一版的做法：折叠的意思是"像一叠卡片一样重合起来"，
  /// **不是**把每条都并排列出来（他还专门画了张概念图，并强调概念图只是表达
  /// "一叠"这个意思，别照抄）。所以这里只画几条露出来的边、**不写字** ——
  /// 想知道到底是谁、想换谁到顶层，点这叠边会弹出列表（[_openRunningPicker]）。
  Widget _runningStack(BuildContext context, UpcomingLayout layout) {
    final others = layout.otherRunning;
    return GestureDetector(
      key: const ValueKey('running-stack'),
      behavior: HitTestBehavior.opaque,
      onTap: () => _openRunningPicker(layout),
      child: Padding(
        padding: const EdgeInsets.only(top: 7),
        child: Column(
          children: [
            for (var i = 0; i < others.length; i++)
              Padding(
                // 逐级内缩一点，才像"一叠"；缩太多会显得像无关的条
                padding: EdgeInsets.symmetric(horizontal: 9.0 * (i + 1)),
                child: _cardEdge(context, last: i == others.length - 1),
              ),
          ],
        ),
      ),
    );
  }

  /// 露出来的那条"卡边"：跟顶层大卡同色同阴影，只是很矮。
  Widget _cardEdge(BuildContext context, {required bool last}) {
    final brightness = CupertinoTheme.of(context).brightness ??
        MediaQuery.of(context).platformBrightness;
    final isDark = brightness == Brightness.dark;
    return Container(
      height: last ? 14 : 11,
      margin: const EdgeInsets.only(bottom: 3),
      decoration: BoxDecoration(
        color: isDark
            ? CupertinoDynamicColor.resolve(
                CupertinoColors.secondarySystemBackground, context)
            : CupertinoDynamicColor.resolve(CupertinoColors.white, context),
        borderRadius: BorderRadius.circular(8),
        boxShadow: isDark
            ? null
            : const [
                BoxShadow(
                  color: CupertinoColors.systemGrey5,
                  blurRadius: 8,
                  offset: Offset(0, 4),
                ),
              ],
      ),
    );
  }

  /// 点那叠卡边：列出全部进行中的条目，选一条置顶。
  ///
  /// 顶层那张大卡本身**不**走这里 —— 点它是"看这条的信息"（用户明确要求）。
  Future<void> _openRunningPicker(UpcomingLayout layout) async {
    final picked = await showCupertinoModalPopup<UpcomingItem>(
      context: context,
      builder: (BuildContext context) => _RunningPickerSheet(
        running: layout.running,
        topKey: layout.head.dedupeKey,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _pinnedKey = picked.dedupeKey);
  }

  // -------------------------------------------------------------- 空状态

  Widget _empty(BuildContext context) {
    final labelColor = CupertinoDynamicColor.resolve(
        CupertinoColors.secondaryLabel, context);
    final textColor =
        CupertinoTheme.of(context).textTheme.textStyle.color ??
            CupertinoColors.label;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🎉', style: TextStyle(fontSize: 46)),
            const SizedBox(height: 12),
            RoundRectangleCard(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
              child: Column(
                children: [
                  Text(
                    '接下来 7 天都很空',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '课程、考试和要提醒你的事都会出现在这里',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: labelColor),
                  ),
                  if (widget.onAddTask != null) ...[
                    const SizedBox(height: 14),
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 8),
                      color: CupertinoDynamicColor.resolve(
                          CupertinoColors.tertiarySystemFill, context),
                      onPressed: widget.onAddTask,
                      child: const Text('去添加待办',
                          style: TextStyle(fontSize: 14)),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------- 大字那一条

  Widget _headCard(BuildContext context, UpcomingItem item, DateTime now) {
    final labelColor = CupertinoDynamicColor.resolve(
        CupertinoColors.secondaryLabel, context);
    final textColor =
        CupertinoTheme.of(context).textTheme.textStyle.color ??
            CupertinoColors.label;
    final running = item.isRunningAt(now);
    final accent = running ? CupertinoColors.systemGreen : _accentOf(item.kind);

    return RoundRectangleCard(
      padding: const EdgeInsets.fromLTRB(0, 16, 18, 16),
      onTap: () => _open(context, item),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 左侧色条（与待办卡片同一套视觉语言）
          Container(
            width: 4,
            height: 96,
            margin: const EdgeInsets.only(left: 14, right: 14),
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (running)
                      Container(
                        width: 7,
                        height: 7,
                        margin: const EdgeInsets.only(right: 6),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: CupertinoColors.systemGreen,
                        ),
                      ),
                    Text(
                      upcomingCountdown(item, now),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color:
                            running ? CupertinoColors.systemGreen : accent,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _kindName(item.kind),
                      style: TextStyle(fontSize: 12, color: labelColor),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  item.title,
                  style: TextStyle(
                    fontSize: 28,
                    height: 1.18,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 8),
                _line(
                  CupertinoIcons.time,
                  '${upcomingWhen(item, now)}'
                  '${item.until != null ? ' – ${_hm(item.until!)}' : ''}',
                  textColor,
                  labelColor,
                  size: 14,
                ),
                if (item.location.isNotEmpty)
                  _line(CupertinoIcons.location, item.location, textColor,
                      labelColor,
                      size: 14),
                if (item.detail.isNotEmpty)
                  _line(CupertinoIcons.doc_text, item.detail, labelColor,
                      labelColor,
                      size: 13),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _line(
    IconData icon,
    String text,
    Color textColor,
    Color iconColor, {
    double size = 14,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: size - 1, color: iconColor),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: size, color: textColor),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------- 小字行

  Widget _row(BuildContext context, UpcomingItem item, DateTime now) {
    final labelColor = CupertinoDynamicColor.resolve(
        CupertinoColors.secondaryLabel, context);
    final textColor =
        CupertinoTheme.of(context).textTheme.textStyle.color ??
            CupertinoColors.label;
    final accent = _accentOf(item.kind);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: RoundRectangleCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        onTap: () => _open(context, item),
        child: Row(
          children: [
            // 标题前的小圆点（与待办列表里的标签点一致）
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(shape: BoxShape.circle, color: accent),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      upcomingWhen(item, now),
                      if (item.location.isNotEmpty) item.location,
                      if (upcomingCountdown(item, now) != '进行中')
                        upcomingCountdown(item, now),
                    ].join(' · '),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: labelColor),
                  ),
                ],
              ),
            ),
            Icon(CupertinoIcons.chevron_forward,
                size: 14,
                color: CupertinoDynamicColor.resolve(
                    CupertinoColors.tertiaryLabel, context)),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- 工具

  static String _hm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static Color _accentOf(UpcomingKind kind) => switch (kind) {
        UpcomingKind.course => AppAccent.primary,
        UpcomingKind.exam => CupertinoColors.systemRed,
        UpcomingKind.activity => CupertinoColors.systemPurple,
        UpcomingKind.deadline => CupertinoColors.systemOrange,
        UpcomingKind.remind => CupertinoColors.systemBlue,
      };

  static String _kindName(UpcomingKind kind) => switch (kind) {
        UpcomingKind.course => '课程',
        UpcomingKind.exam => '考试',
        UpcomingKind.activity => '日程',
        UpcomingKind.deadline => '截止',
        UpcomingKind.remind => '提醒',
      };

  /// 待办 → 详情页；课程/考试/日程 → 一张信息卡。
  ///
  /// 这里原来用的是 `CupertinoActionSheet`：message 堆时间/地点/教师，actions 里塞了
  /// **一条显示日期关系的项**（`chineseDayRelation`）——那行既与上面重复，算出来还可能是
  /// 空串，于是用户看到一块「莫名其妙的空白选项」，风格也和 App 其它弹层不一致。
  /// 现在改成与标签选择器、闹钟配色同一套观感：圆角顶、信息行带图标、粉色主按钮。
  static void _open(BuildContext context, UpcomingItem item) {
    final task = item.task;
    if (task != null) {
      openTaskDetail(context, task);
      return;
    }
    final period = item.period;
    if (period == null) return;
    showCupertinoModalPopup<void>(
      context: context,
      builder: (BuildContext context) => _PeriodSheet(period: period),
    );
  }
}

/// 课程 / 考试 / 日程的信息弹层（与 App 其它底部弹层同一套观感）
class _PeriodSheet extends StatelessWidget {
  final Period period;

  const _PeriodSheet({required this.period});

  @override
  Widget build(BuildContext context) {
    final labelColor = CupertinoDynamicColor.resolve(
        CupertinoColors.secondaryLabel, context);
    final textColor =
        CupertinoTheme.of(context).textTheme.textStyle.color ??
            CupertinoColors.label;
    final description = period.description.trim();

    return Container(
      decoration: BoxDecoration(
        color: CupertinoDynamicColor.resolve(
            CupertinoColors.systemBackground, context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                period.summary,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 14),
              _line(
                CupertinoIcons.time,
                period.friendlyTimeStartDayBased,
                textColor,
                labelColor,
              ),
              if (period.location.trim().isNotEmpty)
                _line(CupertinoIcons.location, period.location.trim(),
                    textColor, labelColor),
              if (description.isNotEmpty)
                _line(CupertinoIcons.doc_text, description, textColor,
                    labelColor),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: CupertinoButton(
                  // 与 App 主按钮一致的爱莉希雅粉（电话/其它主操作用的同一色）
                  color: AppAccent.primary,
                  borderRadius: BorderRadius.circular(22),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('知道了',
                      style:
                          TextStyle(color: CupertinoColors.white, fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 一行「图标 + 文字」，与「接下来」卡片里的信息行同一套写法
  Widget _line(
    IconData icon,
    String text,
    Color textColor,
    Color iconColor,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 15, color: iconColor),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 15, height: 1.35, color: textColor),
            ),
          ),
        ],
      ),
    );
  }
}

/// 点「那叠卡边」弹出来的列表：正在进行中的**全部**条目，选一条放到顶层。
///
/// 顶层那张会标一个勾，点它就等于不改。观感与 [_PeriodSheet] 一致
/// （圆角顶、系统背景、行间发丝线）。
class _RunningPickerSheet extends StatelessWidget {
  /// 全部进行中的条目（含当前顶层）
  final List<UpcomingItem> running;

  /// 当前顶层那条的 [UpcomingItem.dedupeKey]
  final String topKey;

  const _RunningPickerSheet({
    required this.running,
    required this.topKey,
  });

  @override
  Widget build(BuildContext context) {
    final labelColor = CupertinoDynamicColor.resolve(
        CupertinoColors.secondaryLabel, context);
    final textColor =
        CupertinoTheme.of(context).textTheme.textStyle.color ??
            CupertinoColors.label;
    final line = CupertinoDynamicColor.resolve(
        CupertinoColors.separator, context);

    return Container(
      decoration: BoxDecoration(
        color: CupertinoDynamicColor.resolve(
            CupertinoColors.systemBackground, context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '同时进行中',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '点一条把它放到顶层',
                    style: TextStyle(fontSize: 13, color: labelColor),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < running.length; i++) ...[
              if (i > 0)
                Container(height: 0.5, margin: const EdgeInsets.only(left: 52), color: line),
              _row(context, running[i], textColor, labelColor),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: SizedBox(
                width: double.infinity,
                child: CupertinoButton(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  color: CupertinoDynamicColor.resolve(
                      CupertinoColors.tertiarySystemFill, context),
                  borderRadius: BorderRadius.circular(22),
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('取消',
                      style: TextStyle(fontSize: 16, color: textColor)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    UpcomingItem item,
    Color textColor,
    Color labelColor,
  ) {
    final isTop = item.dedupeKey == topKey;
    final sub = [
      '进行中',
      if (item.location.isNotEmpty) item.location,
    ].join(' · ');

    return CupertinoButton(
      key: ValueKey('running-pick-${item.dedupeKey}'),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      // 用 CupertinoButton 是为了有原生的按压反馈；它对不齐也无所谓，
      // 传给 pop 的值才是关键。
      onPressed: () => Navigator.of(context).pop(item),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(right: 10),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: CupertinoColors.systemGreen,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sub,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: CupertinoColors.systemGreen,
                  ),
                ),
              ],
            ),
          ),
          if (isTop) ...[
            Text('当前',
                style: TextStyle(fontSize: 12, color: labelColor)),
            const SizedBox(width: 6),
            const Icon(CupertinoIcons.checkmark_alt,
                size: 16, color: CupertinoColors.systemGreen),
          ] else
            Icon(CupertinoIcons.arrow_up_to_line, size: 16, color: labelColor),
        ],
      ),
    );
  }
}
