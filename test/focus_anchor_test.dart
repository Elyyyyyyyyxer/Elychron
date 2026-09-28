import 'package:celechron/mod/focus_anchor.dart';
import 'package:flutter_test/flutter_test.dart';

/// 专注的锚点：**时长全部按时间推算**（用户 2026-09-21 要求）。
///
/// 只要「现在几点、这一段什么时候开始」是准的，那么页面有没有开着、
/// App 有没有被杀，算出来的时长都一样 —— 所以这里把推算逻辑当纯函数钉死。
void main() {
  final t0 = DateTime(2026, 9, 21, 9, 0);

  FocusAnchor anchor({
    FocusPhaseName phase = FocusPhaseName.working,
    Duration worked = Duration.zero,
    Duration rested = Duration.zero,
    int work = 60,
    int rest = 15,
  }) =>
      FocusAnchor(
        uid: 'u1',
        startedAt: t0,
        phase: phase,
        phaseSince: t0,
        workedBefore: worked,
        restedBefore: rested,
        workMinutes: work,
        restMinutes: rest,
      );

  test('进行中：时长 = 本段起点到现在的差', () {
    final a = anchor();
    expect(a.worked(t0.add(const Duration(minutes: 25))),
        const Duration(minutes: 25));
  });

  test('中断中：中断期间一点时长都不涨', () {
    final a = anchor(
        phase: FocusPhaseName.paused, worked: const Duration(minutes: 10));
    expect(a.worked(t0.add(const Duration(hours: 5))),
        const Duration(minutes: 10));
  });

  test('休息中：只涨休息不涨专注', () {
    final a = anchor(
        phase: FocusPhaseName.resting, worked: const Duration(minutes: 50));
    final now = t0.add(const Duration(minutes: 5));
    expect(a.rested(now), const Duration(minutes: 5));
    expect(a.worked(now), const Duration(minutes: 50));
  });

  test('切段结算进累计：不重复计也不丢', () {
    var a = anchor();
    final at = t0.add(const Duration(minutes: 30));
    a = a.switchingTo(FocusPhaseName.resting, at);
    expect(a.worked(at), const Duration(minutes: 30));
    final later = at.add(const Duration(minutes: 10));
    expect(a.worked(later), const Duration(minutes: 30));
    expect(a.rested(later), const Duration(minutes: 10));
    a = a.switchingTo(FocusPhaseName.working, later);
    final end = later.add(const Duration(minutes: 20));
    expect(a.worked(end), const Duration(minutes: 50));
    expect(a.rested(end), const Duration(minutes: 10));
  });

  test('被杀掉再回来结果一样（无需累加器，重算即可）', () {
    final a = anchor();
    expect(a.worked(t0.add(const Duration(minutes: 42))),
        const Duration(minutes: 42));
  });

  test('本段剩余与该不该切段（超时收敛到 0）', () {
    final a = anchor(work: 25);
    expect(a.currentSegmentRemaining(t0.add(const Duration(minutes: 5))),
        const Duration(minutes: 20));
    expect(a.segmentFinished(t0.add(const Duration(minutes: 25))), isTrue);
    expect(a.currentSegmentRemaining(t0.add(const Duration(hours: 3))),
        Duration.zero);
  });

  test('序列化往返（要存 optionsBox 扛重启）', () {
    final a = anchor(phase: FocusPhaseName.resting, rest: 20, work: 30);
    final back = FocusAnchor.fromJson(a.toJson());
    expect(back, isNotNull);
    expect(back!.uid, 'u1');
    expect(back.phase, FocusPhaseName.resting);
    expect(back.restMinutes, 20);
    expect(back.phaseSince, t0);
  });

  test('三种状态都有用户看得懂的说法', () {
    expect(FocusPhaseName.working.label, '进行中');
    expect(FocusPhaseName.resting.label, '休息中');
    expect(FocusPhaseName.paused.label, '中断中');
  });
}
