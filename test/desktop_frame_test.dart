import 'package:celechron/page/desktop/desktop_frame.dart';
import 'package:celechron/page/desktop/desktop_nav.dart';
import 'package:celechron/page/desktop/desktop_nav_rail.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

/// 桌面端外框（v1.5.0）。
///
/// 布局口径改过一轮，这里记清楚为什么：
/// - 用户先嫌"一条被拉得很长" → 做成两侧按 1/6.5 留白；
/// - 用户又说"留了空隙更丑、有点割裂" → 改成**背景铺满、只把内容限宽居中**。
/// 所以现在的口径：导航栏在最左，右边是内容，内容宽度不超过 contentMaxWidth；
/// 窗口窄的时候内容直接铺满，不留多余边距。
void main() {
  Future<void> pumpFrame(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const CupertinoApp(
      home: DesktopFrame(
        // 必须让它"撑满被允许的空间"：真实应用里这里是根 Navigator（本来就会铺满），
        // 测试里用普通 ColoredBox 的话它会缩到最小，量出来的不是内容区宽度。
        child: ColoredBox(
          key: const ValueKey<String>('content'),
          color: CupertinoColors.white,
          child: const SizedBox.expand(),
        ),
      ),
    ));
    await tester.pump();
    // DesktopFrame 里挂着 HomeModHooks，启动时会排一个 3 秒的一次性定时器
    await tester.pump(const Duration(seconds: 4));
  }

  test('导航序号只会落在 0..4（越界当成没点）', () {
    DesktopNav.go(2);
    expect(DesktopNav.index.value, 2);
    DesktopNav.go(99);
    expect(DesktopNav.index.value, 2, reason: '越界不该改状态');
    DesktopNav.go(-1);
    expect(DesktopNav.index.value, 2);
    DesktopNav.go(0);
  });

  testWidgets('左侧有导航栏，内容区在它右边', (WidgetTester tester) async {
    await pumpFrame(tester, const Size(1400, 900));
    expect(find.byType(DesktopNavRail), findsOneWidget);

    final rail = tester.getRect(find.byType(DesktopNavRail));
    final content =
        tester.getRect(find.byKey(const ValueKey<String>('content')));
    expect(rail.left, 0, reason: '导航栏贴最左边');
    expect(content.left, greaterThanOrEqualTo(rail.right - 0.5),
        reason: '内容区在导航栏右侧，不重叠');
  });

  testWidgets('宽窗口下内容限宽居中（不会拉成一条）', (WidgetTester tester) async {
    await pumpFrame(tester, const Size(1800, 900));
    final content =
        tester.getRect(find.byKey(const ValueKey<String>('content')));
    expect(content.width, lessThanOrEqualTo(DesktopFrame.contentMaxWidth + 1),
        reason: '内容块不能超过限宽');
    final rail = tester.getRect(find.byType(DesktopNavRail));
    final leftGap = content.left - rail.right;
    final rightGap = 1800 - content.right;
    expect((leftGap - rightGap).abs(), lessThan(2), reason: '内容居中');
  });

  testWidgets('窄窗口下内容铺满（不留多余边距）', (WidgetTester tester) async {
    await pumpFrame(tester, const Size(900, 700));
    final rail = tester.getRect(find.byType(DesktopNavRail));
    final content =
        tester.getRect(find.byKey(const ValueKey<String>('content')));
    expect(content.left, closeTo(rail.right, 1), reason: '窄窗口不该再有"割裂"的留白');
    expect(content.right, closeTo(900, 1), reason: '右边也铺满');
  });
}
