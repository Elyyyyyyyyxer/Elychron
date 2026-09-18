import 'package:celechron/page/desktop/desktop_frame.dart';
import 'package:celechron/page/desktop/desktop_nav.dart';
import 'package:celechron/page/desktop/desktop_nav_rail.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

/// 桌面端外框（v1.5.0）—— 用户提的两条布局要求都在这里：
/// 「1. 所有页面两侧留出约六分之一到七分之一的间隙」
/// 「4. 让所有的页面都存在侧边栏」
///
/// 这两条都是"看起来对不对"的事，用测试把数字与结构钉住，
/// 免得以后调样式时手一抖就没了。
void main() {
  Future<void> pumpFrame(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const CupertinoApp(
      home: DesktopFrame(
        child: ColoredBox(
            key: ValueKey<String>('content'), color: CupertinoColors.white),
      ),
    ));
    await tester.pump();
    // DesktopFrame 里挂着 HomeModHooks（分享/闹钟/教程跳转），它启动时会排一个
    // 3 秒的一次性定时器（补记账号密码）。测试不把时间走完的话，
    // 框架会以 "Pending timers" 判失败。
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
    expect(content.right, lessThanOrEqualTo(1400.5));
  });

  testWidgets('内容两侧各留 1/6 ~ 1/7 的宽度（用户要求）', (WidgetTester tester) async {
    const total = 1400.0;
    await pumpFrame(tester, const Size(total, 900));
    final railWidth = tester.getSize(find.byType(DesktopNavRail)).width;
    final contentWidth =
        tester.getSize(find.byKey(const ValueKey<String>('content'))).width;

    final side = (total - railWidth - contentWidth) / 2;
    final ratio = side / total;
    expect(ratio, greaterThan(1 / 7 - 0.005), reason: '不能比七分之一还窄');
    expect(ratio, lessThan(1 / 6 + 0.005), reason: '不能比六分之一还宽');
  });

  testWidgets('窗口窄的时候不硬留 1/6（否则中间只剩一条）', (WidgetTester tester) async {
    // 150% 缩放下 1120 物理像素只有 747 逻辑像素宽，这种宽度要按固定边距走
    await pumpFrame(tester, const Size(747, 700));
    final contentWidth =
        tester.getSize(find.byKey(const ValueKey<String>('content'))).width;
    final contentLeft =
        tester.getRect(find.byKey(const ValueKey<String>('content'))).left;
    expect(contentLeft, closeTo(208 + DesktopFrame.narrowSide, 1),
        reason: '窄窗口用固定边距');
    expect(contentWidth, greaterThan(747 * 0.5), reason: '内容区至少要占一半，不能挤成一条');
  });

  testWidgets('窗口越宽留白越多，但始终留得住（不是固定像素）', (WidgetTester tester) async {
    await pumpFrame(tester, const Size(1000, 800));
    final narrow =
        tester.getSize(find.byKey(const ValueKey<String>('content'))).width;
    await pumpFrame(tester, const Size(1800, 800));
    final wide =
        tester.getSize(find.byKey(const ValueKey<String>('content'))).width;
    expect(wide - narrow,
        closeTo((1800 - 1000) * (1 - 2 * DesktopFrame.sideRatio), 2),
        reason: '多出来的宽度按比例分给内容与留白');
  });
}
