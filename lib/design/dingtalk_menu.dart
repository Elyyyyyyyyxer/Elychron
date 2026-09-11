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

/// 钉钉风格的「⋯」菜单：圆角卡片 + 竖排图标行 + 独立的「取消」块
Future<void> showDingTalkMenu(
  BuildContext context, {
  required List<DingTalkMenuItem> items,
  String? title,
  String? message,
}) {
  final labelColor =
      CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
  final textColor = CupertinoTheme.of(context).textTheme.textStyle.color;

  Widget card({required List<Widget> children}) {
    return Container(
      // 水平方向顶到屏幕边缘
      margin: EdgeInsets.zero,
      decoration: BoxDecoration(
        color: CupertinoDynamicColor.resolve(
            CupertinoColors.systemBackground, context),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }

  return showCupertinoModalPopup<void>(
    context: context,
    builder: (BuildContext context) {
      final rows = <Widget>[];
      if (title != null || message != null) {
        rows.add(Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (title != null)
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
              if (message != null)
                Padding(
                  padding: EdgeInsets.only(top: title == null ? 0 : 6),
                  child: Text(
                    message,
                    style: TextStyle(fontSize: 13, color: labelColor),
                  ),
                ),
            ],
          ),
        ));
        rows.add(Container(
          height: 0.5,
          margin: const EdgeInsets.symmetric(horizontal: 20),
          color:
              CupertinoDynamicColor.resolve(CupertinoColors.separator, context),
        ));
      }
      for (var i = 0; i < items.length; i++) {
        final item = items[i];
        if (i > 0) {
          rows.add(Container(
            height: 0.5,
            margin: const EdgeInsets.symmetric(horizontal: 20),
            color: CupertinoDynamicColor.resolve(
                CupertinoColors.separator, context),
          ));
        }
        rows.add(GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            Navigator.of(context).pop();
            item.onTap();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                if (item.icon != null) ...[
                  Icon(
                    item.icon,
                    size: 20,
                    color: item.destructive
                        ? CupertinoColors.systemRed
                        : textColor,
                  ),
                  const SizedBox(width: 12),
                ],
                Text(
                  item.label,
                  style: TextStyle(
                    fontSize: 17,
                    color: item.destructive
                        ? CupertinoColors.systemRed
                        : textColor,
                  ),
                ),
              ],
            ),
          ),
        ));
      }

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
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: Text(
                      '取消',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: labelColor,
                      ),
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
