import 'package:flutter/cupertino.dart';

/// 闹钟配色预设：浅色 + 毛玻璃风格
class AlarmTheme {
  final String id;
  final String name;

  /// 主色（按钮 / 强调）
  final Color primary;

  /// 背景渐变色
  final Color backgroundStart;
  final Color backgroundEnd;

  /// 毛玻璃卡片的底色（半透明）
  final Color glass;
  final Color text;

  const AlarmTheme({
    required this.id,
    required this.name,
    required this.primary,
    required this.backgroundStart,
    required this.backgroundEnd,
    required this.glass,
    required this.text,
  });
}

/// 天依蓝取自「天依蓝」标准色 #66CCFF；爱莉粉取爱莉希雅标志性柔粉。
const List<AlarmTheme> kAlarmThemes = [
  AlarmTheme(
    id: 'tianyi',
    name: '天依蓝',
    primary: Color(0xFF66CCFF),
    backgroundStart: Color(0xFFE8F7FF),
    backgroundEnd: Color(0xFFBFE7FF),
    glass: Color(0x99FFFFFF),
    text: Color(0xFF12354A),
  ),
  AlarmTheme(
    id: 'elysia',
    name: '爱莉粉',
    primary: Color(0xFFFFA6C9),
    backgroundStart: Color(0xFFFFEFF5),
    backgroundEnd: Color(0xFFFFCFE0),
    glass: Color(0x99FFFFFF),
    text: Color(0xFF4A1E31),
  ),
  AlarmTheme(
    id: 'fresh',
    name: '清新绿',
    primary: Color(0xFF6FD8A6),
    backgroundStart: Color(0xFFEAFBF3),
    backgroundEnd: Color(0xFFBFEED8),
    glass: Color(0x99FFFFFF),
    text: Color(0xFF123A28),
  ),
  AlarmTheme(
    id: 'purple',
    name: '静谧紫',
    primary: Color(0xFFB39DDB),
    backgroundStart: Color(0xFFF2EEFB),
    backgroundEnd: Color(0xFFDCD0F5),
    glass: Color(0x99FFFFFF),
    text: Color(0xFF2A1E45),
  ),
];

AlarmTheme alarmThemeOf(String? id) {
  for (final theme in kAlarmThemes) {
    if (theme.id == id) return theme;
  }
  return kAlarmThemes.first;
}
