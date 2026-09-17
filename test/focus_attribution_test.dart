import 'package:celechron/mod/course_mount_store.dart';
import 'package:celechron/model/period.dart';
import 'package:flutter_test/flutter_test.dart';

/// 专注归属到课程的口径（用户 2026-09-14 拍板：**按开始时间判定**、做成开关）。
///
/// 这是个纯函数，正好能把"边界情况"钉死， 而边界恰恰是这类规则最容易错的地方：
/// 两节课的接缝、考试/日程混进来、挂着待办但待办没选课程……
void main() {
  Period period({
    required String courseId,
    required DateTime start,
    required DateTime end,
    PeriodType type = PeriodType.classes,
  }) =>
      Period(
        uid: '$courseId-$start',
        fromUid: courseId,
        type: type,
        startTime: start,
        endTime: end,
      );

  final day = DateTime(2026, 9, 16);
  // 第 1、2 节 08:00-09:35，第 3、4 节 10:00-11:35
  final first = period(
    courseId: 'CS101',
    start: DateTime(2026, 9, 16, 8),
    end: DateTime(2026, 9, 16, 9, 35),
  );
  final second = period(
    courseId: 'MA102',
    start: DateTime(2026, 9, 16, 10),
    end: DateTime(2026, 9, 16, 11, 35),
  );
  final periods = [first, second];

  group('按开始时间归属', () {
    test('开始时间落在某节课里 → 算那门课', () {
      expect(
        courseIdForFocusStart(
          startedAt: DateTime(2026, 9, 16, 8, 30),
          periodsOfDay: periods,
        ),
        'CS101',
      );
      expect(
        courseIdForFocusStart(
          startedAt: DateTime(2026, 9, 16, 11, 0),
          periodsOfDay: periods,
        ),
        'MA102',
      );
    });

    test('正好从上课那一刻开始 → 算这门课（左闭）', () {
      expect(
        courseIdForFocusStart(
          startedAt: DateTime(2026, 9, 16, 10),
          periodsOfDay: periods,
        ),
        'MA102',
      );
    });

    test('正好在某一节的下课那一刻开始 → 算下一节，不算已经结束的那节（右开）', () {
      // 09:35 是第 1、2 节的结束时刻，此时开始专注不该记到 CS101 上；
      // 它落在两节之间的空档里 → 不归属。
      expect(
        courseIdForFocusStart(
          startedAt: DateTime(2026, 9, 16, 9, 35),
          periodsOfDay: periods,
        ),
        isNull,
      );
    });

    test('课间空档里开始 → 不归属（自由专注）', () {
      expect(
        courseIdForFocusStart(
          startedAt: DateTime(2026, 9, 16, 9, 50),
          periodsOfDay: periods,
        ),
        isNull,
      );
      expect(
        courseIdForFocusStart(
          startedAt: DateTime(2026, 9, 16, 22),
          periodsOfDay: periods,
        ),
        isNull,
      );
    });

    test('另一天的课时不会误命中（起止是绝对时间）', () {
      expect(
        courseIdForFocusStart(
          startedAt: DateTime(2026, 9, 17, 8, 30),
          periodsOfDay: periods,
        ),
        isNull,
      );
    });

    test('考试 / 日程 / 虚拟占位都不算课程', () {
      final mixed = [
        period(
          courseId: 'EXAM01',
          start: DateTime(2026, 9, 16, 8),
          end: DateTime(2026, 9, 16, 9, 35),
          type: PeriodType.test,
        ),
        period(
          courseId: 'EVENT01',
          start: DateTime(2026, 9, 16, 8),
          end: DateTime(2026, 9, 16, 9, 35),
          type: PeriodType.user,
        ),
        period(
          courseId: 'VIRTUAL01',
          start: DateTime(2026, 9, 16, 8),
          end: DateTime(2026, 9, 16, 9, 35),
          type: PeriodType.virtual,
        ),
      ];
      expect(
        courseIdForFocusStart(
          startedAt: DateTime(2026, 9, 16, 8, 30),
          periodsOfDay: mixed,
        ),
        isNull,
      );
    });

    test('课时没有课程代码（fromUid 为空）时跳过，不硬塞一个空串', () {
      final nameless = [
        period(
          courseId: '',
          start: DateTime(2026, 9, 16, 8),
          end: DateTime(2026, 9, 16, 9, 35),
        ),
      ];
      expect(
        courseIdForFocusStart(
          startedAt: DateTime(2026, 9, 16, 8, 30),
          periodsOfDay: nameless,
        ),
        isNull,
      );
    });
  });

  group('待办自带的课程归属优先', () {
    test('挂着课程的待办 → 不管什么时间都记那门课', () {
      expect(
        courseIdForFocusStart(
          startedAt: DateTime(2026, 9, 16, 22), // 半夜，压根没课
          periodsOfDay: periods,
          explicitCourseId: 'PHY300',
        ),
        'PHY300',
      );
    });

    test('待办的课程归属会覆盖"此刻正好在上另一门课"', () {
      expect(
        courseIdForFocusStart(
          startedAt: DateTime(2026, 9, 16, 8, 30), // 正在上 CS101
          periodsOfDay: periods,
          explicitCourseId: 'PHY300',
        ),
        'PHY300',
      );
    });

    test('待办没挂课程（空串 / null）→ 退回按开始时间判定', () {
      for (final explicit in <String?>[null, '']) {
        expect(
          courseIdForFocusStart(
            startedAt: DateTime(2026, 9, 16, 8, 30),
            periodsOfDay: periods,
            explicitCourseId: explicit,
          ),
          'CS101',
        );
      }
    });
  });

  test('没有任何课表数据 → 永远返回 null（不会崩）', () {
    expect(
      courseIdForFocusStart(
        startedAt: DateTime(2026, 9, 16, 8, 30),
        periodsOfDay: const <Period>[],
      ),
      isNull,
    );
  });

  test('同一天同一时段有两节课（冲堂）→ 取课表里的第一个，且只取一门', () {
    final conflict = [
      period(
        courseId: 'AAA111',
        start: DateTime(2026, 9, 16, 13, 25),
        end: DateTime(2026, 9, 16, 15, 50),
      ),
      period(
        courseId: 'BBB222',
        start: DateTime(2026, 9, 16, 13, 25),
        end: DateTime(2026, 9, 16, 15, 50),
      ),
    ];
    expect(
      courseIdForFocusStart(
        startedAt: DateTime(2026, 9, 16, 14),
        periodsOfDay: conflict,
      ),
      'AAA111',
    );
  });

  // day 变量只是为了让上面的时间读起来有上下文，这里显式用一下避免"未使用"告警
  test('基准日期就是 2026-09-16（防手滑改坏上面的用例）', () {
    expect(day.year, 2026);
    expect(day.month, 9);
  });
}
