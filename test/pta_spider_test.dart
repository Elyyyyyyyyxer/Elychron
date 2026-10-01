import 'package:celechron/http/pta_spider.dart';
import 'package:celechron/mod/pta_homework.dart';
import 'package:celechron/model/todo.dart';
import 'package:flutter_test/flutter_test.dart';

/// PTA 作业读取（2026-10-01）。fixture 用的是**实测拿到的响应字段**
/// （见 docs/PTA_RECON.md：endAt / exam.endAt / organizationName / permission=47）。
void main() {
  // 没有 exam 的题目集（截止时间听自己的 endAt）
  final setWithoutExam = <String, dynamic>{
    'id': '1882327366916743000',
    'name': '程序设计与算法基础-第三次作业',
    'organizationName': '浙江大学',
    'type': 'EXERCISE',
    'status': 'PENDING',
    'startAt': '2026-09-30T07:26:00Z',
    'endAt': '2026-10-07T15:59:00Z',
  };
  // 有 exam 的题目集（截止时间听 exam.endAt）
  final setWithExam = <String, dynamic>{
    'id': '2105199020241440000',
    'name': '程序设计与算法基础-第二次作业',
    'organizationName': '浙江大学',
    'startAt': '2026-09-23T07:40:00Z',
    'endAt': '2026-10-08T10:30:00Z',
  };

  group('JSON → 作业', () {
    test('有 exam 的用 exam.endAt，没有的用题目集自己的 endAt', () {
      final parsed = PtaSpider.todosFrom(
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
              'startAt': '2026-09-23T07:40:00Z',
              'endAt': '2026-10-09T15:59:00Z',
              'ended': false,
              'status': 'PROCESSING',
            },
            'problemSet': setWithExam,
          },
        },
      );
      final todos = parsed.todos;

      expect(todos, hasLength(2));
      expect(parsed.skippedInClass, 0);
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

    test('当堂类型（起止在同一天）默认不当作业，并统计跳过条数', () {
      // 实测：当堂实验窗口 2.5 小时（10/8 16:00 → 18:30 北京），而且还没开启
      final inClass = <String, dynamic>{
        'id': '2104854056152141824',
        'name': '程序设计与算法基础-当堂实验',
        'organizationName': '浙江大学',
        'startAt': '2026-10-08T08:00:00Z', // 北京 16:00
        'endAt': '2026-10-08T10:30:00Z', // 北京 18:30
      };
      final parsed = PtaSpider.todosFrom(
        problemSets: <dynamic>[inClass, setWithoutExam],
        examsBySetId: <String, Map<String, dynamic>?>{},
      );
      expect(parsed.todos, hasLength(1));
      expect(parsed.todos.single.id, 'pta:1882327366916743000');
      expect(parsed.skippedInClass, 1);

      // 用户把开关打开时，它就该照常算作业
      final withInClass = PtaSpider.todosFrom(
        problemSets: <dynamic>[inClass, setWithoutExam],
        examsBySetId: <String, Map<String, dynamic>?>{},
        includeInClass: true,
      );
      expect(withInClass.todos, hasLength(2));
      expect(withInClass.skippedInClass, 0);
    });

    test('跨天的作业不会被误判成当堂类型', () {
      // 实测课后作业窗口 152~177 小时；这里用 6 天
      expect(
        PtaSpider.looksLikeInClass(
            DateTime.utc(2026, 9, 23, 7, 40), DateTime.utc(2026, 9, 29, 15, 59)),
        isFalse,
      );
      // 当堂：同一天
      expect(
        PtaSpider.looksLikeInClass(
            DateTime.utc(2026, 10, 8, 8, 0), DateTime.utc(2026, 10, 8, 10, 30)),
        isTrue,
      );
    });

    test('时间是 UTC：15:59Z 换算成北京就是 23:59（不能差 8 小时）', () {
      final todos = PtaSpider.todosFrom(
        problemSets: <dynamic>[setWithoutExam],
        examsBySetId: <String, Map<String, dynamic>?>{},
      ).todos;
      final end = todos.single.endTime!;
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
      ).todos;
      expect(todos, isEmpty);
    });

    test('缺 id 的脏数据被跳过，不影响其它条目', () {
      final todos = PtaSpider.todosFrom(
        problemSets: <dynamic>[
          <String, dynamic>{'name': '没有 id'},
          setWithoutExam,
        ],
        examsBySetId: <String, Map<String, dynamic>?>{},
      ).todos;
      expect(todos, hasLength(1));
    });

    test('同样的输入永远得到同样的 id（否则每次刷新都会重复长待办）', () {
      String run() => PtaSpider.todosFrom(
            problemSets: <dynamic>[setWithoutExam, setWithExam],
            examsBySetId: <String, Map<String, dynamic>?>{},
          ).todos.map((todo) => todo.id).join(',');
      expect(run(), run());
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
  group('截止时间的时区', () {
    test('解析后归一到本地时间，但时刻不变（差 8 小时的显示 bug 别再回来）', () {
      final todo = Todo.fromJson(<String, dynamic>{
        'id': 'x',
        'title': 't',
        'course_name': 'c',
        'end_time': '2026-10-07T15:59:00Z',
      });
      expect(todo.endTime, isNotNull);
      // 与运行机器的时区无关的两条断言
      expect(todo.endTime!.isUtc, isFalse, reason: '应当已经是本地时间');
      expect(todo.endTime!.toUtc().toIso8601String(),
          '2026-10-07T15:59:00.000Z');
    });
  });

}
