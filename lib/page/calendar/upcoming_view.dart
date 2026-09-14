import 'package:celechron/design/round_rectangle_card.dart';
import 'package:celechron/design/bold_markdown_text.dart';
import 'package:celechron/design/task_detail_nav.dart';
import 'package:celechron/model/upcoming.dart';
import 'package:celechron/utils/time_helper.dart';
import 'package:flutter/cupertino.dart';

/// 「接下来」视图：最近的一条大字号，后面几条小字。
///
/// 排序逻辑全在 `model/upcoming.dart`（有单测），这里只负责画。
/// 卡片统一用应用里的 [RoundRectangleCard]，与日程/待办页保持同一套观感。
class UpcomingView extends StatelessWidget {
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
  Widget build(BuildContext context) {
    if (items.isEmpty) return _empty(context);
    final now = DateTime.now();
    final head = items.first;
    final rest = items.skip(1).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 110),
      children: [
        _headCard(context, head, now),
        if (rest.isNotEmpty) ...[
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
          ...rest.map((item) => _row(context, item, now)),
        ],
      ],
    );
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
                  if (onAddTask != null) ...[
                    const SizedBox(height: 14),
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 8),
                      color: CupertinoDynamicColor.resolve(
                          CupertinoColors.tertiarySystemFill, context),
                      onPressed: onAddTask,
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
                BoldMarkdownText(
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
            child: BoldMarkdownText(
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
                  BoldMarkdownText(
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
        UpcomingKind.course => const Color(0xFFFF699A),
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

  /// 待办 → 详情页；课程/考试/日程 → 用一个信息卡展示（含完整备注）
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
      builder: (BuildContext context) => CupertinoActionSheet(
        title: BoldMarkdownText(period.summary),
        message: BoldMarkdownText(
          [
            period.friendlyTimeStartDayBased,
            if (period.location.trim().isNotEmpty) period.location.trim(),
            if (period.description.trim().isNotEmpty) '',
            if (period.description.trim().isNotEmpty) period.description.trim(),
          ].join('\n'),
        ),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              TimeHelper.chineseDayRelation(period.startTime),
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('知道了'),
        ),
      ),
    );
  }
}
