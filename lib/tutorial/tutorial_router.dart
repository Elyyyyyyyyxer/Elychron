import 'package:celechron/tutorial/tutorial_model.dart';

/// ============ 教程去试试按钮的跳转总线 ============
///
/// 为什么单独一个文件：教程的**内容**（`modules/`）要保持纯数据，
/// 而**跳转**需要页面控制器（首页的 PageView）。
/// 让内容层直接依赖页面层会绕成环，所以中间放一个可替换的钩子：
///
/// - 播放器只调 [open]；
/// - 由首页（`home_mod_hooks.dart`）在启动时把真实跳转装进 [handler]。
///
/// 没装 handler 时（比如在测试里、或首页还没起来）跳转静默跳过，
/// 教程本身仍然可以正常看，不会因为"点了个按钮"而崩。
class TutorialRouter {
  TutorialRouter._();

  static final TutorialRouter instance = TutorialRouter._();

  void Function(TutorialTarget target)? handler;

  void open(TutorialTarget target) {
    try {
      handler?.call(target);
    } catch (_) {
      // 跳转失败不影响教程
    }
  }
}
