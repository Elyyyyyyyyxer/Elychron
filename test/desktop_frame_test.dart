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

  testWidgets('很宽的窗口：内容不超过绝对上限，且居中', (WidgetTester tester) async {
    await pumpFrame(tester, const Size(2400, 900));
    final content =
        tester.getRect(find.byKey(const ValueKey<String>('content')));
    expect(content.width, lessThanOrEqualTo(DesktopFrame.contentMaxWidth + 1),
        reason: '超宽窗口由绝对上限兜底');
    final rail = tester.getRect(find.byType(DesktopNavRail));
    final leftGap = content.left - rail.right;
    final rightGap = 2400 - content.right;
    expect((leftGap - rightGap).abs(), lessThan(2), reason: '内容居中');
  });

  testWidgets('用户那种中等窗口也要看得出限宽（按比例，不是只靠绝对上限）', (WidgetTester tester) async {
    // 用户实测窗口约 700 逻辑像素宽（150% 缩放下的 1050 物理像素）
    await pumpFrame(tester, const Size(1000, 700));
    final rail = tester.getRect(find.byType(DesktopNavRail));
    final content =
        tester.getRect(find.byKey(const ValueKey<String>('content')));
    final available = 1000 - rail.width;
    final expected = DesktopFrame.contentWidthFor(available);
    expect(content.width, closeTo(expected, 1),
        reason: '内容区 = min(绝对上限, 可用宽度 × 0.72)');
    expect(content.width, lessThan(available - 40),
        reason: '两侧要真的留出空隙，不能跟没限一样');
  });

  testWidgets('窗口很窄时不会把内容挤没', (WidgetTester tester) async {
    await pumpFrame(tester, const Size(620, 600));
    final content =
        tester.getRect(find.byKey(const ValueKey<String>('content')));
    expect(content.width, greaterThan(200), reason: '再窄也得有可用的内容宽度');
  });
}
