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
    // ⚠️ 退场与进场要用**不同的 Tween**：
    // - 进场那面：animation 从 0→1，希望角度 +90°→0°
    //   → Tween(begin: 1, end: 0)
    // - 退场那面：AnimatedSwitcher 会把 animation **反向**播放（1→0），
    //   希望角度 0°→−90° → Tween(begin: -1, end: 0)
    //   （如果写成 Tween(0, -1)，退场卡片在动画一开始就被算成 −90°，
    //    于是「啪」地瞬间变成竖直一条线再转回来 —— 这个 bug 踩过）
    final rotate = Tween<double>(
      begin: incoming ? 1 : -1,
      end: 0,
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
