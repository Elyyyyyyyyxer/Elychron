import 'package:flutter/foundation.dart';

/// ===== 专注的"现在到底在不在专注"（运行时状态）=====
///
/// 为什么要有这个全局状态（2026-09-17 用户报的两个问题指向同一处）：
///
/// 1. **分享进来时不该打断专注**：拦截逻辑原来用的是库里的
///    "有没有未结算的会话"，而 App 被系统杀掉后那条会话**会一直留着**，
///    于是分享被无限期"攒着" —— 表现就是"图片分享进来没有弹窗"。
/// 2. **开始专注前要知道有没有一次还没结束**：见专注首页的开始按钮。
///
/// 引擎（FocusEngine）是 [FocusPage] 私有的，页面一销毁状态就没了，
/// 所以这里放一份**只读的**运行时快照供各方查询，任何界面都能读到"现在在不在专注"。
///
/// 谁负责写：专注页（running / paused / idle）与专注首页（有暂停中的会话 = paused）。
/// 谁负责读：分享拦截（home_mod_hooks）、专注首页的开始守卫。
enum FocusRunState {
  /// 没有任何专注在进行
  idle,

  /// 正在专注（计时中）
  running,

  /// 有一次专注停在那儿等着继续（暂停后离开 / App 被杀留下的会话被接住）
  paused,
}

class FocusRuntime {
  FocusRuntime._();

  /// 当前状态。用 [ValueNotifier] 是为了将来能直接监听变化，不用轮询。
  static final ValueNotifier<FocusRunState> state =
      ValueNotifier<FocusRunState>(FocusRunState.idle);

  static FocusRunState get value => state.value;

  /// **真的**在计时吗（暂停不算）。分享拦截只看这一个。
  static bool get isRunning => state.value == FocusRunState.running;

  /// 有没有一次专注停在那儿等着继续
  static bool get isPaused => state.value == FocusRunState.paused;

  static void set(FocusRunState next) {
    if (state.value != next) state.value = next;
  }
}
