import 'package:celechron/design/app_accent.dart';
import 'package:celechron/design/page_background.dart';
import 'package:celechron/design/section_text_style.dart';
import 'package:flutter/cupertino.dart';
import 'package:url_launcher/url_launcher_string.dart';

/// ===== 服务条款（2026-10-01 重做外观）=====
///
/// 原来这一页是"裸文字"：24pt 居中标题 + 18pt 正文 + 36pt 空行，
/// 跟 App 里其它页面（分组卡片 + 13pt 灰脚注）完全是两套语言，
/// 用户说它"还是老样式"。真机截图确认：整页就是四段大号黑字。
///
/// 改的是**外观**，不是内容：免责声明 / 责任限制两段法律原文
/// 一个字都没动（GPLv3 附录里那段中文译本），只是换成卡片 + 合适的行距，
/// 让它在 6.7 寸屏上读起来不费劲。
///
/// 顺带把"源码在哪"写清楚：GPLv3 第 6 条要求向拿到二进制的人提供源码获取方式，
/// 所以这一页必须能点进源码仓库，而不是只给一个协议全文链接。
class CustomLicensePage extends StatelessWidget {
  const CustomLicensePage({super.key});

  static const String _gplUrl = 'https://www.gnu.org/licenses/gpl-3.0.html';
  static const String _upstreamUrl = 'https://github.com/Celechron/Celechron';
  static const String _forkUrl = 'https://github.com/Elyyyyyyyyxer/Elychron';

  Future<void> _open(String url) async {
    try {
      await launchUrlString(url, mode: LaunchMode.externalApplication);
    } catch (_) {
      // 打不开浏览器就算了，地址本身已经写在界面上
    }
  }

  /// 法律原文：15pt + 1.6 行距。段内不换行、不缩进，靠行距撑开。
  Widget _paragraph(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 15,
            height: 1.6,
            color: CupertinoDynamicColor.resolve(CupertinoColors.label, context),
          ),
        ),
      );

  Widget _linkTile(String title, String url) => CupertinoListTile(
        title: Text(title),
        trailing: const Icon(CupertinoIcons.arrow_right,
            size: 18, color: CupertinoColors.tertiaryLabel),
        onTap: () => _open(url),
      );

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: pageBackground(context),
      navigationBar: const CupertinoNavigationBar(middle: Text('服务条款')),
      child: ListView(
        padding: EdgeInsets.only(
          top: 8,
          bottom: 24 + MediaQuery.of(context).padding.bottom,
        ),
        children: <Widget>[
          CupertinoListSection.insetGrouped(
            backgroundColor: pageBackground(context),
            children: <Widget>[
              CupertinoListTile(
                leading: Icon(
                  CupertinoIcons.doc_text,
                  size: 22,
                  color: AppAccent.primary,
                ),
                title: const Text('Elychron'),
                subtitle: const Text('Celechron 的非官方改版 · 遵循 GPLv3 分发'),
              ),
            ],
          ),
          CupertinoListSection.insetGrouped(
            backgroundColor: pageBackground(context),
            header: sectionHeader(context, '免责声明'),
            children: <Widget>[_paragraph(context, '在适用的法律范围内，该程序不提供任何质量保证。除非另有书面说明，版权持有者和程序提供者应按照原样提供程序，并且不提供任何明示或者暗示的保证，包括但不限于适销性和特定用途适用性的暗示保证。使用该程序所产生的全部风险，比如程序的质量和性能问题，全部由你承担。如果程序出现缺陷，你将承担所有必要的修复和更正服务带来的损失。')],
          ),
          CupertinoListSection.insetGrouped(
            backgroundColor: pageBackground(context),
            header: sectionHeader(context, '责任限制'),
            children: <Widget>[_paragraph(context, '除非有适用法律或书面协议要求，任何版权持有者，或该程序按照本协议可能存在的第三方修改和再发布者，都不对你的损失负有责任，包括由于使用或者不能使用该程序造成的任何一般的、特殊的、偶发的或重大的损失（包括但不限于数据丢失、数据失真、你或第三方的后续损失、该程序无法和其他程序协同工作等），即使他们声称会对此负责。')],
          ),
          CupertinoListSection.insetGrouped(
            backgroundColor: pageBackground(context),
            header: sectionHeader(context, '许可与源码'),
            footer: sectionFooter(
              context,
              'GPLv3 允许你自由使用、修改和再分发，但改了之后再发出去必须同样开源，'
              '并且要让拿到安装包的人能找到源码。',
            ),
            children: <Widget>[
              _linkTile('查看 GPLv3 协议全文', _gplUrl),
              _linkTile('上游项目 Celechron', _upstreamUrl),
              _linkTile('本改版源码（Elychron）', _forkUrl),
            ],
          ),
        ],
      ),
    );
  }
}
