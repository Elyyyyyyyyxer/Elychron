import 'package:celechron/model/focus_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// P3：专注状态机的边界测试。
///
/// 这段逻辑最容易错的地方是**段与段之间**：工作刚走完就进休息、
/// 锁屏两小时回来要一次算完、暂停期间不计时、休息设成 0 不能死循环。
/// 时间推进用墙上时钟，所以测试里直接给 `tick` 传时间点。
void main() {
  final t0 = DateTime(2026, 9, 12, 9, 0);

  FocusEngine make({int work = 60, int rest = 15}) =>
      FocusEngine(workMinutes: work, restMinutes: rest)..start(t0);

  group('开始与推进', () {
    test('开始后是工作段，剩余 = 工作时长', () {
      final e = make();
      expect(e.phase, FocusPhase.working);
      expect(e.remaining, const Duration(minutes: 60));
      expect(e.focused, Duration.zero);
      expect(e.rounds, 0);
      expect(e.progress, 0);
    });

    test('工作半小时：只算半小时，还在工作段', () {
      final e = make();
      e.tick(t0.add(const Duration(minutes: 30)));
      expect(e.phase, FocusPhase.working);
      expect(e.focused, const Duration(minutes: 30));
      expect(e.remaining, const Duration(minutes: 30));
      expect(e.progress, closeTo(0.5, 0.001));
    });

    test('走满一小时：自动进入休息，轮数 +1', () {
      final e = make();
      e.tick(t0.add(const Duration(minutes: 60)));
      expect(e.phase, FocusPhase.resting);
      expect(e.rounds, 1);
      expect(e.focused, const Duration(minutes: 60));
      expect(e.remaining, const Duration(minutes: 15));
    });

    test('休息走完：回到工作段，专注时长不再增长', () {
      final e = make();
      e.tick(t0.add(const Duration(minutes: 75)));
      expect(e.phase, FocusPhase.working);
      expect(e.rounds, 1);
      expect(e.focused, const Duration(minutes: 60));
      expect(e.rested, const Duration(minutes: 15));
      expect(e.remaining, const Duration(minutes: 60));
    });
  });

  group('跨段的长时间推进（锁屏回来）', () {
    test('一次 tick 跨过工作和休息：两段都正确结算', () {
      final e = make(work: 25, rest: 5);
      // 从 9:00 到 9:31 → 25 分钟工作 + 5 分钟休息 + 1 分钟新工作
      e.tick(t0.add(const Duration(minutes: 31)));
      expect(e.rounds, 1);
      expect(e.focused, const Duration(minutes: 26));
      expect(e.rested, const Duration(minutes: 5));
      expect(e.remaining, const Duration(minutes: 24));
    });

    test('锁屏两小时：轮数与时长都要对得上', () {
      final e = make(work: 60, rest: 15);
      // 两小时 = 75 分钟一轮 × 1 + 剩 45 分钟工作
      e.tick(t0.add(const Duration(hours: 2)));
      expect(e.rounds, 1);
      expect(e.focused, const Duration(minutes: 105));
      expect(e.rested, const Duration(minutes: 15));
      expect(e.phase, FocusPhase.working);
    });

    test('时钟回拨不会把时长算成负数', () {
      final e = make();
      e.tick(t0.add(const Duration(minutes: 10)));
      e.tick(t0); // 时间倒退
      expect(e.focused, const Duration(minutes: 10));
      expect(e.remaining, const Duration(minutes: 50));
    });
  });

  group('暂停 / 继续', () {
    test('暂停期间不计时', () {
      final e = make();
      e.tick(t0.add(const Duration(minutes: 10)));
      e.pause();
      expect(e.isPaused, isTrue);
      e.tick(t0.add(const Duration(minutes: 40))); // 暂停中过了半小时
      expect(e.focused, const Duration(minutes: 10));

      e.resume(t0.add(const Duration(minutes: 40)));
      e.tick(t0.add(const Duration(minutes: 50)));
      expect(e.focused, const Duration(minutes: 20));
    });

    test('休息时暂停，继续后回到休息段', () {
      final e = make();
      e.tick(t0.add(const Duration(minutes: 60))); // 进入休息
      e.pause();
      e.resume(t0.add(const Duration(minutes: 61)));
      e.tick(t0.add(const Duration(minutes: 66)));
      expect(e.phase, FocusPhase.resting);
      expect(e.rested, const Duration(minutes: 5));
    });
  });

  group('跳过休息 / 结束', () {
    test('跳过休息：立刻回到工作段，休息时长不增加', () {
      final e = make();
      e.tick(t0.add(const Duration(minutes: 60)));
      e.skipRest();
      expect(e.phase, FocusPhase.working);
      expect(e.rested, Duration.zero);
      expect(e.rounds, 1);
    });

    test('休息设成 0：不会死循环，直接接下一轮', () {
      final e = make(work: 30, rest: 0);
      e.tick(t0.add(const Duration(minutes: 30, seconds: 1)));
      expect(e.phase, FocusPhase.working);
      expect(e.rounds, 1);
      expect(e.rested, Duration.zero);
      expect(e.remaining.inSeconds, lessThan(30 * 60));
    });

    test('结束之后是 idle，不再计时', () {
      final e = make();
      e.tick(t0.add(const Duration(minutes: 20)));
      e.stop();
      expect(e.phase, FocusPhase.idle);
      e.tick(t0.add(const Duration(minutes: 30)));
      expect(e.focused, const Duration(minutes: 20));
    });
  });

  group('参数护栏', () {
    test('工作时长至少 1 分钟（避免除零与死循环）', () {
      final e = FocusEngine(workMinutes: 0, restMinutes: 5)..start(t0);
      expect(e.workMinutes, 1);
    });

    test('休息时长为负按 0 处理', () {
      final e = FocusEngine(workMinutes: 25, restMinutes: -3)..start(t0);
      expect(e.restMinutes, 0);
    });
  });
}
