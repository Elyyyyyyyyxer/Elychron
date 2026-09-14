import 'package:celechron/design/app_accent.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

/// 主题色是**唯一来源**，而且已经为「主题色设置」留好了接口。
///
/// 这里锁两件事：
/// 1. 换主色之后，浅端 / 深端 / 文字色会自动推出来（不用逐个手调）；
/// 2. 能恢复默认（爱莉希雅粉），保证默认外观不会漂移。
void main() {
  tearDown(AppAccent.resetToDefault);

  test('默认就是爱莉希雅粉', () {
    expect(AppAccent.primary, AppAccent.defaultPrimary);
    expect(AppAccent.defaultPrimary, const Color(0xFFFF699A));
  });

  test('换主色后，浅端更亮、深端与文字色更暗', () {
    AppAccent.configure(const Color(0xFF3A7BD5));
    final base = HSLColor.fromColor(AppAccent.primary);
    expect(AppAccent.primary, const Color(0xFF3A7BD5));
    expect(HSLColor.fromColor(AppAccent.primaryLight).lightness,
        greaterThan(base.lightness));
    expect(HSLColor.fromColor(AppAccent.primaryDeep).lightness,
        lessThan(base.lightness));
    expect(HSLColor.fromColor(AppAccent.primaryText).lightness,
        lessThan(HSLColor.fromColor(AppAccent.primaryDeep).lightness));
  });

  test('resetToDefault 能把三个派生色一起还原', () {
    AppAccent.configure(const Color(0xFF00AA00));
    AppAccent.resetToDefault();
    expect(AppAccent.primary, AppAccent.defaultPrimary);
    expect(AppAccent.primaryLight, const Color(0xFFFF8FB3));
    expect(AppAccent.primaryDeep, const Color(0xFFE0356F));
    expect(AppAccent.primaryText, const Color(0xFFB8285C));
  });

  test('soft() 只是加透明度，不改变色相', () {
    final soft = AppAccent.soft(0.35);
    expect(soft.a, closeTo(0.35, 0.01));
    expect(soft.r, closeTo(AppAccent.primary.r, 0.01));
    expect(soft.g, closeTo(AppAccent.primary.g, 0.01));
    expect(soft.b, closeTo(AppAccent.primary.b, 0.01));
  });

  test('onPrimary 是不透明白（主按钮文字）', () {
    expect(AppAccent.onPrimary, const Color(0xFFFFFFFF));
  });
}
