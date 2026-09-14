import 'package:celechron/tutorial/tutorial_model.dart';

/// ============ 教程进度：纯逻辑，便于单测 ============
///
/// 播放器里所有"上一步/下一步/第几步"的判断都走这里，
/// 不要在界面上散着写 `index + 1 < steps.length` 这类算术。
class TutorialProgress {
  TutorialProgress._();

  /// 下一步的下标（已经在最后一步就停在原地）
  static int nextIndex(int current, int total) {
    if (total <= 0) return 0;
    final next = current + 1;
    return next >= total ? total - 1 : next;
  }

  /// 上一步的下标（已经在第一步就停在原地）
  static int prevIndex(int current, int total) {
    if (total <= 0) return 0;
    final prev = current - 1;
    return prev < 0 ? 0 : prev;
  }

  static bool isFirst(int current) => current <= 0;

  static bool isLast(int current, int total) =>
      total <= 0 || current >= total - 1;

  /// 进度比例（0~1），给顶部的进度条用
  static double ratio(int current, int total) {
    if (total <= 1) return 1;
    final clamped = current.clamp(0, total - 1);
    return (clamped + 1) / total;
  }

  /// 把持久化里读出来的下标收敛到合法范围（内容改短了也不会越界）
  static int clamp(int current, int total) {
    if (total <= 0) return 0;
    if (current < 0) return 0;
    if (current >= total) return total - 1;
    return current;
  }
}

/// ============ 「已看过 / 不再提示 / 看到第几步」的状态 ============
///
/// 纯内存模型 + 变更回调；真正的落盘在 `tutorial_store.dart`。
/// 拆开的原因：状态变化规则（什么算看过、进度怎么合并）可以脱库单测。
class TutorialState {
  /// 已经看过的 `seenKey`（`id@v版本`）
  final Set<String> seen;

  /// 已明确"不再提示"的教程 id
  final Set<String> muted;

  /// 每篇教程看到第几步（id → 下标）
  final Map<String, int> progress;

  TutorialState({
    Set<String>? seen,
    Set<String>? muted,
    Map<String, int>? progress,
  })  : seen = seen ?? <String>{},
        muted = muted ?? <String>{},
        progress = progress ?? <String, int>{};

  /// 这篇教程看过没有（**内容版本变了会重新算没看过**）
  bool hasSeen(Tutorial tutorial) => seen.contains(tutorial.seenKey);

  /// 是否被用户"不再提示"
  bool isMuted(Tutorial tutorial) => muted.contains(tutorial.id);

  /// 上次看到第几步
  int lastIndex(Tutorial tutorial) =>
      TutorialProgress.clamp(progress[tutorial.id] ?? 0, tutorial.steps.length);

  /// 看完一篇：标记 seen，并清掉"不再提示"（用户重新看完就是想再被提示）
  void markSeen(Tutorial tutorial) {
    seen.add(tutorial.seenKey);
    muted.remove(tutorial.id);
    progress[tutorial.id] = tutorial.steps.length - 1;
  }

  /// 中途退出：只记进度，**不算看过**（下次进来接着看）
  void saveProgress(Tutorial tutorial, int index) {
    progress[tutorial.id] =
        TutorialProgress.clamp(index, tutorial.steps.length);
  }

  /// 不再提示这篇
  void mute(Tutorial tutorial) {
    muted.add(tutorial.id);
  }

  /// 重置一篇（教程中心提供"重新观看"）
  void reset(Tutorial tutorial) {
    seen.remove(tutorial.seenKey);
    muted.remove(tutorial.id);
    progress.remove(tutorial.id);
  }

  /// 当前"没看过、也没被静音"的教程（首用自动提示用这个筛选）
  List<Tutorial> pendingOf(Iterable<Tutorial> tutorials) => [
        for (final tutorial in tutorials)
          if (tutorial.showOnFirstUse &&
              !hasSeen(tutorial) &&
              !isMuted(tutorial))
            tutorial,
      ];

  /// 导出成可落盘的形式
  Map<String, dynamic> toJson() => {
        'seen': seen.toList(),
        'muted': muted.toList(),
        'progress': progress.map((k, v) => MapEntry(k, v)),
      };

  static TutorialState fromJson(Map<String, dynamic>? json) {
    if (json == null) return TutorialState();
    // ⚠️ 一律用 is 判断而不是 as 强转：这个键是磁盘上的数据，
    // 版本回退、手工改过、写坏都可能出现类型不对的值，不能因此崩在启动路径上。
    final rawSeen = json['seen'];
    final seen = rawSeen is List
        ? rawSeen.whereType<String>().toSet()
        : <String>{};
    final rawMuted = json['muted'];
    final muted = rawMuted is List
        ? rawMuted.whereType<String>().toSet()
        : <String>{};
    final rawProgress = json['progress'];
    final progress = <String, int>{};
    if (rawProgress is Map) {
      rawProgress.forEach((key, value) {
        if (key is String && value is int) progress[key] = value;
      });
    }
    return TutorialState(seen: seen, muted: muted, progress: progress);
  }
}
