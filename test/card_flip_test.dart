// `CardFlipSwitcher` 的结构 / 状态回归测试。
//
// 为什么不是 golden / 像素测试：本来想做**逐帧像素采样**（把每帧的卡片宽度、
// 页边灰度算出来），但 `flutter test` 是无 GPU 的软件渲染环境：
// `RenderRepaintBoundary.toImage()` 拿到的图像，`toByteData(rawRgba)` 与
// `toByteData(png)` **一律返回 null**（三条路都试过），像素探针在本机不可行。
// 所以这里留下的是**能在无 GPU 环境跑**、且真能兜住回归的结构断言：
//
//   1. 换 flipKey 才翻；只换 face 不翻（直接换面、不同时挂两个面）
//   2. 翻转中旧面在场、新面不在场；到 50% 处换面；翻完只剩新面
//   3. 页边（paper edge）只在可见角度窗口里出现，且挂在 Stack 里
//      （Stack 只做绘制，不给页面内容加任何约束 —— 这是不破坏布局的前提）
//   4. 整段翻转不出现布局异常
//   5. 透传参数不改变默认时序，且默认时长确实接到 AnimationController 上
//
//   D:\flutter\bin\flutter.bat test test/card_flip_test.dart
import 'package:celechron/design/card_flip.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

const Color kPageBg = Color(0xFFEEEEEE);
const double kW = 360;
const double kH = 640;

/// 和 `card_flip.dart` 保持一致的翻转时长，用来算 50% 那一帧。
const Duration kFlip = Duration(milliseconds: 620);

Future<void> pumpHarness(
  WidgetTester tester,
  ValueNotifier<int> flipKey,
  ValueNotifier<int> face,
) async {
  await tester.binding.setSurfaceSize(const Size(kW, kH));
  await tester.pumpWidget(
    CupertinoApp(
      debugShowCheckedModeBanner: false,
      home: ColoredBox(
        color: kPageBg,
        child: ValueListenableBuilder<int>(
          valueListenable: flipKey,
          builder: (BuildContext context, int key, _) =>
              ValueListenableBuilder<int>(
            valueListenable: face,
            builder: (BuildContext context, int f, _) => CardFlipSwitcher(
              flipKey: key,
              face: f,
              faceBuilder: (Object face) => ColoredBox(
                color: const Color(0xFFFFFFFF),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    // 故意放一个固定高度 + 一个 Expanded：触发"约束必须完整"
                    // 的那条路径（历史上用 loose Stack 会在 Expanded 上炸）
                    const SizedBox(height: 44),
                    Expanded(
                      child: Center(child: Text('face $face')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// 页边所在的那层：`Stack(paperEdge, card)`，只在 depth > 0.02 时出现。
/// 用「横向做了平移的 Transform」精确定位（卡片自身用的是 Transform.scale /
/// rotateY，横向平移恒为 0；只有页边那层会被推出去 `cos(angle)*3` 像素）。
Finder paperEdgeFinder() => find.byWidgetPredicate(
      (Widget w) => w is Transform && w.transform.getTranslation().x != 0,
    );

void main() {
  testWidgets('翻转：只在 flipKey 变化时换面，50% 处换面，结束后只剩新面',
      (WidgetTester tester) async {
    final ValueNotifier<int> flipKey = ValueNotifier<int>(0);
    final ValueNotifier<int> face = ValueNotifier<int>(0);
    addTearDown(flipKey.dispose);
    addTearDown(face.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpHarness(tester, flipKey, face);

    // 静止：只有当前面
    expect(find.text('face 0'), findsOneWidget);
    expect(find.text('face 1'), findsNothing);

    // 只换 face、不换 flipKey → 直接换面，不做动画、也不该出现两个面
    face.value = 1;
    await tester.pump();
    expect(find.text('face 1'), findsOneWidget);
    expect(find.text('face 0'), findsNothing);

    // 真正触发翻转：旧面（1）先在场，新面（2）还没上场
    face.value = 2;
    flipKey.value = 1;
    await tester.pump();
    expect(find.text('face 1'), findsOneWidget);
    expect(find.text('face 2'), findsNothing);

    // 不到 50%：仍然是旧面
    await tester.pump(kFlip * 0.3);
    expect(find.text('face 1'), findsOneWidget);
    expect(find.text('face 2'), findsNothing);

    // 过半：换成新面
    await tester.pump(kFlip * 0.21);
    expect(find.text('face 2'), findsOneWidget);
    expect(find.text('face 1'), findsNothing);

    // 结束：只剩新面，且不再有动画
    await tester.pumpAndSettle();
    expect(find.text('face 2'), findsOneWidget);
    expect(find.text('face 1'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('页边只在可见角度窗口里出现，且被裁在自己的矩形内（不加约束）', (WidgetTester tester) async {
    final ValueNotifier<int> flipKey = ValueNotifier<int>(0);
    final ValueNotifier<int> face = ValueNotifier<int>(0);
    addTearDown(flipKey.dispose);
    addTearDown(face.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpHarness(tester, flipKey, face);

    // 静止：没有页边层（depth == 0）
    expect(find.byType(ClipRect), findsNothing);
    expect(paperEdgeFinder(), findsNothing);

    flipKey.value = 1;
    await tester.pump();

    // 刚开始（t≈0.25）：已经转到侧面附近，页边层应当在场
    await tester.pump(kFlip * 0.25);
    expect(paperEdgeFinder(), findsOneWidget);
    // 页边层必须挂在 Stack 里（Stack 只做绘制，不给页面内容加约束）
    expect(find.byType(Stack), findsWidgets);
    expect(tester.takeException(), isNull);

    // 侧面附近（t≈0.5）：仍然在场
    await tester.pump(kFlip * 0.25);
    expect(paperEdgeFinder(), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 收尾：页边退场，不留残留
    await tester.pumpAndSettle();
    expect(paperEdgeFinder(), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('默认时序仍是 620ms 两段式换面，透传 duration 生效', (WidgetTester tester) async {
    final ValueNotifier<int> flipKey = ValueNotifier<int>(0);
    final ValueNotifier<int> face = ValueNotifier<int>(0);
    addTearDown(flipKey.dispose);
    addTearDown(face.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpHarness(tester, flipKey, face);

    // 默认时序：还没到 620ms（但要过半）时已经换成新面，说明确实在动画中换面
    face.value = 1;
    flipKey.value = 1;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 330)); // 53%
    expect(find.text('face 1'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 翻完
    await tester.pumpAndSettle();
    expect(find.text('face 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('显式传 duration / curve 时行为与默认一致（不越界、不露背面）',
      (WidgetTester tester) async {
    final ValueNotifier<int> flipKey = ValueNotifier<int>(0);
    final ValueNotifier<int> face = ValueNotifier<int>(0);
    final ValueNotifier<Duration> duration =
        ValueNotifier<Duration>(const Duration(milliseconds: 300));
    addTearDown(flipKey.dispose);
    addTearDown(face.dispose);
    addTearDown(duration.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.binding.setSurfaceSize(const Size(kW, kH));
    await tester.pumpWidget(
      CupertinoApp(
        debugShowCheckedModeBanner: false,
        home: ColoredBox(
          color: kPageBg,
          child: ValueListenableBuilder<int>(
            valueListenable: flipKey,
            builder: (BuildContext context, int key, _) =>
                ValueListenableBuilder<int>(
              valueListenable: face,
              builder: (BuildContext context, int f, _) =>
                  ValueListenableBuilder<Duration>(
                valueListenable: duration,
                builder: (BuildContext context, Duration d, _) =>
                    CardFlipSwitcher(
                  flipKey: key,
                  face: f,
                  duration: d,
                  curve: Curves.easeInOutSine,
                  faceBuilder: (Object face) => ColoredBox(
                    color: const Color(0xFFFFFFFF),
                    child: Text('face $face'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    face.value = 1;
    flipKey.value = 1;
    await tester.pump();

    // 过半：已经换成新面
    await tester.pump(const Duration(milliseconds: 180)); // 300ms 的 60%
    expect(find.text('face 1'), findsOneWidget);

    // 超过总时长：动画必须收干净，不能停在中间
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('face 1'), findsOneWidget);
    expect(paperEdgeFinder(), findsNothing);
    expect(find.byType(ClipRect), findsNothing);
    expect(tester.takeException(), isNull);

    // 换一次 + 把时长改成 2000ms：AnimationController 只在 initState 读一次
    // duration，如果没在 didUpdateWidget 同步，这里会仍然按 300ms 跑 → 被抓住。
    face.value = 2;
    duration.value = const Duration(milliseconds: 2000);
    flipKey.value = 2;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // 2000ms 的动画在 400ms 时还没过半 → 仍然是旧面
    expect(find.text('face 1'), findsOneWidget);
    expect(find.text('face 2'), findsNothing);

    await tester.pumpAndSettle();
    expect(find.text('face 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
