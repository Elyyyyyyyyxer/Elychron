import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/services.dart' show SystemNavigator;
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'package:celechron/page/scholar/scholar_view.dart';
import 'package:celechron/page/task/task_view.dart';
import 'package:celechron/page/calendar/calendar_view.dart';
import 'package:celechron/page/focus/focus_home_page.dart';
import 'package:celechron/page/option/option_view.dart';
// ===== MOD: 分享接收 / 闹钟逻辑集中在 lib/mod/home_mod_hooks.dart =====
import 'package:celechron/mod/home_mod_hooks.dart';

import 'package:celechron/worker/fuse.dart';

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

  // ===== MOD BEGIN: 分享接收 / 闹钟（实现见 lib/mod/home_mod_hooks.dart）=====
  late final HomeModHooks _modHooks = HomeModHooks(
    jumpToTaskTab: () => _pageController.jumpToPage(1),
  );
  // ===== MOD END =====
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

    // 以下复刻 CupertinoTabScaffold（resizeToAvoidBottomInset: true）的布局逻辑：
    // 键盘高度转为内容 Padding 并从子 MediaQuery 移除；本应用标签栏为半透明
    // （alpha 0.5），栏高只注入 MediaQuery.padding，内容延伸到栏后方由各页
    // SafeArea 自行避让
    final MediaQueryData existingMediaQuery = MediaQuery.of(context);
    MediaQueryData newMediaQuery =
        existingMediaQuery.removeViewInsets(removeBottom: true);
    final EdgeInsets contentPadding =
        EdgeInsets.only(bottom: existingMediaQuery.viewInsets.bottom);

    // 键盘完全盖住标签栏时不再为栏高留白
    if (tabBar.preferredSize.height > existingMediaQuery.viewInsets.bottom) {
      final double bottomPadding =
          tabBar.preferredSize.height + existingMediaQuery.padding.bottom;
      newMediaQuery = newMediaQuery.copyWith(
        padding: newMediaQuery.padding.copyWith(bottom: bottomPadding),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: CupertinoTheme.of(context).scaffoldBackgroundColor,
      ),
      child: Stack(
        children: [
          // 内容在下层，半透明标签栏的 BackdropFilter 才有内容可模糊
          MediaQuery(
            data: newMediaQuery,
            child: Padding(padding: contentPadding, child: content),
          ),
          // 标签栏放在修改后的 MediaQuery 之外，读原始 viewPadding 计算安全区
          MediaQuery.withNoTextScaling(
            child: Align(alignment: Alignment.bottomCenter, child: tabBar),
          ),
        ],
      ),
    );
  }

  Future<void> initFuse() async {
    await Future.delayed(const Duration(seconds: 1));
    var fuse = Get.find<Rx<Fuse>>(tag: 'fuse');
    var update =
        await fuse.value.checkUpdate().whenComplete(() => fuse.refresh());
    if (update == null) return;
    if (!mounted) return;

    // 大版本 → 强制更新：没有「忽略」，只能去下载（或退出应用）。
    // 小版本 → 普通提醒，可忽略；同一个版本只提醒一次（由 Fuse 记录）。
    showCupertinoDialog(
        context: context,
        barrierDismissible: !update.forced,
        builder: (context) {
          return CupertinoAlertDialog(
            title: Text(update.forced ? '需要更新后才能继续使用' : '更新可用'),
            content: Text(
              update.forced
                  ? '当前版本 ${Fuse.appVersionName} 已经太旧，'
                      '请更新到 ${update.tag}。\n\n${update.summary}'
                  : update.message,
            ),
            actions: [
              if (!update.forced)
                CupertinoDialogAction(
                  child: const Text('忽略'),
                  onPressed: () async {
                    Navigator.of(context).pop();
                  },
                ),
              if (update.forced)
                CupertinoDialogAction(
                  child: const Text('退出'),
                  onPressed: () => SystemNavigator.pop(),
                ),
              CupertinoDialogAction(
                isDefaultAction: true,
                child: const Text('去下载'),
                onPressed: () async {
                  // 打开**实际回答的那个源**的 Release 页：
                  // 国内用户多半连不上 GitHub；如果这次是 Gitee 查到的更新，
                  // 就必须跳 Gitee —— 否则他看得到更新却打不开下载页。
                  await launchUrlString(
                    update.downloadUrl,
                    mode: LaunchMode.externalApplication,
                  );
                  // 强制更新时对话框留着，装完新版本自然会消失
                  if (!update.forced && context.mounted) {
                    Navigator.of(context).pop();
                  }
                },
              ),
            ],
          );
        });
  }
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
