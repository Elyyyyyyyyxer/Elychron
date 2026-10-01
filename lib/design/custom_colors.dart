import 'package:celechron/design/app_accent.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// ===== 课程卡片色板（2026-10-01）=====
///
/// 用户要求：「课程底色的颜色改成粉色」。
///
/// 原来课表卡片的底色是写死的那个蓝（会话卡片 constructor 的默认值），
/// 跟 App 的粉色主题完全不搭。现在所有课程卡片统一走粉色系：
/// 底色围绕 AppAccent.primary 取，但**按课程 id 分档**
/// （色相 ±6°、饱和 ±、明度 0.62~0.70）——
/// 同一门课每次都是同一个颜色，相邻的课又不会糊成一片。
///
/// 2026-10-01 第二版：用户反馈「粉色有点太深了……稍微浅一点明亮一点」，
/// 于是明度从 0.55~0.65 抬到 0.62~0.70、饱和度也抬一点（更亮）。
/// 上限压在 0.70：再浅就发灰发白，卡片上的白字就读不动了。
class CoursePalette {
  CoursePalette._();

  static Color of(String? courseId) {
    final seed = (courseId ?? '').hashCode & 0x7fffffff;
    final base = HSLColor.fromColor(AppAccent.primary);
    final hue = (base.hue + ((seed % 5) - 2) * 3.0) % 360;
    final saturation = 0.78 + ((seed ~/ 5) % 2) * 0.08;
    final lightness = 0.62 + ((seed ~/ 10) % 3) * 0.04;
    return HSLColor.fromAHSL(1.0, hue, saturation, lightness).toColor();
  }
}

class UidColors {
  static Color colorFromUid(String? uid) {
    int value = (uid ?? '').hashCode;
    return HSLColor.fromAHSL(
            1.0,
            (20 + (value * 19 + 133) % 310),
            (80 + (value * 17 + 155) % 20) / 100.00,
            (60 + (value * 13 + 494) % 20) / 100.00)
        .toColor();
  }
}

class TimeColors {
  static Color colorFromHour(int hour) {
    Color color = Colors.red;
    if (hour <= 8) {
      color = Colors.red;
    } else if (hour >= 9 && hour <= 12) {
      color = Colors.amber;
    } else if (hour == 13) {
      color = const Color.fromARGB(255, 163, 232, 0);
    } else if (hour >= 14 && hour <= 15) {
      color = Colors.green;
    } else if (hour >= 16 && hour <= 17) {
      color = Colors.lightBlue;
    } else if (hour >= 18 && hour <= 19) {
      color = const Color.fromARGB(255, 38, 0, 255);
    } else if (hour >= 20) {
      color = const Color.fromARGB(255, 195, 0, 255);
    }
    return color;
  }

  static Color colorFromClass(int number) {
    Color color = Colors.red;
    if (number <= 1) {
      color = Colors.red;
    } else if (number >= 2 && number <= 5) {
      color = Colors.amber;
    } else if (number == 6) {
      color = const Color.fromARGB(255, 163, 232, 0);
    } else if (number >= 7 && number <= 8) {
      color = Colors.green;
    } else if (number >= 9 && number <= 10) {
      color = Colors.lightBlue;
    } else if (number >= 11 && number <= 12) {
      color = const Color.fromARGB(255, 38, 0, 255);
    } else if (number >= 13) {
      color = const Color.fromARGB(255, 195, 0, 255);
    }
    return color;
  }
}

class CustomCupertinoDynamicColors {
  static const CupertinoDynamicColor spring =
      CupertinoDynamicColor.withBrightness(
    color: Color.fromRGBO(230, 255, 226, 1.0),
    darkColor: Color.fromRGBO(147, 251, 56, 1.0),
  );

  static const CupertinoDynamicColor summer =
      CupertinoDynamicColor.withBrightness(
    color: Color.fromRGBO(255, 218, 238, 1.0),
    darkColor: Color.fromRGBO(255, 25, 69, 1.0),
  );

  static const CupertinoDynamicColor autumn =
      CupertinoDynamicColor.withBrightness(
    color: Color.fromRGBO(255, 234, 230, 1.0),
    darkColor: Color.fromRGBO(255, 101, 56, 1.0),
  );

  static const CupertinoDynamicColor winter =
      CupertinoDynamicColor.withBrightness(
    color: Color.fromRGBO(226, 239, 255, 1.0),
    darkColor: Color.fromRGBO(0, 183, 251, 1.0),
  );

  static const CupertinoDynamicColor violet =
      CupertinoDynamicColor.withBrightness(
    color: Color.fromRGBO(230, 229, 255, 1.0),
    darkColor: Color.fromRGBO(151, 131, 216, 1.0),
  );

  static const CupertinoDynamicColor sakura =
      CupertinoDynamicColor.withBrightness(
    color: Color.fromRGBO(255, 226, 255, 1.0),
    darkColor: Color.fromRGBO(218, 130, 217, 1.0),
  );

  static const CupertinoDynamicColor sand =
      CupertinoDynamicColor.withBrightness(
    color: Color.fromRGBO(255, 246, 211, 1.0),
    darkColor: Color.fromRGBO(252, 222, 59, 1.0),
  );

  static const CupertinoDynamicColor cyan =
      CupertinoDynamicColor.withBrightness(
    color: Color.fromRGBO(218, 234, 255, 1.0),
    darkColor: Color.fromRGBO(0, 140, 255, 1.0),
  );

  static const CupertinoDynamicColor magenta =
      CupertinoDynamicColor.withBrightness(
    color: Color.fromRGBO(230, 229, 255, 1.0),
    darkColor: Color.fromRGBO(238, 55, 161, 1.0),
  );

  static const CupertinoDynamicColor peach =
      CupertinoDynamicColor.withBrightness(
    color: Color.fromRGBO(255, 235, 226, 1.0),
    darkColor: Color.fromRGBO(233, 114, 70, 1.0),
  );

  static const CupertinoDynamicColor okGreen =
      CupertinoDynamicColor.withBrightness(
    color: Color.fromRGBO(230, 255, 226, 1.0),
    darkColor: Color.fromRGBO(63, 222, 23, 1.0),
  );
}
