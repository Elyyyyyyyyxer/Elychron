import 'package:flutter/foundation.dart';

/// ===== 桌面端导航状态（v1.5.0）=====
///
/// 为什么单独抽一个全局 notifier：桌面端的左侧导航栏**不在** Navigator 里面
/// （见 `desktop_frame.dart` 的说明 —— 用户要求"所有页面都要有侧边栏"），
/// 而它要控制的那五个主页面在 Navigator 里面，中间隔着好几层，
/// 用 InheritedWidget 传不下去，用 GetX 又会在 builder 里踩注册时序。
/// 一个 ValueNotifier 最省事，也最好测。
class DesktopNav {
  DesktopNav._();

  /// 当前选中的主页面序号（顺序与手机端底部标签一致：
  /// 0 日程 / 1 待办 / 2 专注 / 3 学业 / 4 设置）
  static final ValueNotifier<int> index = ValueNotifier<int>(0);

  /// 主页面数量
  static const int count = 5;

  static void go(int i) {
    if (i < 0 || i >= count) return;
    index.value = i;
  }
}
