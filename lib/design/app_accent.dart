import 'package:flutter/cupertino.dart';

/// ============ 主题色（全 App 唯一来源）============
///
/// 以前品牌粉是硬编码在各处的（`const Color(0xFFFF699A)` 散在 8 个文件 16 处），
/// 想换主题色就得满仓库搜。现在**所有界面颜色都从这里取**。
///
/// ## 为什么是 getter 而不是 `const`
///
/// 这是刻意为主题色设置留的位置：将来在设置里换色，只需要调用
/// [configure]（或把 [primary] 接到设置项上），**调用点一行都不用改**。
/// 用 `const` 常量就做不到这一点， 那种写法在切到运行时换色时，
/// 每一处 `const` 上下文都会编译报错，等于要把 16 处再改一遍。
///
/// 代价：不能再放进 `const` 表达式里（例如 `const TextStyle(color: AppAccent.primary)`
/// 要写成 `TextStyle(color: AppAccent.primary)`）。值得。
///
/// ## 现在还没做的部分
///
/// **本版不提供主题色设置界面**，只有这一个统一入口。[resetToDefault] 与
/// [configure] 已经写好并可用，将来加设置只需要接上 UI + 持久化。
class AppAccent {
  AppAccent._();

  /// 默认主色：爱莉希雅粉
  static const Color defaultPrimary = Color(0xFFFF699A);

  static Color _primary = defaultPrimary;
  static Color _light = const Color(0xFFFF8FB3);
  static Color _deep = const Color(0xFFE0356F);
  static Color _text = const Color(0xFFB8285C);

  /// 主色：按钮底色、图标、选中态、课程色条……
  static Color get primary => _primary;

  /// 主色浅端：渐变（大圆按钮等）用
  static Color get primaryLight => _light;

  /// 主色深端：渐变另一端、按下态
  static Color get primaryDeep => _deep;

  /// 主按钮上的文字与图标色
  static Color get onPrimary => const Color(0xFFFFFFFF);

  /// 浅色背景上的主色**文字**（例如数值、标签）。
  ///
  /// 注意与 [primary] 区分：纯主色当文字用对比度不够（白底上约 3.7:1），
  /// 所以文字用这个压深过的版本（约 5:1）。深色模式下由调用点自行取亮色。
  static Color get primaryText => _text;

  /// 主色的淡化版（选中态背景、光晕等）
  static Color soft(double opacity) => _primary.withValues(alpha: opacity);

  /// 换主题色：只给主色，浅端/深端/文字色按 HSL 自动推出来。
  ///
  /// **将来主题色设置就调这个**，然后让界面重建即可。
  static void configure(Color primary) {
    _primary = primary;
    final hsl = HSLColor.fromColor(primary);
    _light =
        hsl.withLightness((hsl.lightness + 0.12).clamp(0.0, 1.0)).toColor();
    _deep = hsl.withLightness((hsl.lightness - 0.16).clamp(0.0, 1.0)).toColor();
    _text = hsl.withLightness((hsl.lightness - 0.24).clamp(0.0, 1.0)).toColor();
  }

  /// 恢复默认（爱莉希雅粉）
  static void resetToDefault() {
    _primary = defaultPrimary;
    _light = const Color(0xFFFF8FB3);
    _deep = const Color(0xFFE0356F);
    _text = const Color(0xFFB8285C);
  }
}
