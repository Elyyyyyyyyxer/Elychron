import 'package:celechron/mod/ai/ai_task_draft.dart';
import 'package:celechron/model/task.dart';
import 'package:flutter_test/flutter_test.dart';

/// P2：AI 把「一段行程」拆成**带时间/地点**的步骤。
///
/// 关键是解析层不信任模型：时间越界、顺序颠倒、把时间写进标题、
/// 重复步骤，都要在这里被处理掉，而且每一次处理都要留一条 warning。
void main() {
  String iso(int dayOffset, int hour, int minute) {
    final d = DateTime.now().add(Duration(days: dayOffset));
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}T${two(hour)}:${two(minute)}:00';
  }

  /// 一条「明天的团建」：14:20 到 19:50
  Map<String, dynamic> teamBuild({
    required List<Object> steps,
  }) =>
      <String, dynamic>{
        'summary': '班级团建',
        'kind': '活动',
        'startTime': iso(1, 14, 20),
        'endTime': iso(1, 19, 50),
        'subtasks': steps,
      };

  group('结构化步骤：时间与地点落到字段上', () {
    test('每一步的 startTime / endTime / location / note 都解析出来', () {
      final draft = AiTaskDraft.fromJsonForTest(teamBuild(steps: [
        {
          'title': '龙湖西溪天街南出入口集合',
          'location': '龙湖西溪天街',
          'note': '带身份证',
          'startTime': iso(1, 14, 20),
        },
        {
          'title': '嗦歌KTV 唱歌',
          'location': '嗦歌KTV',
          'startTime': iso(1, 14, 30),
          'endTime': iso(1, 17, 30),
        },
        {
          'title': '探鱼吃饭',
          'location': '探鱼',
          'startTime': iso(1, 17, 50),
          'endTime': iso(1, 19, 50),
        },
      ]));

      expect(draft.kind, TaskType.fixed);
      expect(draft.subtasks.length, 3);
      final first = draft.subtasks.first;
      expect(first.title, '龙湖西溪天街南出入口集合');
      expect(first.location, '龙湖西溪天街');
      expect(first.note, '带身份证');
      expect(first.startTime, isNotNull);
      expect(first.endTime, isNull);
      expect(first.timeLabel.isNotEmpty, isTrue);

      final second = draft.subtasks[1];
      expect(second.hasTime, isTrue);
      expect(second.endTime!.difference(second.startTime!), const Duration(hours: 3));
    });

    test('applyTo 把时间/地点/注意事项都写进子待办', () {
      final draft = AiTaskDraft.fromJsonForTest(teamBuild(steps: [
        {
          'title': '探鱼吃饭',
          'location': '探鱼',
          'note': '17:45 南出入口集合',
          'startTime': iso(1, 17, 50),
          'endTime': iso(1, 19, 50),
        },
      ]));
      final task = Task(
        endTime: DateTime.now(),
        startTime: DateTime.now(),
        repeatEndsTime: DateTime.now(),
      );
      draft.applyTo(task);

      expect(task.subtasks.length, 1);
      final sub = task.subtasks.first;
      expect(sub.title, '探鱼吃饭');
      expect(sub.location, '探鱼');
      expect(sub.description, '17:45 南出入口集合');
      expect(sub.startTime, isNotNull);
      expect(sub.endTime, isNotNull);
      // 行程型判定：只要有一步带时间，整组就按时间轴显示
      expect(task.hasItinerary, isTrue);
      expect(task.nextItineraryStep?.title, '探鱼吃饭');
    });
  });

  group('解析层的强制校验', () {
    test('时间写进标题 → 抢救到时间字段里，标题只剩动作', () {
      final draft = AiTaskDraft.fromJsonForTest(teamBuild(steps: [
        {'title': '14:30-17:30 嗦歌KTV唱歌'},
        {'title': '17:50 探鱼吃饭', 'startTime': iso(1, 17, 50)},
      ]));
      // 时间被抢救出来之后按时间排序：14:30 的唱歌在前
      expect(draft.subtasks.map((s) => s.title).toList(),
          ['嗦歌KTV唱歌', '探鱼吃饭']);
      final sing = draft.subtasks.first;
      expect(sing.startTime, isNotNull);
      expect(sing.endTime, isNotNull);
      expect(sing.endTime!.hour, 17);
      expect(sing.endTime!.minute, 30);
      expect(draft.warnings.any((w) => w.contains('原本写在标题里')), isTrue);
    });

    test('结束时间不晚于开始时间 → 时间丢掉、标题保留、留一条 warning', () {
      final draft = AiTaskDraft.fromJsonForTest(teamBuild(steps: [
        {
          'title': '唱歌',
          'startTime': iso(1, 17, 30),
          'endTime': iso(1, 14, 30),
        },
      ]));
      expect(draft.subtasks.single.title, '唱歌');
      expect(draft.subtasks.single.hasTime, isFalse);
      expect(draft.warnings.any((w) => w.contains('不晚于开始时间')), isTrue);
    });

    test('步骤时间超出父任务范围 → 丢掉并留一条 warning', () {
      final draft = AiTaskDraft.fromJsonForTest(teamBuild(steps: [
        // 第二天才发生，不可能属于今晚这场团建
        {'title': '第二天再聚', 'startTime': iso(2, 12, 0)},
      ]));
      expect(draft.subtasks.single.hasTime, isFalse);
      expect(draft.warnings.any((w) => w.contains('超出了这条待办的范围')), isTrue);
    });

    test('结束时间越界但开始时间在范围内 → 只丢结束时间', () {
      final draft = AiTaskDraft.fromJsonForTest(teamBuild(steps: [
        {
          'title': '收尾',
          'startTime': iso(1, 19, 0),
          'endTime': iso(2, 2, 0),
        },
      ]));
      final step = draft.subtasks.single;
      expect(step.startTime, isNotNull);
      expect(step.endTime, isNull);
      expect(draft.warnings.any((w) => w.contains('丢掉了结束时间') || w.contains('超出了')), isTrue);
    });

    test('按时间排序，没时间的排最后', () {
      final draft = AiTaskDraft.fromJsonForTest(teamBuild(steps: [
        {'title': '没时间的一步'},
        {'title': '最后一步', 'startTime': iso(1, 17, 50)},
        {'title': '第一步', 'startTime': iso(1, 14, 20)},
      ]));
      expect(draft.subtasks.map((s) => s.title).toList(),
          ['第一步', '最后一步', '没时间的一步']);
    });

    test('重复标题去重，且不超过上限', () {
      final draft = AiTaskDraft.fromJsonForTest(teamBuild(steps: [
        {'title': '吃饭'},
        {'title': '吃饭'},
        {'title': '吃饭'},
      ]));
      expect(draft.subtasks.length, 1);
    });

    test('老格式（纯字符串数组）仍然读得进来', () {
      final draft = AiTaskDraft.fromJsonForTest(<String, dynamic>{
        'summary': '写实验报告',
        'kind': '截止',
        'endTime': iso(3, 23, 59),
        'subtasks': ['查文献', '写提纲', '写正文'],
      });
      expect(draft.subtasks.length, 3);
      expect(draft.subtasks.every((s) => !s.hasTime), isTrue);
      expect(draft.subtasks.first.title, '查文献');
    });

    test('交付型待办没有时间范围时，步骤时间不会因为「父范围」被误删', () {
      final draft = AiTaskDraft.fromJsonForTest(<String, dynamic>{
        'summary': '交实验报告',
        'kind': '截止',
        'endTime': iso(3, 23, 59),
        'subtasks': [
          {'title': '整理数据', 'startTime': iso(1, 10, 0)},
        ],
      });
      expect(draft.subtasks.single.hasTime, isTrue);
    });
  });

  group('AiStepDraft 自身', () {
    test('timeLabel：时段写成 14:30-17:30，单时刻只写 14:20', () {
      final span = AiStepDraft(
        title: '唱歌',
        startTime: DateTime(2026, 9, 12, 14, 30),
        endTime: DateTime(2026, 9, 12, 17, 30),
      );
      expect(span.timeLabel, '14:30-17:30');
      final moment = AiStepDraft(
        title: '集合',
        startTime: DateTime(2026, 9, 12, 14, 20),
      );
      expect(moment.timeLabel, '14:20');
      expect(AiStepDraft(title: '查文献').timeLabel, '');
    });

    test('withoutTime：预览里「全部不要时间」用', () {
      final step = AiStepDraft(
        title: '唱歌',
        note: '带身份证',
        location: '嗦歌KTV',
        startTime: DateTime(2026, 9, 12, 14, 30),
        endTime: DateTime(2026, 9, 12, 17, 30),
      );
      final plain = step.withoutTime();
      expect(plain.hasTime, isFalse);
      expect(plain.title, '唱歌');
      expect(plain.location, '嗦歌KTV');
      expect(plain.note, '带身份证');
    });
  });

  group('SubTask 行程型判定', () {
    test('有开始时间就是一段，进行中/已过去都能算出来', () {
      final now = DateTime.now();
      final sub = SubTask(
        title: '唱歌',
        startTime: now.subtract(const Duration(minutes: 10)),
        endTime: now.add(const Duration(minutes: 50)),
      );
      expect(sub.hasTime, isTrue);
      expect(sub.isSpan, isTrue);
      expect(sub.isOngoingAt(now), isTrue);
      expect(sub.isMissedAt(now), isFalse);
    });

    test('勾完的步骤不再高亮、也不再标红', () {
      final now = DateTime.now();
      final sub = SubTask(
        title: '唱歌',
        done: true,
        startTime: now.subtract(const Duration(hours: 2)),
        endTime: now.subtract(const Duration(hours: 1)),
      );
      expect(sub.isOngoingAt(now), isFalse);
      expect(sub.isMissedAt(now), isFalse);
      expect(sub.reminderAt(30), isNull);
    });

    test('提醒时间 = 开始时间 − 提前量；没设就用默认', () {
      final anchor = DateTime(2026, 9, 12, 14, 30);
      final sub = SubTask(title: '唱歌', startTime: anchor);
      expect(sub.reminderAt(30), DateTime(2026, 9, 12, 14, 0));
      final custom = SubTask(title: '唱歌', startTime: anchor, reminderMinutes: 120);
      expect(custom.reminderAt(30), DateTime(2026, 9, 12, 12, 30));
    });

    test('清单型步骤（没有时间）永远不提醒', () {
      expect(SubTask(title: '查文献').reminderAt(30), isNull);
      expect(SubTask(title: '查文献').hasTime, isFalse);
    });
  });

}
