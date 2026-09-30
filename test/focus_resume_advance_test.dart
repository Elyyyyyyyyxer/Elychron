import 'package:celechron/mod/focus_anchor.dart';
import 'package:flutter_test/flutter_test.dart';

/// 「杀后台回来，现在该是什么状态」这套推算（2026-09-30）。
///
/// 用户原话：「杀后台之前处于什么状态做好记录，回来后读取时间进行比较，
/// 确认现在应该处于什么状态后直接静默继续」。
/// 之前的实现把"被杀"当成"暂停后离开"：先弹卡片问用户，而且离开期间的时长
/// 再也不计入 —— 用户丢的就是那几个小时。
void main() {
  FocusAnchor anchor({
    required FocusPhaseName phase,
    required DateTime phaseSince,
    Duration worked = Duration.zero,
    Duration rested = Duration.zero,
    int workMinutes = 45,
    int restMinutes = 5,
  }) =>
      FocusAnchor(
        uid: 'u1',
        startedAt: phaseSince,
        phase: phase,
        phaseSince: phaseSince,
        workedBefore: worked,
        restedBefore: rested,
        workMinutes: workMinutes,
        restMinutes: restMinutes,
      );

  final base = DateTime(2026, 9, 30, 20, 0);

  test('工作段还没走完 → 不切段，专注时长跟着现在涨', () {
    final a = anchor(phase: FocusPhaseName.working, phaseSince: base);
    final now = base.add(const Duration(minutes: 30));
    final r = advanceFocusAnchor(a, now);
    expect(r.phase, FocusPhaseName.working);
    expect(r.worked(now), const Duration(minutes: 30));
    expect(r.rested(now), Duration.zero);
  });

  test('工作段走完了 → 已经在休息段里（自动切段）', () {
    final a = anchor(phase: FocusPhaseName.working, phaseSince: base);
    // 45 分钟工作段走完 → 进休息段，现在过了 3 分钟
    final now = base.add(const Duration(minutes: 48));
    final r = advanceFocusAnchor(a, now);
    expect(r.phase, FocusPhaseName.resting);
    expect(r.worked(now), const Duration(minutes: 45));
    expect(r.rested(now), const Duration(minutes: 3));
  });

  test('离开很久（跨过多段）→ 轮次照常推进，时长不丢', () {
    final a = anchor(phase: FocusPhaseName.working, phaseSince: base);
    // 45+5 = 50 一段循环；过 3 小时 = 180 分钟 → 3 个整循环 + 30 分钟
    final now = base.add(const Duration(minutes: 180));
    final r = advanceFocusAnchor(a, now);
    expect(r.phase, FocusPhaseName.working);
    expect(r.worked(now), const Duration(minutes: 135 + 30));
    expect(r.rested(now), const Duration(minutes: 15));
  });

  test('暂停 → 一段都不推（暂停期间不计时，这是用户选的 (a)）', () {
    final a = anchor(
        phase: FocusPhaseName.paused,
        phaseSince: base,
        worked: const Duration(minutes: 20));
    final now = base.add(const Duration(hours: 5));
    final r = advanceFocusAnchor(a, now);
    expect(r.phase, FocusPhaseName.paused);
    expect(r.worked(now), const Duration(minutes: 20));
  });

  test('脏数据（段长为 0）不会死循环', () {
    final a = anchor(
        phase: FocusPhaseName.working,
        phaseSince: base,
        workMinutes: 0,
        restMinutes: 0);
    final now = base.add(const Duration(hours: 3));
    expect(advanceFocusAnchor(a, now).phase, FocusPhaseName.working);
  });
}
