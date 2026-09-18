import 'package:celechron/design/app_accent.dart';
import 'package:celechron/mod/home_mod_hooks.dart';
import 'package:celechron/mod/update_prompt.dart';
import 'package:celechron/page/desktop/desktop_nav.dart';
import 'package:celechron/page/desktop/desktop_nav_rail.dart';
import 'package:celechron/utils/share_receiver.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/cupertino.dart';

/// ===== 桌面端外框：左侧导航 + 内容区（v1.5.0）=====
///
/// 它是挂在 `GetCupertinoApp(builder: …)` 上的，也就是说它**包在根 Navigator 外面**。
///
/// 为什么必须这样（用户的要求：「让所有的页面都存在侧边栏」）：
/// 一开始我把左侧导航放在了入口页里，而入口页位于根 Navigator **内部** ——
/// 只要有谁 push 一个二级页面（新建待办、课程详情、设置里的子页……），
/// 新页面就整屏盖上去，左侧导航跟着一起消失 ✗
/// 放到 builder 里之后，**所有** push 进来的页面都只占右侧内容区，
/// 导航栏从头到尾都在 ✓
///
/// 内容两侧留白（用户要求：默认窗口下两侧各留 1/6 ~ 1/7）：
/// 直接在 Navigator 外面套一层内边距，这样弹窗和二级页面也一起被收进这个范围里，
/// 不会出现"主页面有留白、二级页面又贴边"的割裂感。
class DesktopFrame extends StatefulWidget {
  const DesktopFrame({super.key, required this.child});

  final Widget child;

  /// 两侧各占窗口宽度的比例。1/6.5 ≈ 0.154，正好落在"六分之一到七分之一"之间。
  static const double sideRatio = 1 / 6.5;

  /// 低于这个宽度（逻辑像素）就不再按比例留白，改成一个小的固定边距。
  ///
  /// 起因：用户的屏幕是 150% 缩放，150% 下 1120 物理像素只有 **747 逻辑像素**宽，
  /// 再各留 1/6 的话中间只剩 300 逻辑像素 —— 页面被挤成一条，看着像"内容被切掉了"。
  /// 所以窄窗口按固定边距走，宽窗口才用用户要的比例。
  static const double proportionalMinWidth = 900;

  /// 窄窗口时的固定边距
  static const double narrowSide = 16;

  /// 按窗口宽度算两侧留白（逻辑像素）
  static double sideInsetFor(double width) =>
      width >= proportionalMinWidth ? width * sideRatio : narrowSide;

  @override
  State<DesktopFrame> createState() => _DesktopFrameState();
}

class _DesktopFrameState extends State<DesktopFrame> {
  bool _dragging = false;

  // 分享 / 闹钟 / 教程跳转这套钩子两端共用；桌面端"跳标签"就是换 DesktopNav.index
  late final HomeModHooks _modHooks = HomeModHooks(
    jumpToTaskTab: () => DesktopNav.go(1),
    jumpToTab: DesktopNav.go,
  );

  @override
  void initState() {
    super.initState();
    _modHooks.start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) checkUpdateOnStart(context);
    });
  }

  @override
  void dispose() {
    _modHooks.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      // 拖文件进窗口 = 手机上的"从别的应用分享进来"（用户拍板的替代方案）
      onDragEntered: (DropEventDetails details) {
        if (!mounted) return;
        setState(() => _dragging = true);
      },
      onDragExited: (DropEventDetails details) {
        if (!mounted) return;
        setState(() => _dragging = false);
      },
      onDragDone: (DropDoneDetails details) async {
        if (!mounted) return;
        setState(() => _dragging = false);
        final items = <SharedItem>[
          for (final file in details.files)
            SharedItem(path: file.path, name: file.name),
        ];
        if (items.isNotEmpty) await _modHooks.acceptDroppedFiles(items);
      },
      child: Container(
        color: CupertinoColors.systemGroupedBackground,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final side = DesktopFrame.sideInsetFor(constraints.maxWidth);
            return Stack(
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    ValueListenableBuilder<int>(
                      valueListenable: DesktopNav.index,
                      builder: (BuildContext context, int index, Widget? _) =>
                          DesktopNavRail(
                        index: index,
                        onSelect: DesktopNav.go,
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: side),
                        child: widget.child,
                      ),
                    ),
                  ],
                ),
                if (_dragging) _dropHint(context),
              ],
            );
          },
        ),
      ),
    );
  }

  /// 拖着文件悬在窗口上时的提示
  Widget _dropHint(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          color: AppAccent.primary.withValues(alpha: 0.08),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
              decoration: BoxDecoration(
                color: CupertinoDynamicColor.resolve(
                    CupertinoColors.secondarySystemBackground, context),
                borderRadius: BorderRadius.circular(14),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x22000000),
                    blurRadius: 18,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(CupertinoIcons.arrow_down_doc,
                      size: 30, color: AppAccent.primary),
                  const SizedBox(height: 8),
                  const Text('松手就加进 Elychron',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text('文件会作为附件，图片还能交给 AI 识别',
                      style: TextStyle(
                          fontSize: 12,
                          color: CupertinoDynamicColor.resolve(
                              CupertinoColors.secondaryLabel, context))),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
