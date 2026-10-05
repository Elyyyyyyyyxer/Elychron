import 'package:celechron/design/app_accent.dart';
import 'package:flutter/cupertino.dart';

/// 桌面端左上角那条竖导航（v1.5.0）
///
/// 单独抽出来有两个原因：
/// 1. 用户拍板的桌面布局核心就是这条导航（左上角竖列、正中间是功能页），
///    它值得有自己的名字，而不是埋在某个 State 的 build 里；
/// 2. 抽出来之后**能单测**：点一下会不会选中、会不会回调出去，
///    这些不用把五个功能页都拉起来就能验（那五个页面依赖 GetX 注册，很重）。
class DesktopNavRail extends StatelessWidget {
  const DesktopNavRail({
    super.key,
    required this.index,
    required this.onSelect,
    this.width = 208,
    this.showDropHint = true,
  });

  /// 当前选中的序号
  final int index;

  /// 点某一项时回调（参数是序号）
  final ValueChanged<int> onSelect;

  final double width;
  final bool showDropHint;

  /// 导航项：与手机端底部标签一一对应（日程 / 待办 / 专注 / 学业 / 设置）
  static const List<DesktopNavItem> items = <DesktopNavItem>[
    DesktopNavItem(icon: CupertinoIcons.calendar, label: '日程'),
    DesktopNavItem(icon: CupertinoIcons.check_mark, label: '待办'),
    DesktopNavItem(icon: CupertinoIcons.time, label: '专注'),
    DesktopNavItem(icon: CupertinoIcons.book, label: '学业'),
    DesktopNavItem(icon: CupertinoIcons.settings, label: '设置'),
  ];

  @override
  Widget build(BuildContext context) {
    final labelColor =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    final accent = AppAccent.primary;
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: CupertinoDynamicColor.resolve(
            CupertinoColors.secondarySystemBackground, context),
        border: Border(
          right: BorderSide(
            width: 0.5,
            color: CupertinoDynamicColor.resolve(
                CupertinoColors.separator, context),
          ),
        ),
      ),
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
              child: Row(
                children: <Widget>[
                  // ===== 左上角这个才是"爱莉"（用户 2026-09-30 明确指出来）=====
                  //
                  // 就是 App 图标本身（assets/logo.png，粉色圆底头像）。
                  // 原来是"爱莉粉方块 + 白色时钟字形"，那只是个占位标。
                  // 裁成圆角（原图是圆底，方形摆上去会露四角）。
                  ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: Image.asset(
                      'assets/logo.png',
                      width: 26,
                      height: 26,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Expanded + 省略号：字体一换（微软雅黑比默认字体宽一点点）
                  // 或者用户把窗口调窄，这行就会溢出（测试实测溢出过 1.2px）
                  const Expanded(
                    child: Text(
                      'Elychron',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            for (var i = 0; i < items.length; i++)
              _tile(context, i, labelColor, accent),
            const Spacer(),
            if (showDropHint)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Text(
                  '把文件拖进窗口即可添加为待办附件',
                  style: TextStyle(fontSize: 11, color: labelColor),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, int i, Color labelColor, Color accent) {
    final selected = i == index;
    final item = items[i];
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onSelect(i),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.14)
              : CupertinoColors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          children: <Widget>[
            // 导航项还是系统字形（2026-09-30 更正）。
            //
            // 用户的原话：「我让你给电脑版的导航栏图标换成爱莉，不是说把每一个
            // "日程""待办"等等条目前面加上，删掉。我的意思是最左上角那个大字
            // Elychron 左边的图标需要换掉」——
            // 所以爱莉只出现在左上角那个 App 标上（build 里那个 Image.asset），
            // 每一项这里回到各自的功能图标，一眼能分清是哪一页。
            Icon(
              item.icon,
              size: 19,
              color: selected ? accent : labelColor,
            ),
            const SizedBox(width: 12),
            Text(
              item.label,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                color: selected ? accent : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DesktopNavItem {
  final IconData icon;
  final String label;
  const DesktopNavItem({required this.icon, required this.label});
}
