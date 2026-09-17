import 'package:celechron/mod/focus_suspend.dart';
import 'package:celechron/model/focus_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// 暂停后离开，回来接着专注（2026-09-16 用户要求）里两块**纯逻辑**的测试：
///  1. «FocusEngine.restore»， 从存档里原样接回计时状态；
///  2. «SuspendedFocus» 的序列化， 它存在 optionsBox 里，读回来的可能是任何东西。
///
/// 为什么这两块值得单独测：接不回来 = 用户白专注一段（或者反过来多算），
/// 而脏数据读崩 = 专注首页直接打不开。都属于"再也不想遇到第二次"的那类。
void main() {
  final t0 = DateTime(2026, 9, 16, 20, 0, 0);

  group('FocusEngine.restore：从暂停后离开的存档里接回来', () {
    test('数值原样恢复，并且停在暂停态（不自己跑起来）', () {
      final engine = FocusEngine(workMinutes: 45, restMinutes: 10);
      engine.restore(
        now: t0,
        focused: const Duration(minutes: 20, seconds: 30),
        rested: const Duration(minutes: 5),
        rounds: 2,
        remaining: const Duration(minutes: 12, seconds: 15),
        wasResting: false,
      );

      expect(engine.isPaused, isTrue);
      expect(engine.focused, const Duration(minutes: 20, seconds: 30));
      expect(engine.rested, const Duration(minutes: 5));
      expect(engine.rounds, 2);
      expect(engine.remaining, const Duration(minutes: 12, seconds: 15));
      expect(engine.pausedFromResting, isFalse);
    });

    test('暂停前是休息记得住：继续后走的是休息段，只加休息时长', () {
      final engine = FocusEngine(workMinutes: 45, restMinutes: 10);
      engine.restore(
        now: t0,
        focused: const Duration(minutes: 30),
        rested: Duration.zero,
        rounds: 1,
        remaining: const Duration(minutes: 4),
        wasResting: true,
      );
      expect(engine.pausedFromResting, isTrue);

      engine.resume(t0);
      expect(engine.isResting, isTrue);
      engine.tick(t0.add(const Duration(minutes: 1)));

      expect(engine.rested, const Duration(minutes: 1));
      // 休息段不该动专注时长
      expect(engine.focused, const Duration(minutes: 30));
      expect(engine.remaining, const Duration(minutes: 3));
    });

    test('继续之后接着倒数：暂停期间流逝的时间**不算**进去', () {
      final engine = FocusEngine(workMinutes: 45, restMinutes: 10);
      engine.restore(
        now: t0,
        focused: const Duration(minutes: 10),
        rested: Duration.zero,
        rounds: 0,
        remaining: const Duration(minutes: 35),
        wasResting: false,
      );
      // 用户走开一小时，回来点继续，又专注了 2 分钟
      final back = t0.add(const Duration(hours: 1));
      engine.resume(back);
      engine.tick(back.add(const Duration(minutes: 2)));

      expect(engine.focused, const Duration(minutes: 12));
      expect(engine.remaining, const Duration(minutes: 33));
    });

    test('脏数据（负数）被夹到 0，不抛也不产生负时长', () {
      final engine = FocusEngine(workMinutes: 45, restMinutes: 10);
      engine.restore(
        now: t0,
        focused: const Duration(minutes: -5),
        rested: const Duration(minutes: -1),
        rounds: -3,
        remaining: const Duration(minutes: -9),
        wasResting: false,
      );
      expect(engine.focused, Duration.zero);
      expect(engine.rested, Duration.zero);
      expect(engine.rounds, 0);
      expect(engine.remaining, Duration.zero);
    });
  });

  group('SuspendedFocus：存档的读写', () {
    test('写出去再读回来，四个字段都在', () {
      final at = DateTime(2026, 9, 16, 21, 30);
      final value = SuspendedFocus(
        uid: 'abc-123',
        remaining: const Duration(minutes: 7, seconds: 42),
        wasResting: true,
        at: at,
      );

      final back = SuspendedFocus.fromMap(value.toMap())!;
      expect(back.uid, 'abc-123');
      expect(back.remaining, const Duration(minutes: 7, seconds: 42));
      expect(back.wasResting, isTrue);
      expect(back.at, at);
    });

    test('读不出来的一律当没有暂停中的专注，绝不抛', () {
      expect(SuspendedFocus.fromMap(null), isNull);
      expect(SuspendedFocus.fromMap('nonsense'), isNull);
      expect(SuspendedFocus.fromMap(<String, dynamic>{}), isNull);
      expect(SuspendedFocus.fromMap({'uid': 42}), isNull);
      expect(SuspendedFocus.fromMap({'uid': ''}), isNull);
    });

    test('缺字段 / 类型不对时用安全默认值', () {
      final back = SuspendedFocus.fromMap(<String, dynamic>{'uid': 'x'})!;
      expect(back.uid, 'x');
      expect(back.remaining, Duration.zero);
      expect(back.wasResting, isFalse);
      // at 缺失时用"现在"，免得首页显示成 1970 年
      expect(back.at.difference(DateTime.now()).inSeconds.abs(), lessThan(5));
    });

    test('负数剩余时间被夹到 0', () {
      final back = SuspendedFocus.fromMap(<String, dynamic>{
        'uid': 'x',
        'remainingSeconds': -30,
        'wasResting': 'yes', // 不是 bool → 当作 false
        'at': -1, // 非法时间戳 → 当作"现在"
      })!;
      expect(back.remaining, Duration.zero);
      expect(back.wasResting, isFalse);
      expect(back.at.year, greaterThanOrEqualTo(2026));
    });
  });
}
