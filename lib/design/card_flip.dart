import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

/// 把一个页面当成**一张卡片**翻过去。
///
/// ## 为什么不用 AnimatedSwitcher
///
/// 直觉上 `AnimatedSwitcher` + 自定义 transition 就能做翻牌，但它是**两面同时存在**的：
/// 旧面转到 −45°、新面从 +45° 转回来 —— 两张卡恰好差 90°，屏幕上就是
/// **两张互相垂直的卡片** ✗（这个 bug 真踩过）
///
/// 真实的一张卡片翻转，**任何时刻只有一张卡在转**：
/// 前半程旧面从 0° 转到 90°（转到侧面、看不见了），后半程新面从 −90° 转回 0°。
/// 所以这里自己用 [AnimationController] 驱动，在转到侧面的那一瞬间换内容 ——
/// 侧面时什么都看不见，换内容不会被看出来。
class CardFlipSwitcher extends StatefulWidget {
  /// 「面」的标识：只有它变了才翻。内容变了但 faceKey 没变 → 直接换内容，不翻。
  ///
  /// 这样可以让「切到课表」之类的切换不触发翻转（用户反馈过那样很突兀）。
  final Object faceKey;

  /// 当前这一面的内容（每次 build 传最新的，倒计时之类的刷新不会被冻住）
  final Widget child;

  /// 翻转时长。默认 620ms —— 慢一点能看清「翻过去」的过程。
  final Duration duration;

  const CardFlipSwitcher({
    super.key,
    required this.faceKey,
    required this.child,
    this.duration = const Duration(milliseconds: 620),
  });

  @override
  State<CardFlipSwitcher> createState() => _CardFlipSwitcherState();
}

class _CardFlipSwitcherState extends State<CardFlipSwitcher>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  /// 正在显示的那一面（翻转中会被冻住 —— 只冻 0.6 秒，无所谓）
  late Widget _front = widget.child;

  /// 翻转结束后要换上的新内容
  Widget? _pending;

  bool get _flipping => _controller.isAnimating;

  @override
  void didUpdateWidget(covariant CardFlipSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.faceKey != widget.faceKey) {
      // 换面 → 翻一次
      _pending = widget.child;
      _controller.forward(from: 0).whenComplete(() {
        if (!mounted) return;
        setState(() {
          _front = _pending ?? widget.child;
          _pending = null;
        });
        _controller.value = 0;
      });
    } else if (!_flipping) {
      // 同一面里内容更新（倒计时、列表变化）→ 直接跟着更新
      _front = widget.child;
    } else {
      // 正在翻的时候又来了新内容 → 更新待显示的那一面，动画不用重来
      _pending = widget.child;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? _) {
        final t = _controller.value; // 0..1
        final firstHalf = t < 0.5;
        // 前半程：旧面 0° → +90°（转出去）；后半程：新面 −90° → 0°（转回来）
        final half = (firstHalf ? t : t - 0.5) * 2;
        final angle = half * (math.pi / 2);
        final shown = firstHalf ? _front : (_pending ?? _front);
        // 转到侧面时稍微缩一点，立体感更足
        final scale = 1 - 0.07 * math.sin(half * (math.pi / 2));

        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0012)
            ..rotateY(firstHalf ? angle : -angle),
          child: Transform.scale(scale: scale, child: shown),
        );
      },
    );
  }
}
