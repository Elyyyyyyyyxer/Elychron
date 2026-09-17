import 'package:celechron/design/round_rectangle_card.dart';
import 'package:celechron/design/sub_title.dart';
import 'package:celechron/database/database_helper.dart';
import 'package:celechron/model/focus_session.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';

/// 课程页的「专注」区块：**这门课一共专注了多久、最近几次是什么时候**。
///
/// ## 为什么要加它（用户 2026-09-17）
///
/// 用户报「当现在有课的时候，自由专注不会自动计入当前课程？」——
/// 真机实测下来归属其实是**好的**（在一节 16:15–17:50 的课里开自由专注，
/// 结束后确实算到了那门课），问题出在**看不见**：
///
/// - 专注页当时一声不吭，不告诉你这次算到了哪门课（现在会写了）；
/// - 专注记录列表里也只有名字和时长，没有课程（现在也带上了）；
/// - 而课程页本身**完全没有专注的影子** —— 用户点进"当前这门课"，
///   自然觉得"根本没计入"。
///
/// 所以这个区块就是把归属**落到课程这一侧**：这门课我一共专注了多少、
/// 最近几次是哪天。数据直接从 dbFocus 里按 «FocusSession.courseId» 查，
/// 不额外存冗余（口径见 «docs/BACKLOG.md» #24）。
class CourseFocusSection extends StatelessWidget {
  const CourseFocusSection({super.key, required this.courseId});

  final String courseId;

  /// 这门课的全部专注会话（新的在前）；没注册数据库就返回空表。
  List<FocusSession> _sessions() {
    if (!Get.isRegistered<DatabaseHelper>(tag: 'db')) return const [];
    if (courseId.isEmpty) return const [];
    return Get.find<DatabaseHelper>(tag: 'db')
        .getFocusSessions()
        .where((s) => s.courseId == courseId && s.focusedTime > Duration.zero)
        .toList();
  }

  /// 「1 小时 20 分」这种口语化时长（与专注页同一套写法）
  String _human(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes % 60;
    if (hours > 0) return minutes > 0 ? '$hours 小时 $minutes 分' : '$hours 小时';
    if (minutes > 0) return '$minutes 分';
    return '${d.inSeconds} 秒';
  }

  @override
  Widget build(BuildContext context) {
    final labelColor =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    final textColor = CupertinoTheme.of(context).textTheme.textStyle.color;
    final sessions = _sessions();
    final total = sessions.fold<Duration>(
        Duration.zero, (acc, s) => acc + s.focusedTime);

    return Column(
      children: [
        SubSubtitleRow(subtitle: '专注'),
        RoundRectangleCard(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (sessions.isEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      '这门课还没有专注记录。\n'
                      '专注自动计入课程是开着的：上课时段里开始的自由专注，'
                      '结束后会自动算到这门课上。',
                      style: TextStyle(fontSize: 13, color: labelColor),
                    ),
                  ),
                )
              else ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '一共专注 ${_human(total)}',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: textColor),
                      ),
                    ),
                    Text('${sessions.length} 次',
                        style: TextStyle(fontSize: 13, color: labelColor)),
                  ],
                ),
                const SizedBox(height: 8),
                for (final session in sessions.take(5))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${session.startedAt.month}-${session.startedAt.day} '
                            '${session.startedAt.hour.toString().padLeft(2, '0')}:'
                            '${session.startedAt.minute.toString().padLeft(2, '0')}',
                            style: TextStyle(fontSize: 13, color: labelColor),
                          ),
                        ),
                        Text(
                          _human(session.focusedTime),
                          style: TextStyle(fontSize: 13, color: textColor),
                        ),
                      ],
                    ),
                  ),
                if (sessions.length > 5)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('（只列最近 5 次）',
                        style: TextStyle(fontSize: 11.5, color: labelColor)),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
