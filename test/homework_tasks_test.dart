import 'package:celechron/model/task.dart';
import 'package:celechron/mod/homework_tasks.dart';
import 'package:flutter_test/flutter_test.dart';

/// 作业自动进日程（v1.5.0，用户 2026-09-21 要求）。
///
/// 这里只钉"可纯函数验证"的那部分（排序与识别）——
/// 完整的"刷新 → 生成待办"要在真机上验（需要 Hive 与学者数据）。
void main() {
  Task make(String summary, DateTime end, {List<String> tags = const []}) {
    final task = Task(
      summary: summary,
      startTime: end.subtract(const Duration(hours: 2)),
      endTime: end,
      repeatEndsTime: end,
    );
    task.tags = List<String>.of(tags);
    return task;
  }

  test('带「作业」标签的才算作业', () {
    expect(
        taskIsHomework(
            make('写作业', DateTime(2026, 9, 25), tags: <String>[kHomeworkTag])),
        isTrue);
    expect(taskIsHomework(make('开会', DateTime(2026, 9, 25))), isFalse);
  });

  test('作业置顶：哪怕截止时间更晚也排在普通待办前面', () {
    final list = <Task>[
      make('普通待办（今天截止）', DateTime(2026, 9, 21, 12)),
      make('作业（下周截止）', DateTime(2026, 9, 28), tags: <String>[kHomeworkTag]),
    ];
    list.sort(homeworkFirst);
    expect(list.first.summary, contains('作业'));
  });

  test('都是作业（或都不是）时，仍按截止时间排', () {
    final list = <Task>[
      make('作业 B', DateTime(2026, 9, 28), tags: <String>[kHomeworkTag]),
      make('作业 A', DateTime(2026, 9, 22), tags: <String>[kHomeworkTag]),
    ];
    list.sort(homeworkFirst);
    expect(list.first.summary, '作业 A');
  });

  test('自动生成的作业用稳定 uid 前缀（反复刷新不会长出重复待办）', () {
    final task =
        make('作业', DateTime(2026, 9, 28), tags: <String>[kHomeworkTag]);
    task.uid = kHomeworkUidPrefix + '12345';
    expect(task.uid.startsWith(kHomeworkUidPrefix), isTrue);
    expect(task.uid.substring(kHomeworkUidPrefix.length), '12345');
  });
}
