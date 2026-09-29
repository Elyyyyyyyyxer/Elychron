import 'package:celechron/design/adaptive_sheet_frame.dart';
import 'package:celechron/design/dingtalk_sheet.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> showSheet(
    WidgetTester tester, {
    required double width,
    int optionCount = 2,
    double keyboardInset = 0,
  }) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = FakeViewPadding(bottom: keyboardInset);
    await tester.pumpWidget(CupertinoApp(
      home: Builder(builder: (context) {
        return CupertinoButton(
          onPressed: () => showDingTalkSheet<int>(
            context: context,
            title: '选择目标',
            options: [
              for (var i = 0; i < optionCount; i++)
                DingTalkSheetOption(label: '选项 $i', value: i),
            ],
          ),
          child: const Text('打开'),
        );
      }),
    ));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
  }

  testWidgets('wide iPad sheet is a centered card at most 560 wide',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(tester.view.reset);
    try {
      await showSheet(tester, width: 1100);
      expect(find.byType(AdaptiveSheetFrame), findsOneWidget);
      final cardRect = tester.getRect(find.byType(DingTalkSheetShell));
      expect(cardRect.width, lessThanOrEqualTo(560));
      expect((cardRect.center.dx - 550).abs(), lessThan(1));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('narrow iPad sheet keeps full phone width', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(tester.view.reset);
    try {
      await showSheet(tester, width: 500);
      expect(tester.getRect(find.byType(DingTalkSheetShell)).width,
          closeTo(500, 1));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('long iPad sheet scrolls options without hiding cancel',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(tester.view.reset);
    try {
      await showSheet(tester, width: 1100, optionCount: 30);
      expect(find.text('取消'), findsOneWidget);
      await tester.ensureVisible(find.text('选项 29'));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.text('取消')).bottom, lessThanOrEqualTo(800));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('keyboard does not cover wide iPad sheet cancel action',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(tester.view.reset);
    try {
      await showSheet(tester, width: 1100, keyboardInset: 320);
      expect(tester.getRect(find.text('取消')).bottom, lessThanOrEqualTo(480));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('sheet cancel stays reachable when keyboard stays open on resize',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(tester.view.reset);
    try {
      await showSheet(tester, width: 1100, keyboardInset: 320);
      tester.view.physicalSize = const Size(700, 800);
      await tester.pumpAndSettle();

      expect(tester.getRect(find.text('取消')).bottom, lessThanOrEqualTo(480));
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text('取消'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
