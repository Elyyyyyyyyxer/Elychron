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

  /// 内容区的最大宽度（逻辑像素）。
  ///
  /// 用户最早的意见是"一条会被拉得很长"，但加了边距之后又觉得"割裂"——
  /// 所以改成这个折中：**背景照旧铺满整个窗口，只把内容块限宽居中**。
  static const double contentMaxWidth = 920;

  /// 内容区最多占窗口宽度的多少。
  ///
  /// ⚠️ 光有 [contentMaxWidth] 是不够的：用户的窗口只有约 700 逻辑像素宽
  /// （150% 缩放下 1050 物理像素），920 这个上限**永远不会触发**，
  /// 看上去就跟没限宽一样（2026-09-19 用户反馈"实际内容好像并没有限宽"）。
  /// 所以再加一道按比例的上限：两边各留约 14%，与用户最早说的 1/6~1/7 同一档。
  static const double contentWidthFactor = 0.72;

  /// 左侧导航栏宽度（与 DesktopNavRail 的默认值保持一致）
  static const double railWidth = 208;

  /// 按**可用宽度**算内容区宽度上限。
  ///
  /// ⚠️ 传进来的必须是"扣掉导航栏之后"的宽度。第一版传的是整个窗口宽度，
  /// 于是算出来的上限恰好等于可用宽度本身 —— 等于没限宽
  /// （用户反馈"实际内容好像并没有限宽"，测试也复现了：期望 570、实际 720）。
  static double contentWidthFor(double available) {
    final byRatio = available * contentWidthFactor;
    return byRatio < contentMaxWidth ? byRatio : contentMaxWidth;
  }

  @override
  State<DesktopFrame> createState() => _DesktopFrameState();
}

class _DesktopFrameState extends State<DesktopFrame> {
  bool _dragging = false;

  // 分享 / 闹钟 / 教程跳转这套钩子两端共用；桌面端"跳标签"就是换 DesktopNav.index
  late final HomeModHooks _modHooks = HomeModHooks(
    // 教程里"去试试"、分享进来跳待办……同样要先退掉二级页面
    jumpToTaskTab: () => DesktopNav.goAndPop(1),
    jumpToTab: DesktopNav.goAndPop,
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
        // 背景色与页面自身一致（systemBackground）：内容限宽之后两侧露出来的是这一层，
        // 同色才不会出现"页面被切成一条"的割裂感（用户 2026-09-18 反馈）。
        color: CupertinoDynamicColor.resolve(
            CupertinoColors.systemBackground, context),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
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
                        onSelect: DesktopNav.goAndPop,
                      ),
                    ),
                    Expanded(
                      // 不用 Padding（那会连页面背景一起切掉，看着割裂），
                      // 改成"内容居中 + 限宽"：背景仍然铺满，只有内容块不会拉得很长。
                      // 注意这里传的是**扣掉导航栏之后**的宽度（见 contentWidthFor 的注释）。
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: DesktopFrame.contentWidthFor(
                                constraints.maxWidth - DesktopFrame.railWidth),
                          ),
                          child: widget.child,
                        ),
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
