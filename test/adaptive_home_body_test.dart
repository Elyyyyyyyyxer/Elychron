import 'package:celechron/page/desktop/desktop_nav_rail.dart';
import 'package:celechron/page/tablet/adaptive_home_body.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

class _PageProbe extends StatefulWidget {
  const _PageProbe();

  @override
  State<_PageProbe> createState() => _PageProbeState();
}

class _PageProbeState extends State<_PageProbe> {
  @override
  Widget build(BuildContext context) =>
      const SizedBox.expand(key: ValueKey('page-content'));
}

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  Future<void> pumpShell(
    WidgetTester tester, {
    required double width,
    required TargetPlatform platform,
    int selectedIndex = 0,
    ValueChanged<int>? onSelect,
  }) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    debugDefaultTargetPlatformOverride = platform;
    final bottomBar = CupertinoTabBar(
      currentIndex: selectedIndex,
      onTap: onSelect,
      items: const [
        BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.calendar), label: '日程'),
        BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.check_mark), label: '待办'),
        BottomNavigationBarItem(icon: Icon(CupertinoIcons.timer), label: '专注'),
        BottomNavigationBarItem(icon: Icon(CupertinoIcons.book), label: '学业'),
        BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.settings), label: '设置'),
      ],
    );
    await tester.pumpWidget(CupertinoApp(
      home: AdaptiveHomeBody(
        content: const _PageProbe(),
        bottomBar: bottomBar,
        selectedIndex: selectedIndex,
        onSelect: onSelect ?? (_) {},
      ),
    ));
    await tester.pump();
  }

  testWidgets('iOS wide window uses a sidebar and bounds page width',
      (tester) async {
    addTearDown(tester.view.reset);
    await pumpShell(tester, width: 1200, platform: TargetPlatform.iOS);

    expect(find.byType(DesktopNavRail), findsOneWidget);
    expect(find.byType(CupertinoTabBar), findsNothing);
    expect(tester.getSize(find.byKey(const ValueKey('page-content'))).width,
        lessThanOrEqualTo(920));
    expect(find.text('把文件拖进窗口即可添加为待办附件'), findsNothing);
    expect(DesktopNavRail.items.map((item) => item.label).toList(),
        ['日程', '待办', '专注', '学业', '设置']);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('iOS switches navigation at 900 logical pixels', (tester) async {
    addTearDown(tester.view.reset);
    await pumpShell(tester, width: 899, platform: TargetPlatform.iOS);
    expect(find.byType(CupertinoTabBar), findsOneWidget);
    expect(find.byType(DesktopNavRail), findsNothing);

    await pumpShell(tester, width: 900, platform: TargetPlatform.iOS);
    expect(find.byType(DesktopNavRail), findsOneWidget);
    expect(find.byType(CupertinoTabBar), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('wide Android window keeps bottom tabs', (tester) async {
    addTearDown(tester.view.reset);
    await pumpShell(tester, width: 1200, platform: TargetPlatform.android);
    expect(find.byType(CupertinoTabBar), findsOneWidget);
    expect(find.byType(DesktopNavRail), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('resizing keeps page state and selected destination',
      (tester) async {
    addTearDown(tester.view.reset);
    var selected = 2;
    void select(int index) => selected = index;

    await pumpShell(tester,
        width: 1100,
        platform: TargetPlatform.iOS,
        selectedIndex: selected,
        onSelect: select);
    final originalState =
        tester.state<_PageProbeState>(find.byType(_PageProbe));
    await tester.tap(find.text('设置'));
    expect(selected, 4);

    await pumpShell(tester,
        width: 700,
        platform: TargetPlatform.iOS,
        selectedIndex: selected,
        onSelect: select);
    expect(tester.state<_PageProbeState>(find.byType(_PageProbe)),
        same(originalState));
    expect(
        tester
            .widget<CupertinoTabBar>(find.byType(CupertinoTabBar))
            .currentIndex,
        4);
    debugDefaultTargetPlatformOverride = null;
  });
}
