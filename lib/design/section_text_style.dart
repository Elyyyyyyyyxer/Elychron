import 'package:flutter/cupertino.dart';

/// ===== 分组列表的「标题 / 脚注」统一样式 =====
///
/// 为什么需要它：CupertinoListSection.insetGrouped 默认拿 textTheme.textStyle
/// （17pt、正文色）当标题和脚注 —— 于是分组标题比卡片里的列表项本身还抢眼，
/// 整页看起来"又黑又乱"，而且跟设置页的分组对不上。真机上就是这么发现的
/// （mod/webdav_settings_page.dart 里那句注释记的就是这件事）。
///
/// 这个值**照抄设置页**（page/option/option_view.dart）与同步页用的那一份：
/// 13pt + 系统灰。几处必须一样，否则同一台手机上两个页面的分组标题
/// 字号 / 颜色会差一点点 —— 用户看得出来。
///
/// 用法：给 insetGrouped 传
///   header: sectionHeader(context, '开关')
///   footer: sectionFooter(context, '……')
const Color kSectionHeaderFooterColor = CupertinoDynamicColor(
  color: Color.fromRGBO(108, 108, 108, 1.0),
  darkColor: Color.fromRGBO(142, 142, 146, 1.0),
  highContrastColor: Color.fromRGBO(74, 74, 77, 1.0),
  darkHighContrastColor: Color.fromRGBO(176, 176, 183, 1.0),
  elevatedColor: Color.fromRGBO(108, 108, 108, 1.0),
  darkElevatedColor: Color.fromRGBO(142, 142, 146, 1.0),
  highContrastElevatedColor: Color.fromRGBO(108, 108, 108, 1.0),
  darkHighContrastElevatedColor: Color.fromRGBO(142, 142, 146, 1.0),
);

TextStyle sectionHeaderFooterStyle(BuildContext context) =>
    CupertinoTheme.of(context).textTheme.textStyle.merge(TextStyle(
      fontSize: 13.0,
      color: CupertinoDynamicColor.resolve(kSectionHeaderFooterColor, context),
    ));

Widget sectionHeader(BuildContext context, String text) => Container(
      padding: const EdgeInsets.only(left: 16),
      child: Text(text, style: sectionHeaderFooterStyle(context)),
    );

Widget sectionFooter(BuildContext context, String text) => Container(
      padding: const EdgeInsets.only(left: 16),
      child: Text(text, style: sectionHeaderFooterStyle(context)),
    );
