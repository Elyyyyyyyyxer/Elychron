import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

/// 把一个页面当成**一张卡片**翻过去。
///
/// 用法：`CardFlipHost(faceKey: 当前是正面还是反面, child: 整页内容)`。
/// [faceKey] 一变就翻一次 —— 调用方不用管动画控制器。
///
/// 注意：**只该在「换面」时改变 [faceKey]**。比如日程页里切到「课表」不算换面，
/// 就不该让 faceKey 变，否则切课表也会翻一下（用户反馈过，那样很突兀）。
class CardFlipHost extends StatelessWidget {
  final Object faceKey;
  final Widget child;

  /// 翻转时长。默认 600ms —— 慢一点能看清「翻过去」的过程，比 300ms 有质感。
  final Duration duration;

  const CardFlipHost({
    super.key,
    required this.faceKey,
    required this.child,
    this.duration = const Duration(milliseconds: 600),
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: Curves.easeInOutCubic,
      switchOutCurve: Curves.easeInOutCubic,
      transitionBuilder: (Widget child, Animation<double> anim) => CardFlip(
        animation: anim,
        incoming: child.key == ValueKey<Object>(faceKey),
        child: child,
      ),
      child: KeyedSubtree(
        key: ValueKey<Object>(faceKey),
        child: child,
      ),
    );
  }
}

/// 卡片翻转：上一面转到 −90° 转走，新一面从 +90° 转回来。
///
/// 两半朝**同一个方向**转，所以看起来是「同一张卡片翻过去」；
/// 若两面各转一半，观感会像两个东西在互相替换。
class CardFlip extends StatelessWidget {
  final Animation<double> animation;

  /// 是不是正在进场的那一面（见 [CardFlipHost] 的判断）
  final bool incoming;
  final Widget child;

  const CardFlip({
    super.key,
    required this.animation,
    required this.incoming,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final progress = CurvedAnimation(
      parent: animation,
      curve: Curves.easeInOutCubic,
    );
    final rotate = Tween<double>(
      begin: incoming ? 1 : 0,
      end: incoming ? 0 : -1,
    ).animate(progress);
    // 转到侧面时稍微缩一点，翻过去的立体感更足
    final scale = Tween<double>(begin: 0.93, end: 1).animate(progress);

    return AnimatedBuilder(
      animation: rotate,
      builder: (BuildContext context, Widget? inner) {
        final angle = rotate.value * (math.pi / 2);
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0012)
            ..rotateY(angle),
          child: Transform.scale(
            scale: incoming ? scale.value : 0.93,
            child: inner,
          ),
        );
      },
      child: child,
    );
  }
}

/// 让翻转的那块内容看起来**像一张实体卡片**：圆角 + 衬底 + 投影 + 裁掉溢出。
///
/// 没有衬底时，翻转过程中只能看到文字在转，很虚；有了这块底，
/// 一眼就能看出「一张卡片翻过去了」。
class FlipCardSurface extends StatelessWidget {
  final Widget child;
  final EdgeInsets margin;

  const FlipCardSurface({
    super.key,
    required this.child,
    this.margin = const EdgeInsets.fromLTRB(10, 6, 10, 6),
  });

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    return Container(
      margin: margin,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: CupertinoDynamicColor.resolve(
            CupertinoColors.systemGroupedBackground, context),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color:
                CupertinoColors.black.withValues(alpha: isDark ? 0.45 : 0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}
