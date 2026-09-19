import 'package:celechron/utils/platform_features.dart';
import 'package:flutter/cupertino.dart';

/// ===== 页面转场：桌面端不要动画（v1.5.0）=====
///
/// 用户原话：「电脑上好像不需要什么丝滑的动画，毕竟其他电脑应用基本上都是点击就切换的。删掉吧！」
///
/// 起因是页面推入时的滑入动画会明显滑到**限宽内容区之外**（比如专注页 → 专注记录页）——
/// 因为内容区被 DesktopFrame 限宽了，而 `CupertinoPageRoute` 的转场是按 Navigator 的
/// 整个宽度滑的。与其凑一个"限宽版滑入"，不如按用户的判断来：
/// **桌面端点击即切换，不做转场**；手机端维持原来的 iOS 滑入（那是它的辨识度）。
///
/// 用法：把 `CupertinoPageRoute<void>(builder: …)` 换成 `appPageRoute<void>(builder: …)`，
/// 参数完全一样。这样两端各走各的，不需要在每个调用点写 if。
Route<T> appPageRoute<T>({
  required WidgetBuilder builder,
  bool fullscreenDialog = false,
  RouteSettings? settings,

  /// 无障碍用的标题（桌面端没有转场，这个参数用不上，只在手机端传给 Cupertino）
  String? title,
  bool maintainState = true,
}) {
  if (PlatformFeatures.isDesktop) {
    // 时长归零 = 直接切换（PageRouteBuilder 本身没有内置转场，正合适）
    return PageRouteBuilder<T>(
      settings: settings,
      fullscreenDialog: fullscreenDialog,
      maintainState: maintainState,
      pageBuilder: (BuildContext context, Animation<double> animation,
              Animation<double> secondaryAnimation) =>
          builder(context),
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
    );
  }
  return CupertinoPageRoute<T>(
    settings: settings,
    builder: builder,
    fullscreenDialog: fullscreenDialog,
    title: title,
    maintainState: maintainState,
  );
}
