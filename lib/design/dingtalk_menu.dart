import 'package:celechron/design/context_menu.dart';
import 'package:celechron/utils/platform_features.dart';
import 'package:flutter/cupertino.dart';

/// 钉钉风格的操作菜单项
class DingTalkMenuItem {
  final String label;
  final IconData? icon;
  final bool destructive;
  final VoidCallback onTap;

  const DingTalkMenuItem({
    required this.label,
    this.icon,
    this.destructive = false,
    required this.onTap,
  });
}

/// 钉钉风格的⋯菜单
///
/// 两种呈现：
/// - **手机**（默认）：底部行式菜单（圆角卡片 + 竖排图标行 + 独立的取消块，iOS 那种）
/// - **桌面右键**（传了 [position]，或者刚从 [ContextMenuAnchor] 取到右键位置）：
///   贴着鼠标弹一块**小窗口**，更紧凑、没有"取消"块，点外面就关，而且没有动画
///   （用户要求：「改成右键点击弹出小窗口」）
Future<void> showDingTalkMenu(
  BuildContext context, {
  required List<DingTalkMenuItem> items,
  String? title,
  String? message,

  /// 桌面右键的位置；传了就弹成贴着鼠标的小窗口
  Offset? position,
}) {
  // 位置优先用调用方传的，其次用「最近一次右键」记下的那个（见 ContextMenuAnchor）
  final anchor = position ??
      (PlatformFeatures.isDesktop ? ContextMenuAnchor.take() : null);
  final compact = anchor != null;

  final labelColor =
      CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
  final textColor = CupertinoTheme.of(context).textTheme.textStyle.color;

  Widget card({required List<Widget> children}) {
    return Container(
      margin: EdgeInsets.zero,
      decoration: BoxDecoration(
        color: CupertinoDynamicColor.resolve(
            CupertinoColors.systemBackground, context),
        borderRadius: BorderRadius.circular(compact ? 11 : 14),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }

  /// 菜单内容（两种呈现共用）
  ///
  /// [close] 是"关掉菜单"的动作：底部弹层里是 pop 路由，小窗口里是移除 OverlayEntry。
  List<Widget> buildRows(BuildContext context, VoidCallback close) {
    final rows = <Widget>[];
    if (title != null || message != null) {
      rows.add(Padding(
        padding: EdgeInsets.fromLTRB(compact ? 14 : 20, compact ? 12 : 18,
            compact ? 14 : 20, compact ? 10 : 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (title != null)
              Text(
                title,
                style: TextStyle(
                  fontSize: compact ? 13 : 16,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
            if (message != null)
              Padding(
                padding: EdgeInsets.only(top: title == null ? 0 : 6),
                child: Text(
                  message,
                  style: TextStyle(
                      fontSize: compact ? 11.5 : 13, color: labelColor),
                ),
              ),
          ],
        ),
      ));
      rows.add(Container(
        height: 0.5,
        margin: EdgeInsets.symmetric(horizontal: compact ? 14 : 20),
        color:
            CupertinoDynamicColor.resolve(CupertinoColors.separator, context),
      ));
    }
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (i > 0) {
        rows.add(Container(
          height: 0.5,
          margin: EdgeInsets.symmetric(horizontal: compact ? 14 : 20),
          color:
              CupertinoDynamicColor.resolve(CupertinoColors.separator, context),
        ));
      }
      rows.add(GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          close();
          item.onTap();
        },
        child: Padding(
          padding: EdgeInsets.symmetric(
              horizontal: compact ? 14 : 20, vertical: compact ? 10 : 16),
          child: Row(
            children: [
              if (item.icon != null) ...[
                Icon(
                  item.icon,
                  size: compact ? 16 : 20,
                  color:
                      item.destructive ? CupertinoColors.systemRed : textColor,
                ),
                SizedBox(width: compact ? 8 : 12),
              ],
              Expanded(
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 13.5 : 17,
                    color: item.destructive
                        ? CupertinoColors.systemRed
                        : textColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ));
    }
    return rows;
  }

  // ===== 桌面右键：贴鼠标的小窗口 =====
  //
  // 这里用 OverlayEntry 而不是路由：路由（包括 showCupertinoModalPopup）会把内容
  // 从屏幕底部滑上来，贴鼠标的小窗口用那个动画很怪；直接插一个 Overlay 则没有动画，
  // 而且"点外面关掉"自己说了算。
  if (compact) {
    final overlay = Overlay.of(context, rootOverlay: true);
    final screen = MediaQuery.of(context).size;
    const width = 208.0;
    final rowCount =
        items.length + ((title == null && message == null) ? 0 : 1);
    final estimate = 20.0 + rowCount * 36.0;
    final left = anchor.dx
        .clamp(8.0, (screen.width - width - 8).clamp(8.0, screen.width));
    final top = anchor.dy
        .clamp(8.0, (screen.height - estimate - 8).clamp(8.0, screen.height));

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (BuildContext context) => Stack(
        children: [
          // 点外面关掉
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => entry.remove(),
              onSecondaryTap: () => entry.remove(),
            ),
          ),
          Positioned(
            left: left,
            top: top,
            width: width,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(11),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x28000000),
                    blurRadius: 20,
                    offset: Offset(0, 7),
                  ),
                ],
              ),
              child: card(children: buildRows(context, () => entry.remove())),
            ),
          ),
        ],
      ),
    );
    overlay.insert(entry);
    return Future<void>.value();
  }

  // ===== 手机：原来的底部行式菜单 =====
  return showCupertinoModalPopup<void>(
    context: context,
    builder: (BuildContext context) {
      final rows = buildRows(context, () => Navigator.of(context).pop());
      return Padding(
        padding: EdgeInsets.fromLTRB(
            0, 0, 0, MediaQuery.of(context).padding.bottom + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            card(children: rows),
            const SizedBox(height: 8),
            card(children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: Text(
                      '取消',
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            ]),
          ],
        ),
      );
    },
  );
}
