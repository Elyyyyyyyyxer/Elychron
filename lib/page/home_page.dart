import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart' show Icons;

import 'package:celechron/page/scholar/scholar_view.dart';
import 'package:celechron/page/task/task_view.dart';
import 'package:celechron/mod/update_prompt.dart';
import 'package:celechron/page/calendar/calendar_view.dart';
import 'package:celechron/page/focus/focus_home_page.dart';
import 'package:celechron/page/option/option_view.dart';
// ===== MOD: 分享接收 / 闹钟逻辑集中在 lib/mod/home_mod_hooks.dart =====
import 'package:celechron/mod/home_mod_hooks.dart';
import 'package:celechron/page/tablet/adaptive_home_body.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.title});

  final String title;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _indexNum = 0;
  final PageController _pageController = PageController();

  // 只构建一次，保持各页 widget 身份稳定，切页时不会重跑各页构造器里的 Get.put
  late final List<Widget> _pages = [
    _KeepAlivePage(child: CalendarPage()),
    _KeepAlivePage(child: TaskPage()),
    // ===== MOD: 专注页（待办/学业之间，插在这里不会动到 jumpToPage(1)）=====
    _KeepAlivePage(child: FocusHomePage()),
    _KeepAlivePage(child: ScholarPage()),
    _KeepAlivePage(child: OptionPage()),
  ];

  // ===== MOD BEGIN: 分享接收 / 闹钟监听 =====

  // ===== MOD BEGIN: 分享接收 / 闹钟 / 教程跳转（实现见 lib/mod/home_mod_hooks.dart）=====
  late final HomeModHooks _modHooks = HomeModHooks(
    jumpToTaskTab: () => _pageController.jumpToPage(1),
    jumpToTab: (int index) => _pageController.jumpToPage(index),
  );
  // ===== MOD END =====

  @override
  void initState() {
    super.initState();
    initFuse();
    _modHooks.start();
  }

  @override
  void dispose() {
    _modHooks.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tabBar = CupertinoTabBar(
      iconSize: 26,
      backgroundColor: CupertinoDynamicColor.resolve(
              CupertinoColors.secondarySystemBackground, context)
          .withValues(alpha: 0.5),
      items: const <BottomNavigationBarItem>[
        BottomNavigationBarItem(
          icon: Icon(CupertinoIcons.calendar),
          label: '日程',
        ),
        BottomNavigationBarItem(
          icon: Icon(CupertinoIcons.check_mark),
          label: '待办',
        ),
        BottomNavigationBarItem(
          icon: Icon(CupertinoIcons.timer),
          label: '专注',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.school_rounded),
          label: '学业',
        ),
        BottomNavigationBarItem(
          icon: Icon(CupertinoIcons.settings),
          label: '设置',
        ),
      ],
      currentIndex: _indexNum,
      // 点按瞬时切换（iOS 原生习惯）。jumpToPage 会同步触发 onPageChanged，
      // _indexNum 只在 onPageChanged 里更新，这里不再 setState
      onTap: (int index) => _pageController.jumpToPage(index),
    );

    final ScrollBehavior scrollBehavior = ScrollConfiguration.of(context);
    // HeroMode 关闭：原先嵌套 CupertinoTabView 导航器会屏蔽标签页内的 Hero
    // 飞行动画（如学业页成绩卡片），这里显式关闭以保持原有行为
    Widget content = HeroMode(
      enabled: false,
      child: PageView(
        controller: _pageController,
        onPageChanged: (index) {
          if (index != _indexNum) {
            setState(() {
              _indexNum = index;
            });
          }
        },
        // 允许鼠标拖动切页（与原 GestureDetector 行为一致），只作用于本 PageView，
        // 不影响页面内部列表；scrollbars 必须关掉，否则桌面端会叠一条横向滚动条
        scrollBehavior: scrollBehavior.copyWith(
          scrollbars: false,
          dragDevices: {
            ...scrollBehavior.dragDevices,
            PointerDeviceKind.mouse,
          },
        ),
        children: _pages,
      ),
    );

    return AdaptiveHomeBody(
      content: content,
      bottomBar: tabBar,
      selectedIndex: _indexNum,
      onSelect: (index) => _pageController.jumpToPage(index),
    );
  }

  /// 启动后的更新检查 + 提示
  ///
  /// v1.5.0 起实现搬到 lib/mod/update_prompt.dart（桌面端要用同一套口径），
  /// 这里只留一行调用，避免两份逻辑漂移。
  Future<void> initFuse() => checkUpdateOnStart(context);
}

// 离屏页面保活：保留滚动位置等临时状态，等价于原先 CupertinoTabScaffold
// 对已构建标签页的常驻行为
class _KeepAlivePage extends StatefulWidget {
  const _KeepAlivePage({required this.child});

  final Widget child;

  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
