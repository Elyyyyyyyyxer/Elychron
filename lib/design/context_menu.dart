import 'package:celechron/utils/platform_features.dart';
import 'package:flutter/cupertino.dart';

/// ===== 长按 / 右键 的统一入口（v1.5.0）=====
///
/// 用户需求：「电脑端由于移植了安卓端的程序，很多操作还是长按完成的。
/// 为了适配电脑需求，请改成右键点击弹出小窗口。」
///
/// 用法：原来写
///
///     GestureDetector(
///       behavior: HitTestBehavior.opaque,
///       onTap: ...,
///       onLongPress: () => 弹菜单(),
///       child: ...,
///     )
///
/// 现在把 GestureDetector 换成 [contextMenuRegion]（参数一模一样）：
/// 手机端继续长按，桌面端变成**右键**。
///
/// 为什么不做成"两个 onXxx 参数"：Dart 没法把命名参数展开传给 GestureDetector，
/// 在每个调用点写 if 又太啰嗦，所以包一层。
/// 手势行为与 GestureDetector 完全一致，只是把 onLongPress 按平台换成 onSecondaryTapUp。
Widget contextMenuRegion({
  required Widget child,
  HitTestBehavior behavior = HitTestBehavior.opaque,
  VoidCallback? onTap,
  VoidCallback? onLongPress,
  GestureTapDownCallback? onTapDown,
  GestureTapUpCallback? onTapUp,
  GestureTapCancelCallback? onTapCancel,
  VoidCallback? onDoubleTap,
}) {
  final desktop = PlatformFeatures.isDesktop;
  return GestureDetector(
    behavior: behavior,
    onTap: onTap == null
        ? null
        : () {
            // 普通点击不是"上下文菜单"，把上一次右键的位置丢掉，
            // 免得之后某个菜单莫名其妙弹在上次右键的地方
            ContextMenuAnchor.remember(null);
            onTap();
          },
    onTapDown: onTapDown,
    onTapUp: onTapUp,
    onTapCancel: onTapCancel,
    onDoubleTap: onDoubleTap,
    // 手机：长按；桌面：右键（两者互斥，另一个平台上都是 null）
    onLongPress: desktop ? null : onLongPress,
    onSecondaryTapUp: desktop && onLongPress != null
        ? (TapUpDetails details) {
            // 记下鼠标位置：菜单会贴着它弹成小窗口（见 showDingTalkMenu）
            ContextMenuAnchor.remember(details.globalPosition);
            onLongPress();
          }
        : null,
    child: child,
  );
}

/// 最近一次右键的位置
///
/// 为什么用这么一个"全局小纸条"而不是给每个调用点加参数：
/// 调用点写的是 onLongPress: () => showDingTalkMenu(...)，菜单函数拿不到手势位置；
/// 要传就得改十来个调用点、而且它们本身不关心位置。
/// 这里右键时记一笔、菜单打开时**取一次就清掉**（读一次即消费），
/// 所以不会把位置带到别的菜单上去。
class ContextMenuAnchor {
  ContextMenuAnchor._();

  static Offset? _pending;

  static void remember(Offset? position) => _pending = position;

  /// 取走位置（取完就没了）
  static Offset? take() {
    final value = _pending;
    _pending = null;
    return value;
  }
}
