import 'dart:convert';

import 'package:celechron/database/database_helper.dart';
import 'package:get/get.dart';

/// ===== 专注的「锚点」：只记时间与状态，时长一律按时间推算（v1.5.0）=====
///
/// 用户原话（2026-09-21）：
/// 「目前的专注模式容易被打断，还有杀后台等等问题。那就干脆不在过程中计数了，
///   直接算起止时间 + 增设一个状态变量（中断中，进行中，休息中），
///   这样就算后台被杀掉也能保证时间计算准确」
///
/// 旧做法的问题：计时靠页面里的 Timer 累加 ✗ ——
/// 页面一关、App 一被杀，累加值就停了；所以之前要靠 SuspendedFocus
/// 存「还剩多久 / 暂停前是工作还是休息」去补偿，很脆。
///
/// 新做法：**只持久化四个事实**，其余全部推算出来 ——
///   · 这次专注什么时候开始的（uid + startedAt）
///   · 现在处于哪个状态（进行中 / 休息中 / 中断中）
///   · 当前这一段是什么时候开始的（phaseSince）
///   · 切到本段之前累计了多少（workedBefore / restedBefore）
/// 于是「专注了多久」= workedBefore + (进行中 ? now - phaseSince : 0)，
/// 跟是否在计时、页面在不在、App 有没有被杀**完全无关** ✓
///
/// ⚠️ 不动 Hive 结构：锚点存 optionsBox（JSON），
/// 与「设备标注」「墓碑」同一套做法（用户明确提醒过别搞崩字段数）。
enum FocusPhaseName { working, resting, paused }

extension FocusPhaseNameX on FocusPhaseName {
  /// 用户看得懂的说法（用户指定：中断中 / 进行中 / 休息中）
  String get label => switch (this) {
        FocusPhaseName.working => '进行中',
        FocusPhaseName.resting => '休息中',
        FocusPhaseName.paused => '中断中',
      };

  static FocusPhaseName parse(String? raw) => switch (raw) {
        'resting' => FocusPhaseName.resting,
        'paused' => FocusPhaseName.paused,
        _ => FocusPhaseName.working,
      };
}

class FocusAnchor {
  /// 会话 uid（与 FocusSession 对应）
  final String uid;

  /// 这次专注是什么时候开始的（用来算「这次专注总跨度」）
  final DateTime startedAt;

  /// 当前状态
  final FocusPhaseName phase;

  /// 当前这一段是什么时候开始的
  ///
  /// 「中断中」时它是**进入中断的时刻** —— 所以中断期间不计入任何时长 ✓
  final DateTime phaseSince;

  /// 切到本段之前已经专注 / 休息了多久
  final Duration workedBefore;
  final Duration restedBefore;

  /// 计划参数（用来判断该不该切段、还剩多少）
  final int workMinutes;
  final int restMinutes;

  const FocusAnchor({
    required this.uid,
    required this.startedAt,
    required this.phase,
    required this.phaseSince,
    this.workedBefore = Duration.zero,
    this.restedBefore = Duration.zero,
    this.workMinutes = 60,
    this.restMinutes = 15,
  });

  /// 到目前为止**专注**了多久（纯函数：只看 now）
  Duration worked(DateTime now) =>
      workedBefore +
      (phase == FocusPhaseName.working
          ? now.difference(phaseSince)
          : Duration.zero);

  /// 到目前为止**休息**了多久
  Duration rested(DateTime now) =>
      restedBefore +
      (phase == FocusPhaseName.resting
          ? now.difference(phaseSince)
          : Duration.zero);

  /// 本段还剩多久（负数收敛到 0）
  Duration currentSegmentRemaining(DateTime now) {
    final planned = Duration(
        minutes: phase == FocusPhaseName.resting ? restMinutes : workMinutes);
    final elapsed = phase == FocusPhaseName.resting
        ? rested(now) - restedBefore
        : worked(now) - workedBefore;
    final left = planned - elapsed;
    return left.isNegative ? Duration.zero : left;
  }

  /// 本段是否已经走完（该切段了）
  bool segmentFinished(DateTime now) =>
      currentSegmentRemaining(now) == Duration.zero;

  /// 切到另一个状态：把本段已走的时长结算进累计，重锚现在
  FocusAnchor switchingTo(FocusPhaseName next, DateTime now) {
    if (next == phase) return this;
    return FocusAnchor(
      uid: uid,
      startedAt: startedAt,
      phase: next,
      phaseSince: now,
      workedBefore: worked(now),
      restedBefore: rested(now),
      workMinutes: workMinutes,
      restMinutes: restMinutes,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'uid': uid,
        'startedAt': startedAt.toIso8601String(),
        'phase': phase.name,
        'phaseSince': phaseSince.toIso8601String(),
        'workedMs': workedBefore.inMilliseconds,
        'restedMs': restedBefore.inMilliseconds,
        'workMinutes': workMinutes,
        'restMinutes': restMinutes,
      };

  static FocusAnchor? fromJson(Map<String, dynamic> json) {
    final uid = json['uid']?.toString() ?? '';
    if (uid.isEmpty) return null;
    final startedAt = DateTime.tryParse(json['startedAt']?.toString() ?? '');
    if (startedAt == null) return null;
    return FocusAnchor(
      uid: uid,
      startedAt: startedAt,
      phase: FocusPhaseNameX.parse(json['phase']?.toString()),
      phaseSince:
          DateTime.tryParse(json['phaseSince']?.toString() ?? '') ?? startedAt,
      workedBefore:
          Duration(milliseconds: (json['workedMs'] as num?)?.toInt() ?? 0),
      restedBefore:
          Duration(milliseconds: (json['restedMs'] as num?)?.toInt() ?? 0),
      workMinutes: (json['workMinutes'] as num?)?.toInt() ?? 60,
      restMinutes: (json['restMinutes'] as num?)?.toInt() ?? 15,
    );
  }
}

/// 锚点的存取（optionsBox，JSON）
class FocusAnchorStore {
  FocusAnchorStore._();

  static const String _key = 'focusAnchor';

  static DatabaseHelper? get _db {
    try {
      return Get.find<DatabaseHelper>(tag: 'db');
    } catch (_) {
      return null;
    }
  }

  static FocusAnchor? load() {
    try {
      final raw = _db?.optionsBox.get(_key);
      if (raw is String && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return FocusAnchor.fromJson(Map<String, dynamic>.from(decoded));
        }
      }
    } catch (_) {}
    return null;
  }

  static Future<void> save(FocusAnchor anchor) async {
    try {
      await _db?.optionsBox.put(_key, jsonEncode(anchor.toJson()));
    } catch (_) {}
  }

  static Future<void> clear() async {
    try {
      await _db?.optionsBox.delete(_key);
    } catch (_) {}
  }
}
