import 'package:celechron/database/database_helper.dart';
import 'package:celechron/tutorial/tutorial_model.dart';
import 'package:celechron/tutorial/tutorial_progress.dart';
import 'package:celechron/tutorial/tutorial_registry.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

/// ============ 教程状态的持久化 + 全局入口 ============
///
/// 存哪儿：和本仓库其它"魔改新增的设置"一样，落在数据库的 options box 里
/// （见 `lib/mod/database_mod.dart` 的同款做法），键名 [kTutorialStateKey]。
///
/// 为什么不各页面自己 `Get.find<DatabaseHelper>()` 判断：
/// "看过没有"必须在**任何入口**结果一致（教程中心、帮助按钮、首用提示），
/// 所以集中在这一个单例里，并带一层内存缓存（避免每次进页面都读 Hive）。
class TutorialStore {
  TutorialStore._();

  static final TutorialStore instance = TutorialStore._();

  static const String kTutorialStateKey = 'tutorialState';

  TutorialState _state = TutorialState();
  bool _loaded = false;

  /// 状态变化通知（教程中心据此刷新"已看/未看"）
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  DatabaseHelper? get _db {
    if (!Get.isRegistered<DatabaseHelper>(tag: 'db')) return null;
    return Get.find<DatabaseHelper>(tag: 'db');
  }

  /// 当前状态（第一次访问会从库里读一次）
  TutorialState get state {
    if (!_loaded) _load();
    return _state;
  }

  void _load() {
    _loaded = true;
    try {
      final db = _db;
      if (db == null) return;
      final raw = db.optionsBox.get(kTutorialStateKey);
      if (raw is Map) {
        _state = TutorialState.fromJson(
          raw.map((key, value) => MapEntry(key.toString(), value)),
        );
      }
    } catch (_) {
      // 读不出来就当全新（最坏情况：已看过的教程再提示一次）
      _state = TutorialState();
    }
  }

  Future<void> _persist() async {
    revision.value++;
    try {
      await _db?.optionsBox.put(kTutorialStateKey, _state.toJson());
    } catch (_) {
      // 落盘失败不影响本次观看
    }
  }

  bool hasSeen(Tutorial tutorial) => state.hasSeen(tutorial);
  bool isMuted(Tutorial tutorial) => state.isMuted(tutorial);
  int lastIndex(Tutorial tutorial) => state.lastIndex(tutorial);

  /// 看完一篇
  Future<void> markSeen(Tutorial tutorial) async {
    state.markSeen(tutorial);
    await _persist();
  }

  /// 中途退出，记进度
  Future<void> saveProgress(Tutorial tutorial, int index) async {
    state.saveProgress(tutorial, index);
    await _persist();
  }

  /// 不再提示
  Future<void> mute(Tutorial tutorial) async {
    state.mute(tutorial);
    await _persist();
  }

  /// 重新观看（清掉这篇的记录）
  Future<void> reset(Tutorial tutorial) async {
    state.reset(tutorial);
    await _persist();
  }

  /// 教程中心用：按分组拿"可见"的教程（未登录时隐藏 loggedInOnly 的）
  Map<TutorialGroup, List<Tutorial>> visibleGrouped({required bool loggedIn}) {
    final result = <TutorialGroup, List<Tutorial>>{};
    TutorialRegistry.grouped.forEach((group, tutorials) {
      final visible = tutorials
          .where((t) => t.audience == TutorialAudience.everyone || loggedIn)
          .toList();
      if (visible.isNotEmpty) result[group] = visible;
    });
    return result;
  }

  /// 首用提示用：还没看过、也没被静音的教程
  List<Tutorial> pending({bool loggedIn = true}) => state.pendingOf(
        TutorialRegistry.all
            .where((t) => t.audience == TutorialAudience.everyone || loggedIn),
      );

  /// 仅供测试：直接注入状态，避免依赖数据库
  @visibleForTesting
  void setStateForTest(TutorialState state) {
    _state = state;
    _loaded = true;
  }
}
