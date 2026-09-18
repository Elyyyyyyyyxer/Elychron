import 'package:celechron/design/app_accent.dart';
import 'package:celechron/mod/home_mod_hooks.dart';
import 'package:celechron/mod/update_prompt.dart';
import 'package:celechron/page/desktop/desktop_nav_rail.dart';
import 'package:celechron/page/calendar/calendar_view.dart';
import 'package:celechron/page/focus/focus_home_page.dart';
import 'package:celechron/page/option/option_view.dart';
import 'package:celechron/page/scholar/scholar_view.dart';
import 'package:celechron/page/task/task_view.dart';
import 'package:celechron/utils/share_receiver.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/cupertino.dart';

/// ===== 桌面端主界面（v1.5.0）=====
///
/// 用户拍板：「桌面布局重新设计，当然也是分页面。左上角排一个竖列的导航栏，
/// 正中间大面积的都是功能页面」「分享进来改用拖动文件」。
///
/// 所以这里和手机端（底部 CupertinoTabBar + PageView）是**两套壳**，里面装的页
/// 完全一样（CalendarPage / TaskPage / FocusHomePage / ScholarPage / OptionPage），
/// 一行业务逻辑都不重写：
/// - 左边一条竖导航（图标 + 文字，选中态用主题色），
/// - 右边是内容区，占满剩下的空间（IndexedStack 保证切页不丢状态），
/// - 整个窗口是拖放目标：把文件拖进来 = 手机上"从别的应用分享进来"，
///   走的是同一条管线（home_mod_hooks.acceptDroppedFiles）。
class DesktopShell extends StatefulWidget {
  const DesktopShell({super.key});

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  int _index = 0;
  bool _dragging = false;

  /// 导航栏宽度：够放"图标 + 四个字"的标签，又不至于把内容区挤窄
  static const double _railWidth = 208;

  // 与手机端一样只构造一次：切页时不会重跑各页构造器里的 Get.put
  late final List<Widget> _pages = <Widget>[
    CalendarPage(),
    TaskPage(),
    FocusHomePage(),
    ScholarPage(),
    OptionPage(),
  ];

  // 分享 / 闹钟 / 教程跳转这套钩子两端共用；桌面上"跳标签"就是换 _index
  late final HomeModHooks _modHooks = HomeModHooks(
    jumpToTaskTab: () => _jumpTo(1),
    jumpToTab: _jumpTo,
  );

  void _jumpTo(int index) {
    if (index < 0 || index >= DesktopNavRail.items.length) return;
    if (!mounted) return;
    setState(() => _index = index);
  }

  @override
  void initState() {
    super.initState();
    _modHooks.start();
    // 更新检查与手机端共用同一套（lib/mod/update_prompt.dart）
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
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      child: DropTarget(
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
          // 拖进来的文件按"分享"处理：复制到附件目录 → 问新建还是挂到已有待办
          final items = <SharedItem>[
            for (final file in details.files)
              SharedItem(path: file.path, name: file.name),
          ];
          if (items.isNotEmpty) await _modHooks.acceptDroppedFiles(items);
        },
        child: Stack(
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                DesktopNavRail(
                  index: _index,
                  onSelect: _jumpTo,
                  width: _railWidth,
                ),
                Expanded(
                  child: IndexedStack(
                    index: _index,
                    children: _pages,
                  ),
                ),
              ],
            ),
            if (_dragging) _dropHint(context),
          ],
        ),
      ),
    );
  }

  /// 拖着文件悬在窗口上时的提示（松手就进待办）
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
