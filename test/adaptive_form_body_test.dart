import 'package:celechron/design/adaptive_form_body.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('task form stays readable and retains input across resize',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(tester.view.reset);
    try {
      tester.view.physicalSize = const Size(1100, 800);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(CupertinoApp(
        home: CupertinoPageScaffold(
          child: SafeArea(
            child: AdaptiveFormBody(
              child: ListView(
                key: const Key('form'),
                children: const [CupertinoTextField(key: Key('title'))],
              ),
            ),
          ),
        ),
      ));

      final wideRect = tester.getRect(find.byKey(const Key('form')));
      expect(wideRect.width, lessThanOrEqualTo(720));
      expect((wideRect.center.dx - 550).abs(), lessThan(1));
      expect(wideRect.height, greaterThan(700));

      await tester.enterText(find.byKey(const Key('title')), '保留这段输入');
      tester.view.physicalSize = const Size(500, 800);
      await tester.pump();
      expect(
          tester.getRect(find.byKey(const Key('form'))).width, closeTo(500, 1));
      expect(find.text('保留这段输入'), findsOneWidget);

      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      await tester.pump();
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
