import 'package:celechron/model/class_reminder_rule.dart';
import 'package:flutter_test/flutter_test.dart';

/// 课前提醒的提前量算法。
///
/// 规则由用户口述，这里逐条钉住 —— 这类"看起来显然"的规则最容易在改动中被理解错，
/// 尤其是「空余时间大于课间算前面没课」和「饭点视作空课」这两条。
void main() {
  final rule = ClassReminderRule();

  DateTime at(int hour, int minute) => DateTime(2026, 9, 14, hour, minute);

  ClassSlot slot(int sh, int sm, int eh, int em) =>
      ClassSlot(at(sh, sm), at(eh, em));

  group('规则 1：前面没有课 → 提前 20 分钟', () {
    test('当天第一节课', () {
      final first = slot(8, 0, 8, 45);
      expect(rule.leadMinutesFor(first, [first]), 20);
    });

    test('空课表', () {
      expect(rule.leadMinutesFor(slot(10, 0, 10, 45), []), 20);
    });

    test('前面只有更晚的课（不算前面有课）', () {
      final target = slot(8, 0, 8, 45);
      final later = slot(10, 0, 10, 45);
      expect(rule.leadMinutesFor(target, [target, later]), 20);
    });
  });

  group('规则 2：前面有课且连着上 → 提前 10 分钟', () {
    test('小课间 5 分钟（08:45 下课 → 08:50 上课）', () {
      final first = slot(8, 0, 8, 45);
      final second = slot(8, 50, 9, 35);
      expect(rule.leadMinutesFor(second, [first, second]), 10);
    });

    test('连堂课的课间 15 分钟 → 仍算连着上', () {
      final first = slot(8, 0, 8, 45);
      final second = slot(9, 0, 9, 45); // 空 15 分钟
      expect(rule.leadMinutesFor(second, [first, second]), 10);
    });

    test('课间刚好 10 分钟（阈值内）', () {
      final first = slot(8, 0, 8, 45);
      final second = slot(8, 55, 9, 40);
      expect(rule.leadMinutesFor(second, [first, second]), 10);
    });

    test('三节连堂：第二节按"前面有课"算', () {
      final a = slot(8, 0, 8, 45);
      final b = slot(8, 50, 9, 35);
      final c = slot(10, 0, 10, 45); // 与 b 空 25 分钟 → 见规则 4
      expect(rule.leadMinutesFor(b, [a, b, c]), 10);
    });
  });

  group('规则 4：空余时间大于课间时长 → 视作前面没课（20 分钟）', () {
    test('大课间 25 分钟（09:35 下课 → 10:00 上课）', () {
      final first = slot(9, 0, 9, 35);
      final second = slot(10, 0, 10, 45);
      expect(rule.leadMinutesFor(second, [first, second]), 20);
    });

    test('空 16 分钟（刚好超过 15 分钟阈值）', () {
      final first = slot(8, 0, 8, 45);
      final second = slot(9, 1, 9, 46);
      expect(rule.leadMinutesFor(second, [first, second]), 20);
    });

    test('空 15 分钟（等于阈值，不算超过）', () {
      final first = slot(8, 0, 8, 45);
      final second = slot(9, 0, 9, 45);
      expect(rule.leadMinutesFor(second, [first, second]), 10);
    });

    test('取的是"最近的一节"：中间隔了两节课也算挨着最近的', () {
      final morning = slot(8, 0, 8, 45);
      final before = slot(9, 0, 9, 45);
      final target = slot(9, 55, 10, 40);
      // 与 before 空 10 分钟 → 10 分钟（morning 更远，不影响）
      expect(rule.leadMinutesFor(target, [morning, before, target]), 10);
    });
  });

  group('规则 3：午饭 / 晚饭视作一节空课', () {
    test('上午最后一节 → 下午第一节：隔着午饭 → 20 分钟', () {
      final morning = slot(11, 40, 12, 25); // 第 5 节
      final afternoon = slot(13, 25, 14, 10); // 第 6 节
      expect(rule.leadMinutesFor(afternoon, [morning, afternoon]), 20);
    });

    test('下午最后一节 → 晚上第一节：隔着晚饭 → 20 分钟', () {
      final afternoon = slot(17, 5, 17, 50); // 第 11 节
      final evening = slot(18, 50, 19, 35); // 第 12 节
      expect(rule.leadMinutesFor(evening, [afternoon, evening]), 20);
    });

    test('饭点判定本身：空档与饭点重叠才算', () {
      expect(rule.crossesMeal(at(12, 25), at(13, 25)), isTrue); // 午饭整段
      expect(rule.crossesMeal(at(12, 0), at(12, 20)), isTrue); // 落在午饭内
      expect(rule.crossesMeal(at(9, 0), at(9, 10)), isFalse); // 上午课间
      expect(rule.crossesMeal(at(13, 25), at(14, 10)), isFalse); // 午饭之后
    });

    test('即使两节"贴着"饭点边界，也不会误判成连着上', () {
      // 12:25 下课、12:30 上课（人为构造：空档落在饭点边界内）
      final before = slot(11, 40, 12, 26);
      final after = slot(12, 30, 13, 15);
      expect(rule.leadMinutesFor(after, [before, after]), 20);
    });
  });

  group('可配置：课间时长与饭点都能换（别写死）', () {
    test('课间时长改成 20 分钟后，空 15 分钟也算连着上', () {
      final custom = ClassReminderRule(breakMinutes: 20);
      final first = slot(8, 0, 8, 45);
      final second = slot(9, 0, 9, 45); // 空 15 分钟
      expect(custom.leadMinutesFor(second, [first, second]), 10);
    });

    test('去掉所有饭点后，午饭时段按普通空档算', () {
      final noMeals = ClassReminderRule(meals: []);
      final morning = slot(11, 40, 12, 25);
      final afternoon = slot(13, 25, 14, 10);
      // 空 60 分钟 > 课间 → 依然是 20 分钟（规则 4 已经覆盖）
      expect(noMeals.leadMinutesFor(afternoon, [morning, afternoon]), 20);
    });

    test('自定义饭点能被识别', () {
      final custom = ClassReminderRule(meals: [const TimeWindow(600, 660)]);
      expect(custom.crossesMeal(at(10, 5), at(10, 30)), isTrue);
      expect(custom.crossesMeal(at(12, 0), at(12, 30)), isFalse);
    });
  });

  group('previousClassBefore：找"最近的一节"', () {
    test('返回开始时间最晚的那一节', () {
      final a = slot(8, 0, 8, 45);
      final b = slot(10, 0, 10, 45);
      final target = slot(14, 0, 14, 45);
      final prev = rule.previousClassBefore(target, [a, b, target]);
      expect(prev?.start, b.start);
    });

    test('没有更早的课 → null', () {
      final target = slot(8, 0, 8, 45);
      expect(rule.previousClassBefore(target, [target]), isNull);
    });
  });
}
