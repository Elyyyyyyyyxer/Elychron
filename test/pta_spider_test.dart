import 'package:celechron/http/pta_spider.dart';
import 'package:celechron/mod/pta_homework.dart';
import 'package:celechron/model/todo.dart';
import 'package:flutter_test/flutter_test.dart';

/// PTA 作业读取（2026-10-01）。fixture 用的是**实测拿到的响应字段**
/// （见 docs/PTA_RECON.md：endAt / exam.endAt / organizationName / permission=47）。
void main() {
  // 一个没有 exam 的题目集（截止时间听自己的 endAt）
  final setWithoutExam = <String, dynamic>{
    'id': '1882327366916743000',
    'name': '程序设计与算法基础-第三次作业',
    'organizationName': '浙江大学',
    'type': 'EXERCISE',
    'status': 'PENDING',
    'startAt': '2026-09-30T07:26:00Z',
    'endAt': '2026-10-07T15:59:00Z',
  };
  // 一个有 exam 的题目集（截止时间听 exam.endAt）
  final setWithExam = <String, dynamic>{
    'id': '2105199020241440000',
    'name': '程序设计与算法基础-第二次作业',
    'organizationName': '浙江大学',
    'endAt': '2026-10-08T10:30:00Z',
  };

  group('JSON → 作业', () {
    test('有 exam 的用 exam.endAt，没有的用题目集自己的 endAt', () {
      final todos = PtaSpider.todosFrom(
        problemSets: <dynamic>[setWithoutExam, setWithExam],
        examsBySetId: <String, Map<String, dynamic>?>{
          '1882327366916743000': <String, dynamic>{
            'status': 'PENDING',
            'problemSet': setWithoutExam,
            'permission': <String, dynamic>{'permission': 47},
          },
          '2105199020241440000': <String, dynamic>{
            'status': 'PROCESSING',
            'exam': <String, dynamic>{
              'id': '2105199020241440768',
              'startAt': '2026-09-30T07:32:13Z',
              'endAt': '2026-10-09T15:59:00Z',
              'ended': false,
              'status': 'PROCESSING',
            },
            'problemSet': setWithExam,
          },
        },
      );

      expect(todos, hasLength(2));
      expect(todos[0].id, 'pta:1882327366916743000');
      expect(todos[0].course, '浙江大学');
      expect(todos[0].name, '程序设计与算法基础-第三次作业');
      expect(todos[0].endTime?.toUtc().toIso8601String(),
          '2026-10-07T15:59:00.000Z');
      // 有 exam 的时候以 exam 的截止时间为准
      expect(todos[1].id, 'pta:2105199020241440000:2105199020241440768');
      expect(todos[1].endTime?.toUtc().toIso8601String(),
          '2026-10-09T15:59:00.000Z');
    });

    test('时间是 UTC：15:59Z 换算成北京就是 23:59（不能差 8 小时）', () {
      final todos = PtaSpider.todosFrom(
        problemSets: <dynamic>[setWithoutExam],
        examsBySetId: <String, Map<String, dynamic>?>{},
      );
      final end = todos.single.endTime!;
      // 用 UTC+8 手动换算，断言与运行机器的时区无关
      final beijing = end.toUtc().add(const Duration(hours: 8));
      expect(beijing.hour, 23);
      expect(beijing.minute, 59);
      expect(beijing.day, 7);
    });

    test('没有截止时间的题目集不变成待办', () {
      final todos = PtaSpider.todosFrom(
        problemSets: <dynamic>[
          <String, dynamic>{'id': 'x', 'name': '没有时间的题集'}
        ],
        examsBySetId: <String, Map<String, dynamic>?>{},
      );
      expect(todos, isEmpty);
    });

    test('缺 id 的脏数据被跳过，不影响其它条目', () {
      final todos = PtaSpider.todosFrom(
        problemSets: <dynamic>[
          <String, dynamic>{'name': '没有 id'},
          setWithoutExam,
        ],
        examsBySetId: <String, Map<String, dynamic>?>{},
      );
      expect(todos, hasLength(1));
    });

    test('同样的输入永远得到同样的 id（否则每次刷新都会重复长待办）', () {
      List<Todo> run() => PtaSpider.todosFrom(
            problemSets: <dynamic>[setWithoutExam, setWithExam],
            examsBySetId: <String, Map<String, dynamic>?>{},
          );
      expect(run().map((todo) => todo.id).join(','),
          run().map((todo) => todo.id).join(','));
    });
  });

  group('并进 scholar.todos', () {
    Todo todo(String id) => Todo.fromJson(<String, dynamic>{
          'id': id,
          'title': id,
          'course_name': 'c',
          'end_time': '2026-10-07T15:59:00Z',
        });

    test('只换 pta: 前缀的条目，教务/学在浙大的原样保留', () {
      final current = <Todo>[todo('教务1'), todo('pta:old'), todo('学在浙大1')];
      final merged = PtaHomework.mergeTodos(current, <Todo>[todo('pta:new')]);
      expect(merged.map((t) => t.id).toList(),
          <String>['教务1', '学在浙大1', 'pta:new']);
    });

    test('PTA 拉不回来时（空列表）只把自己那几条去掉，别人的不动', () {
      final current = <Todo>[todo('教务1'), todo('pta:old')];
      expect(PtaHomework.mergeTodos(current, <Todo>[]).map((t) => t.id).toList(),
          <String>['教务1']);
    });
  });
}
