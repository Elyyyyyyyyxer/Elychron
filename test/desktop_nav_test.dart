import 'package:celechron/page/desktop/desktop_nav.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

/// 桌面端侧边栏切页（v1.5.0）。
///
/// 用户反馈：「当处于非主页面的某个页面时，点击侧边栏的另外一个页面，无法正常进行切换。」
///
/// 原因：左侧导航栏挂在根 Navigator **外面**（这样 push 二级页面时它不会被盖住），
/// 而二级页面只盖住右边的内容区 —— 用户点侧边栏时"看得见导航栏，点了却没反应"：
/// 新选的主页面在二级页面**下面**。所以切页时必须先把二级页面退掉。
///
/// 这里用注入的 navigator 把这条口径钉死（真机上靠肉眼验太容易漏）。
void main() {
  testWidgets('切换主页面时会把压在上面的二级页面退掉', (WidgetTester tester) async {
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(CupertinoApp(
      navigatorKey: key,
      home: Builder(
        builder: (BuildContext context) => CupertinoButton(
          onPressed: () => Navigator.of(context).push(
            CupertinoPageRoute<void>(
              builder: (BuildContext context) => const Text('二级页面'),
            ),
          ),
          child: const Text('进去'),
        ),
      ),
    ));
    await tester.tap(find.text('进去'));
    await tester.pumpAndSettle();
    expect(find.text('二级页面'), findsOneWidget);
    expect(key.currentState!.canPop(), isTrue, reason: '先确认真的压了一层');

    DesktopNav.goAndPop(3, navigator: key.currentState);

    await tester.pumpAndSettle();
    expect(key.currentState!.canPop(), isFalse, reason: '二级页面应该被退掉');
    expect(find.text('二级页面'), findsNothing);
    expect(DesktopNav.index.value, 3, reason: '同时要切到选中的那个主页面');

    DesktopNav.go(0);
  });

  test('序号越界时什么都不做', () {
    DesktopNav.go(2);
    DesktopNav.goAndPop(99);
    expect(DesktopNav.index.value, 2);
    DesktopNav.goAndPop(-1);
    expect(DesktopNav.index.value, 2);
    DesktopNav.go(0);
  });
}
