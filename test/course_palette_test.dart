import 'package:celechron/design/app_accent.dart';
import 'package:celechron/design/custom_colors.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

/// 课程卡片底色（2026-10-01）：用户要求「课程底色的颜色改成粉色」。
/// 这几条钉的就是"确实是粉"和"相邻的课还分得开"。
void main() {
  test('同一门课永远是同一个颜色', () {
    for (final id in <String>['a', 'b', 'course-1', '2026-spring-001', '']) {
      expect(CoursePalette.of(id), CoursePalette.of(id), reason: id);
    }
  });

  test('所有颜色都在粉色范围内（色相贴着主题粉 ±6°，明度够白字看清）', () {
    final base = HSLColor.fromColor(AppAccent.primary);
    for (var i = 0; i < 200; i++) {
      final color = CoursePalette.of('id-' + i.toString());
      final hsl = HSLColor.fromColor(color);
      var delta = (hsl.hue - base.hue).abs();
      if (delta > 180) delta = 360 - delta;
      expect(delta <= 6.5, isTrue, reason: 'id-' + i.toString());
      expect(hsl.lightness >= 0.60 && hsl.lightness <= 0.72, isTrue,
          reason: 'id-' + i.toString());
      expect(hsl.saturation >= 0.74, isTrue, reason: 'id-' + i.toString());
    }
  });

  test('相邻的课不会糊成一片（颜色够分散）', () {
    final colors = <Color>{
      for (var i = 0; i < 30; i++)
        CoursePalette.of('course-' + i.toString()),
    };
    expect(colors.length >= 8, isTrue,
        reason: '只有 ' + colors.length.toString() + ' 种颜色');
  });
}
