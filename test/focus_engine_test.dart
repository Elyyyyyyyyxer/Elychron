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

  // ===== 真机反馈的那个 bug：刚满一小时显示成 1:60:00 =====
  group('focusClock：分钟必须对 3600 取模', () {
    test('整整一小时是 1:00:00，不是 1:60:00', () {
      expect(focusClock(const Duration(minutes: 60)), '1:00:00');
    });

    test('90 分钟是 1:30:00，不是 1:90:00', () {
      expect(focusClock(const Duration(minutes: 90)), '1:30:00');
    });

    test('59:58 / 59:59 这种边界', () {
      expect(focusClock(const Duration(seconds: 3598)), '59:58');
      expect(focusClock(const Duration(seconds: 3599)), '59:59');
      expect(focusClock(const Duration(seconds: 3600)), '1:00:00');
    });

    test('withHours：整段格式稳定，不到一小时也带小时位', () {
      // 工作 60 分钟时，倒计时从 1:00:00 走到 0:59:58 都不该突然变成 59:58
      expect(
          focusClock(const Duration(seconds: 3600), withHours: true), '1:00:00');
      expect(
          focusClock(const Duration(seconds: 3598), withHours: true), '0:59:58');
      expect(focusClock(const Duration(seconds: 59), withHours: true), '0:00:59');
      // 不带 withHours 时维持老行为
      expect(focusClock(const Duration(seconds: 3598)), '59:58');
    });

    test('秒数向上取整：定时器晚几十毫秒也不会「跳秒」', () {
      // 整秒不受影响
      expect(focusClock(const Duration(minutes: 59, seconds: 58)), '59:58');
      // 剩 59:58.7 → 59:59（截断会显示 59:58，看着像一次跳两秒）
      expect(
          focusClock(const Duration(minutes: 59, seconds: 58, milliseconds: 700)),
          '59:59');
    });

    test('一分钟以内与零', () {
      expect(focusClock(const Duration(seconds: 5)), '00:05');
      expect(focusClock(Duration.zero), '00:00');
    });

    test('负数当 0 处理（时钟异常也不显示负时长）', () {
      expect(focusClock(const Duration(seconds: -30)), '00:00');
    });

    test('两小时以上', () {
      expect(focusClock(const Duration(hours: 2, minutes: 5, seconds: 9)),
          '2:05:09');
    });
  });

  group('focusHuman：口语化时长', () {
    test('常见写法', () {
      expect(focusHuman(const Duration(minutes: 45)), '45 分');
      expect(focusHuman(const Duration(hours: 1)), '1 小时');
      expect(focusHuman(const Duration(minutes: 80)), '1 小时 20 分');
      expect(focusHuman(const Duration(seconds: 30)), '30 秒');
      expect(focusHuman(Duration.zero), '0 秒');
    });

    test('小时里的分钟同样要对 60 取模', () {
      expect(focusHuman(const Duration(minutes: 150)), '2 小时 30 分');
    });
  });
}
