import 'package:celechron/page/desktop/desktop_nav_rail.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

/// 桌面端左上角竖导航（v1.5.0）。
///
/// 为什么要单测这条导航：
/// 1. 它是用户拍板的桌面布局核心（左上角竖列 + 正中间功能页），点错了整页就走偏；
/// 2. **序号必须与手机端底部标签严格一致** —— 教程的"去试试"、分享进来要跳待办、
///    专注结束要跳专注页，全都靠 `jumpToTab(index)` 这个整数，
///    两端顺序一旦不一致，这些跳转会全部跳错页面（而且是那种"看起来都能用"的错误）。
void main() {
  test('导航项的顺序 = 手机端底部标签的顺序', () {
    expect(
      DesktopNavRail.items.map((item) => item.label).toList(),
      <String>['日程', '待办', '专注', '学业', '设置'],
    );
  });

  testWidgets('点某一项会回调它的序号', (WidgetTester tester) async {
    var selected = -1;
    await tester.pumpWidget(CupertinoApp(
      home: DesktopNavRail(index: 0, onSelect: (int i) => selected = i),
    ));
    await tester.tap(find.text('设置'));
    expect(selected, 4);
  });

  testWidgets('每一项都点得到（不会有点不动的格子）', (WidgetTester tester) async {
    final tapped = <int>[];
    await tester.pumpWidget(CupertinoApp(
      home: DesktopNavRail(index: 0, onSelect: tapped.add),
    ));
    for (final item in DesktopNavRail.items) {
      await tester.tap(find.text(item.label));
      await tester.pump();
    }
    expect(tapped, <int>[0, 1, 2, 3, 4]);
  });

  testWidgets('标签和图标都画出来了，宽度可配', (WidgetTester tester) async {
    await tester.pumpWidget(CupertinoApp(
      home: DesktopNavRail(index: 2, onSelect: (_) {}, width: 240),
    ));
    for (final item in DesktopNavRail.items) {
      expect(find.text(item.label), findsOneWidget);
    }
    final container = tester.widget<Container>(find
        .descendant(
          of: find.byType(DesktopNavRail),
          matching: find.byType(Container),
        )
        .first);
    expect((container.constraints?.maxWidth ?? 240), 240);
  });
}
