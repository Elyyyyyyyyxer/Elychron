import 'package:celechron/page/calendar/calendar_view.dart';
import 'package:celechron/page/desktop/desktop_nav.dart';
import 'package:celechron/page/focus/focus_home_page.dart';
import 'package:celechron/page/option/option_view.dart';
import 'package:celechron/page/scholar/scholar_view.dart';
import 'package:celechron/page/task/task_view.dart';
import 'package:flutter/cupertino.dart';

/// ===== 桌面端主内容区（v1.5.0）=====
///
/// 五个主页面与手机端**完全同一份代码**，只是换了个容器：
/// 手机端是 PageView + 底部标签，这边是 IndexedStack + 左侧竖导航（在外框里）。
///
/// 用 IndexedStack 而不是"切一个建一个"：它把五个页面都留在 widget 树里，
/// 切来切去不丢滚动位置和输入状态（和手机端的 keep-alive 一个意思），
/// 代价是启动时全部构建一次 —— 桌面端不在乎这点。
class DesktopHome extends StatelessWidget {
  const DesktopHome({super.key});

  static final List<Widget> _pages = <Widget>[
    CalendarPage(),
    TaskPage(),
    FocusHomePage(),
    ScholarPage(),
    OptionPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: DesktopNav.index,
      builder: (BuildContext context, int index, Widget? _) =>
          IndexedStack(index: index, children: _pages),
    );
  }
}
