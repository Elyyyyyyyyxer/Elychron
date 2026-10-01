import 'package:celechron/database/database_helper.dart';
import 'package:celechron/design/app_route.dart';
import 'package:celechron/design/page_background.dart';
import 'package:celechron/design/section_text_style.dart';
import 'package:celechron/http/library_spider.dart';
import 'package:celechron/http/zjuServices/exceptions.dart';
import 'package:celechron/model/scholar.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';

/// ===== 设置 → 校园服务 → 图书馆预约（2026-10-01）=====
///
/// 只做"登录 + 读数据"：**我的预约**（座位/研讨间）与**座位查询**。
/// 登录复用教务那套 ZJU 账号（ZjuAm），用户不用为图书馆再填任何东西。
///
/// ⚠️ 登录态是 token 不是 cookie（实测：只带 PHPSESSID 会被判"您尚未登录"），
/// 换 token 的流程见 http/library_spider.dart 的 login()。
class LibrarySettingsPage extends StatefulWidget {
  const LibrarySettingsPage({super.key});

  @override
  State<LibrarySettingsPage> createState() => _LibrarySettingsPageState();
}

class _LibrarySettingsPageState extends State<LibrarySettingsPage> {
  bool _busy = false;
  String? _result;
  int? _reservationCount;

  DatabaseHelper? get _db {
    try {
      return Get.find<DatabaseHelper>(tag: 'db');
    } catch (_) {
      return null;
    }
  }

  bool get _enabled => _db?.getLibraryEnabled() ?? false;

  /// 测试连接：登录 → 读一次公告（免登录）→ 读一次我的预约
  Future<void> _test() async {
    setState(() {
      _busy = true;
      _result = null;
    });
    LibrarySpider? spider;
    try {
      final scholar = Get.find<Rx<Scholar>>(tag: 'scholar').value;
      final username = scholar.username ?? '';
      final password = scholar.password ?? '';
      if (username.isEmpty || password.isEmpty) {
        throw LibraryAuthException('还没登录教务账号，图书馆用的是同一套 ZJU 账号');
      }
      spider = LibrarySpider(username: username, password: password);
      final notices = await spider.notices();
      await spider.login();
      final info = await spider.myInfo();
      final count = LibrarySpider.reservationsFrom(info).length;
      final result = '连接成功：' + count.toString() + ' 条预约，' +
          notices.length.toString() + ' 条公告';
      await _db?.setLibraryLastResult(result);
      if (!mounted) return;
      setState(() {
        _result = result;
        _reservationCount = count;
      });
    } on Object catch (error) {
      final message = error is AuthenticationExpiredException
          ? '教务登录态失效了：' + error.toString()
          : error.toString();
      await _db?.setLibraryLastResult(message);
      if (!mounted) return;
      setState(() => _result = message);
    } finally {
      spider?.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: pageBackground(context),
      navigationBar: const CupertinoNavigationBar(middle: Text('图书馆预约')),
      child: ListView(
        padding: EdgeInsets.only(
          top: 8,
          bottom: 24 + MediaQuery.of(context).padding.bottom,
        ),
        children: <Widget>[
          CupertinoListSection.insetGrouped(
            backgroundColor: pageBackground(context),
            header: sectionHeader(context, '开关'),
            footer: sectionFooter(
              context,
              '用你已登录的教务账号连图书馆；图书馆这边不用再填任何账号。'
              '目前只读：我的预约、座位查询。',
            ),
            children: <Widget>[
              CupertinoListTile(
                title: const Text('启用图书馆预约'),
                subtitle: Text(
                  _db?.getLibraryLastResult().isNotEmpty == true
                      ? _db!.getLibraryLastResult()
                      : '还没连接过',
                ),
                trailing: CupertinoSwitch(
                  value: _enabled,
                  onChanged: (bool value) async {
                    await _db?.setLibraryEnabled(value);
                    if (mounted) setState(() {});
                  },
                ),
              ),
            ],
          ),
          CupertinoListSection.insetGrouped(
            backgroundColor: pageBackground(context),
            header: sectionHeader(context, '连接'),
            footer: sectionFooter(
              context,
              '登录走学校的统一身份认证（和教务同一条路），'
              '登录态是临时的、只存在内存里，不会写进数据库。',
            ),
            children: <Widget>[
              CupertinoListTile(
                title: const Text('测试连接'),
                subtitle: Text(_result ?? '登录 + 读一次我的预约'),
                trailing: _busy
                    ? const CupertinoActivityIndicator()
                    : const Icon(CupertinoIcons.bolt, size: 18),
                onTap: _busy ? null : _test,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 设置页里的那一行（校园服务分组）
class LibraryReservationTile extends StatelessWidget {
  const LibraryReservationTile({super.key});

  @override
  Widget build(BuildContext context) {
    String subtitle = '关闭中；把图书馆的预约变成待办';
    try {
      final db = Get.find<DatabaseHelper>(tag: 'db');
      if (db.getLibraryEnabled()) {
        final last = db.getLibraryLastResult();
        subtitle = last.isEmpty ? '已开启' : last;
      }
    } catch (_) {}
    return CupertinoListTile(
      title: const Text('图书馆预约'),
      subtitle: Text(subtitle),
      trailing: const Icon(CupertinoIcons.arrow_right,
          size: 18, color: CupertinoColors.tertiaryLabel),
      onTap: () => Navigator.of(context, rootNavigator: true).push(
        appPageRoute<void>(
          builder: (BuildContext context) => const LibrarySettingsPage(),
        ),
      ),
    );
  }
}
