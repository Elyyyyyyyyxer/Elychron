import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

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

  /// 切到某个主页面：**先把二级页面退掉，再换页**
  ///
  /// 为什么必须退（用户 2026-09-19 反馈"在某个二级页面时点侧边栏切不过去"）：
  /// 左侧导航栏挂在根 Navigator **外面**（这样 push 二级页面时它不会被盖住），
  /// 而二级页面（新建待办、课程详情……）只盖住右边的内容区 ——
  /// 于是用户点侧边栏时"看得见导航栏，点了却没反应"：
  /// 新选的主页面在二级页面**下面**，得先把上面那层退掉才看得见。
  static void goAndPop(int i, {NavigatorState? navigator}) {
    if (i < 0 || i >= count) return;
    try {
      // 平时用 App 的根 navigator；测试可以注入一个自己的（见 desktop_nav_test）
      final state = navigator ?? Get.key.currentState;
      state?.popUntil((Route<dynamic> route) => route.isFirst);
    } catch (_) {
      // 拿不到 navigator（启动早期等）就只换页
    }
    index.value = i;
  }
}
