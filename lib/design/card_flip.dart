import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

/// 把一个页面当成**一张卡片**翻过去。
///
/// ## 三个设计要点（都是踩过坑才明白的）
///
/// **1）每一面必须由「面」算出来，不能是活的 widget**
///
/// 最初的实现是把上一面的 widget 存起来"冻结"，但那个 widget 树里还有 `Obx`
/// 读着 controller —— 状态一变它就跟着重建，于是「点完立刻变成新页面，然后才开始转」✗
/// 所以这里接的是 [faceBuilder]：旧面 = `faceBuilder(旧的面)`，
/// 内容是**算出来的**，跟 controller 无关。只有"是哪个面"被冻结，其它数据照常实时 ✓
///
/// **2）一面只渲染一张卡**
///
/// 不能用 `AnimatedSwitcher`：它让进退两面**同时**存在，一个 +45°、一个 −45°，
/// 屏幕上就是两张互相垂直的卡片 ✗ 这里任何时刻只 build 一面 ✓
///
/// **3）厚度感来自"光照 + 速度曲线"，不是靠加边**
///
/// - 光照：越接近侧面越暗（`sin(|angle|)`），平面立刻变成"表面"
/// - 曲线：前半程**加速**冲向侧面（侧面时角速度最大），后半程**减速**落定并轻微过冲回弹
class CardFlipSwitcher extends StatefulWidget {
  /// 变了才翻。用来区分「该翻的切换」和「不该翻的切换」
  /// （比如日程页里切到课表就不该翻）。
  final Object flipKey;

  /// 当前要渲染的面。可以是任意值（这里传的是视图模式），
  /// 翻转时会先用**上一个面**渲染，转到侧面后才换成这个。
  final Object face;

  /// 由「面」构建那一面的内容
  final Widget Function(Object face) faceBuilder;

  /// 翻转时长。默认 620ms —— 慢一点能看清「翻过去」的过程。
  final Duration duration;

  const CardFlipSwitcher({
    super.key,
    required this.flipKey,
    required this.face,
    required this.faceBuilder,
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

  /// 不在翻转时显示的面
  late Object _shownFace = widget.face;

  /// 翻转中的两个面
  Object? _outgoingFace;
  Object? _incomingFace;

  bool get _flipping => _controller.isAnimating;

  @override
  void didUpdateWidget(covariant CardFlipSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.flipKey != widget.flipKey) {
      // 该翻：旧面用**上一帧的那个面**，新面用当前的
      _outgoingFace = oldWidget.face;
      _incomingFace = widget.face;
      _controller.forward(from: 0).whenComplete(() {
        if (!mounted) return;
        setState(() {
          _shownFace = _incomingFace ?? widget.face;
          _outgoingFace = null;
          _incomingFace = null;
        });
        _controller.value = 0;
      });
    } else if (_flipping) {
      // 翻的过程中内容又变了 → 更新正在进场的那一面，动画不重来
      _incomingFace = widget.face;
    } else {
      // 不翻的切换（例如切课表）：直接换面，不做动画
      _shownFace = widget.face;
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
        final rawHalf = (firstHalf ? t : t - 0.5) * 2;

        // 速度曲线：前半程加速冲向侧面，后半程减速落定 + 轻微过冲回弹
        final half = firstHalf
            ? Curves.easeInCubic.transform(rawHalf)
            : const Cubic(0.18, 1.0, 0.32, 1.06).transform(rawHalf);

        // 一张卡**连续转 180°**：前半 0° → +90°，后半 −90° → 0°（接着同方向继续）
        final angle = (firstHalf ? half : half - 1) * (math.pi / 2);

        final face = firstHalf
            ? (_outgoingFace ?? _shownFace)
            : (_incomingFace ?? _shownFace);

        // 越接近侧面越暗（|angle| 在 90° 时最大）
        final shade = 0.20 * math.sin(angle.abs());
        // 侧面时缩一点，立体感更足
        final scale = 1 - 0.07 * math.sin(angle.abs());

        // 不要用 Stack 包住 faceBuilder：整页内部有 Expanded，Stack 的非定位子项
        // 会拿到不明确的高度约束，触发 RenderFlex 构建异常（错误提示因此盖到日程页）。
        // ColorFiltered 不改变布局约束，只负责把转开的表面压暗。
        final faceWidget = widget.faceBuilder(face);
        final shadedFace = shade > 0.001
            ? ColorFiltered(
                colorFilter: ColorFilter.mode(
                  CupertinoColors.black.withValues(alpha: shade),
                  BlendMode.darken,
                ),
                child: faceWidget,
              )
            : faceWidget;

        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0022)
            ..rotateY(angle),
          child: Transform.scale(scale: scale, child: shadedFace),
        );
      },
    );
  }
}
