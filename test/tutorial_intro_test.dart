import 'package:celechron/tutorial/tutorial_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// 第一次打开 App 的教程引导（2026-09-17 用户要求）：
/// 「没打开过教程的 app 第一次打开默认弹出一个弹窗，引导进入教程」。
///
/// 这里锁的是"该不该弹"的判据 —— 纯逻辑，不需要数据库。
/// 重点是**别打扰老用户**：看过任何一篇、或进过教程中心，都不弹。
void main() {
  test('全新用户：没弹过、没进过教程中心、没看过 → 弹', () {
    expect(
      TutorialStore.shouldShowIntro(
        alreadyPrompted: false,
        openedCenter: false,
        seenAny: false,
      ),
      isTrue,
    );
  });

  test('看过任何一篇教程 → 不弹（老用户别被打扰）', () {
    expect(
      TutorialStore.shouldShowIntro(
        alreadyPrompted: false,
        openedCenter: false,
        seenAny: true,
      ),
      isFalse,
    );
  });

  test('进过教程中心 → 不弹', () {
    expect(
      TutorialStore.shouldShowIntro(
        alreadyPrompted: false,
        openedCenter: true,
        seenAny: false,
      ),
      isFalse,
    );
  });

  test('已经弹过一次 → 不再弹（哪怕当时选了以后再说）', () {
    expect(
      TutorialStore.shouldShowIntro(
        alreadyPrompted: true,
        openedCenter: false,
        seenAny: false,
      ),
      isFalse,
    );
  });

  test('三个条件全中 → 也不弹', () {
    expect(
      TutorialStore.shouldShowIntro(
        alreadyPrompted: true,
        openedCenter: true,
        seenAny: true,
      ),
      isFalse,
    );
  });
}
