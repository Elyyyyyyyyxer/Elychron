import 'package:celechron/design/app_route.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

/// 页面转场：**桌面端不要动画**（v1.5.0）。
///
/// 用户原话：「电脑上好像不需要什么丝滑的动画，毕竟其他电脑应用基本上都是点击就切换的。删掉吧！」
/// 起因是推入动画会明显滑到限宽内容区**之外**（比如专注页 → 专注记录页）——
/// 内容区被 DesktopFrame 限宽了，而 CupertinoPageRoute 是按 Navigator 整个宽度滑的。
///
/// 测试跑在 Windows 上，所以 PlatformFeatures.isDesktop 为真，
/// 这条断言验的正是"桌面端拿到的是零转场路由"。
void main() {
  test('桌面端：页面路由的转场时长为 0（点击即切换）', () {
    // 返回类型是 Route，具体时长要当成 PageRoute 看才有
    final route =
        appPageRoute<void>(builder: (_) => const SizedBox()) as PageRoute<void>;
    expect(route.transitionDuration, Duration.zero);
    expect(route.reverseTransitionDuration, Duration.zero);
  });

  test('桌面端：仍然是正常可用的路由（能返回、能带参数）', () {
    final route = appPageRoute<bool>(
      settings: const RouteSettings(name: '/x'),
      fullscreenDialog: true,
      builder: (_) => const SizedBox(),
    ) as PageRoute<bool>;
    expect(route.settings.name, '/x');
    expect(route.fullscreenDialog, isTrue);
    expect(route.maintainState, isTrue);
  });
}
