import 'package:celechron/mod/class_half_rule.dart';
import 'package:flutter_test/flutter_test.dart';

/// 自定义周次属于哪一半学期的判定。
///
/// 锁的是一个真实 bug：只有冬学期的研究生课（周次 `1-8周`）被排到了秋天，
/// 因为原代码只看周次数字、把第 1-8 周一律当上半学期。
void main() {
  group('单半学期 + 周次 ≤ 8 → 按它自己那一半', () {
    test('只有冬学期的课（周次 1-8）→ 下半学期', () {
      expect(
        ClassHalfRule.baseHalfIndex(
          firstHalf: false,
          secondHalf: true,
          weeks: [1, 2, 3, 4, 5, 6, 7, 8],
        ),
        ClassHalfRule.secondHalfIndex,
      );
    });

    test('只有秋学期的课（周次 1-8）→ 上半学期', () {
      expect(
        ClassHalfRule.baseHalfIndex(
          firstHalf: true,
          secondHalf: false,
          weeks: [1, 3, 5, 7],
        ),
        ClassHalfRule.firstHalfIndex,
      );
    });

    test('只有冬学期、单周上课（周次 1,3,5,7）', () {
      expect(
        ClassHalfRule.baseHalfIndex(
          firstHalf: false,
          secondHalf: true,
          weeks: [1, 3, 5, 7],
        ),
        ClassHalfRule.secondHalfIndex,
      );
    });
  });

  group('维持原样（不要修坏本来正确的排课）', () {
    test('跨两半的长学期课 → null（按全局周次解释）', () {
      expect(
        ClassHalfRule.baseHalfIndex(
          firstHalf: true,
          secondHalf: true,
          weeks: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
        ),
        isNull,
      );
    });

    test('周次里出现 ≥ 9（全局编号）→ null', () {
      expect(
        ClassHalfRule.baseHalfIndex(
          firstHalf: false,
          secondHalf: true,
          weeks: [9, 10, 11, 12],
        ),
        isNull,
      );
    });

    test('两半都没标（异常数据）→ null', () {
      expect(
        ClassHalfRule.baseHalfIndex(
          firstHalf: false,
          secondHalf: false,
          weeks: [1, 2, 3],
        ),
        isNull,
      );
    });

    test('没有周次 → null', () {
      expect(
        ClassHalfRule.baseHalfIndex(
          firstHalf: false,
          secondHalf: true,
          weeks: [],
        ),
        isNull,
      );
    });
  });

  group('周次 → 半学期下标', () {
    test('有基准时一律用基准（冬课的 1-8 周都落在下半学期）', () {
      for (final week in [1, 2, 3, 8]) {
        expect(
          ClassHalfRule.halfIndexForWeek(week,
              baseHalfIndex: ClassHalfRule.secondHalfIndex),
          ClassHalfRule.secondHalfIndex,
        );
      }
    });

    test('没有基准时沿用原公式：1-8 周上半学期、9-16 周下半学期', () {
      expect(ClassHalfRule.halfIndexForWeek(1), 0);
      expect(ClassHalfRule.halfIndexForWeek(8), 0);
      expect(ClassHalfRule.halfIndexForWeek(9), 1);
      expect(ClassHalfRule.halfIndexForWeek(16), 1);
    });
  });
}
