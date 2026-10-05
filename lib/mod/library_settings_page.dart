import 'dart:convert';

import 'package:celechron/design/app_accent.dart';
import 'package:celechron/design/app_route.dart';
import 'package:celechron/design/page_background.dart';
import 'package:celechron/design/section_text_style.dart';
import 'package:celechron/database/database_helper.dart';
import 'package:celechron/http/library_spider.dart';
import 'package:celechron/model/task.dart';
import 'package:celechron/mod/library_config.dart';
import 'package:celechron/mod/library_login_page.dart';
import 'package:celechron/mod/library_tasks.dart';
import 'package:celechron/mod/library_web_session.dart';
import 'package:celechron/utils/platform_features.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';

/// ===== 设置 → 校园服务 → 图书馆预约 =====
///
/// 只做三件事：登录、看我的预约、把预约变成待办。
/// 数据一律从**那个网页**里取（这站单设备登录，凭据只在页面里成立）——
/// 见 mod/library_web_session.dart。
class LibrarySettingsPage extends StatefulWidget {
  const LibrarySettingsPage({super.key});

  @override
  State<LibrarySettingsPage> createState() => _LibrarySettingsPageState();
}

class _LibrarySettingsPageState extends State<LibrarySettingsPage> {
  final TextEditingController _tokenController = TextEditingController();

  bool _busy = false;
  bool _loadingList = false;
  String? _status;
  String _name = '';
  List<LibraryReservation> _reservations = <LibraryReservation>[];

  @override
  void initState() {
    super.initState();
    _name = LibraryConfig.lastName;
    if (LibraryConfig.enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadReservations());
    }
  }

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  DatabaseHelper? get _db {
    try {
      return Get.find<DatabaseHelper>(tag: 'db');
    } catch (_) {
      return null;
    }
  }

  RxList<Task>? get _taskList {
    try {
      return Get.find<RxList<Task>>(tag: 'taskList');
    } catch (_) {
      return null;
    }
  }

  bool get _enabled => LibraryConfig.enabled;

  /// 从网页里读一次"我的预约"（三个来源合并）
  Future<void> _loadReservations() async {
    if (!PlatformFeatures.hasWebViewLogin) {
      setState(() => _status = '桌面端没有内置浏览器，先用「粘贴 token」那套');
      return;
    }
    setState(() {
      _loadingList = true;
      _status = null;
    });
    final found = <String, LibraryReservation>{};
    var authError = '';
    for (final source in const <({String path, String kind})>[
      (path: '/api/Member/seat', kind: 'seat'),
      (path: '/api/Member/room', kind: 'room'),
      (path: '/api/Member/seminar', kind: 'seminar'),
    ]) {
      try {
        final body = await LibraryWebSession.instance.postJson(source.path);
        // 原始 JSON 进 logcat：座位号 / 房间名的字段名只能靠它对出来
        LibrarySpider.traceResponse(source.path, body);
        for (final reservation in LibrarySpider.reservationsFrom(jsonDecode(body),
            kind: source.kind)) {
          if (reservation.id.isEmpty) continue;
          found[reservation.id] = reservation;
        }
      } on LibraryAuthException catch (error) {
        authError = error.message;
      } on Object {
        // 单个来源失败不影响别的
      }
    }
    // 顺手取一次姓名（"已连接"要有名字才像样）
    try {
      final me = jsonDecode(await LibraryWebSession.instance.postJson('/api/Member/my'));
      if (me is Map && me['code'] == 1 && me['data'] is Map) {
        _name = me['data']['name']?.toString() ?? _name;
        await LibraryConfig.setLastName(_name);
      }
    } on Object {
      // 名字取不到就算了
    }

    // 只留"还生效"的：结束时间在将来、且不是已取消 / 已使用。
    // 用户明确要求——历史预约别再出现在"我的预约"里。
    final active = DateTime.now();
    final list = found.values
        .where((reservation) => libraryReservationActive(reservation, now: active))
        .toList()
      ..sort((a, b) => (a.start ?? DateTime(2100))
          .compareTo(b.start ?? DateTime(2100)));
    if (!mounted) return;
    setState(() {
      _loadingList = false;
      _reservations = list;
      _status = authError.isEmpty ? null : authError;
    });
    await LibraryConfig.setLastCount(list.length);
    if (authError.isEmpty && list.isNotEmpty) {
      await LibraryConfig.setEnabled(true);
    }
  }

  /// 把预约落成待办
  Future<void> _syncToTasks() async {
    final db = _db;
    final list = _taskList;
    if (db == null || list == null) {
      setState(() => _status = '待办还没准备好');
      return;
    }
    setState(() {
      _busy = true;
      _status = null;
    });
    var result = '';
    try {
      result = await syncLibraryReservations(db: db, taskList: list);
    } on Object catch (error) {
      result = error.toString();
    }
    await LibraryConfig.setLastResult(result);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = result;
    });
  }

  Future<void> _loginWithWebView() async {
    final result = await Navigator.of(context, rootNavigator: true).push<String>(
      appPageRoute<String>(
        builder: (BuildContext context) => const LibraryLoginPage(),
      ),
    );
    if (!mounted || result == null) return;
    setState(() => _status = result);
    await _loadReservations();
  }

  Future<void> _saveToken() async {
    final value = _tokenController.text.trim();
    if (value.isEmpty) return;
    await LibraryConfig.setToken(value);
    _tokenController.clear();
    if (mounted) setState(() => _status = 'token 已保存（网页会话仍以内置浏览器那条为准）');
  }

  Future<void> _clear() async {
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (BuildContext context) => CupertinoAlertDialog(
        title: const Text('清除图书馆登录信息'),
        content: const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('清除后不再读取预约；已经建好的待办不受影响。',
              style: TextStyle(fontSize: 14)),
        ),
        actions: <Widget>[
          CupertinoDialogAction(
            child: const Text('取消'),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('清除'),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await LibraryConfig.clearToken();
    await LibraryConfig.setLastName('');
    await LibraryConfig.setLastCount(0);
    LibraryWebSession.instance.reset();
    await clearLibraryWebViewCookies();
    if (!mounted) return;
    setState(() {
      _reservations = <LibraryReservation>[];
      _name = '';
      _status = null;
    });
  }

  static String _hm(DateTime t) {
    final local = t.toLocal();
    final two = (int v) => v.toString().padLeft(2, '0');
    return two(local.month) + '-' + two(local.day) + ' ' + two(local.hour) + ':' + two(local.minute);
  }

  @override
  Widget build(BuildContext context) {
    final hasToken = LibraryConfig.token.isNotEmpty;
    final connected = _name.isNotEmpty || _reservations.isNotEmpty;
    return CupertinoPageScaffold(
      backgroundColor: pageBackground(context),
      navigationBar: const CupertinoNavigationBar(middle: Text('图书馆预约')),
      child: ListView(
        padding: EdgeInsets.only(
          top: 8,
          bottom: 24 + MediaQuery.of(context).padding.bottom,
        ),
        children: <Widget>[
          // ① 状态
          CupertinoListSection.insetGrouped(
            backgroundColor: pageBackground(context),
            children: <Widget>[
              CupertinoListTile(
                leading: Icon(
                  connected ? CupertinoIcons.check_mark_circled_solid : CupertinoIcons.circle,
                  size: 22,
                  color: connected ? AppAccent.primary : CupertinoColors.tertiaryLabel,
                ),
                title: Text(connected ? '已连接' : '未连接'),
                subtitle: Text(
                  connected
                      ? (_name.isEmpty ? '' : _name + ' · ') +
                          _reservations.length.toString() +
                          ' 条预约'
                      : '用内置浏览器登录一次即可',
                ),
                trailing: _loadingList
                    ? const CupertinoActivityIndicator()
                    : CupertinoButton(
                        padding: EdgeInsets.zero,
                        child: const Text('刷新'),
                        onPressed: _busy ? null : _loadReservations,
                      ),
              ),
              if (_status != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text(
                    _status!,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
            ],
          ),
          // ② 我的预约
          CupertinoListSection.insetGrouped(
            backgroundColor: pageBackground(context),
            header: sectionHeader(context, '我的预约'),
            footer: sectionFooter(context, '只有还生效的预约会变成待办。'),
            children: <Widget>[
              if (_loadingList)
                const CupertinoListTile(
                  title: Text('正在读取…'),
                  trailing: CupertinoActivityIndicator(),
                )
              else if (_reservations.isEmpty)
                const CupertinoListTile(
                  title: Text('当前没有预约'),
                  subtitle: Text('在图书馆网站约到座位后再来刷新'),
                )
              else
                for (final reservation in _reservations)
                  CupertinoListTile(
                    // 用户要看到"是哪个座位 / 哪个房间"：地点 + 座位号 / 房间名
                    title: Text(
                      libraryPlaceDetail(reservation),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      (libraryStatusLabel(reservation).isEmpty
                              ? ''
                              : libraryStatusLabel(reservation) + ' · ') +
                          (reservation.start == null
                              ? ''
                              : _hm(reservation.start!)) +
                          (reservation.end == null
                              ? ''
                              : ' → ' + _hm(reservation.end!)),
                    ),
                  ),
            ],
          ),
          // ③ 同步到待办
          CupertinoListSection.insetGrouped(
            backgroundColor: pageBackground(context),
            header: sectionHeader(context, '同步'),
            footer: sectionFooter(context, '预约带起止时间，到点会提醒；反复同步不会重复长待办。'),
            children: <Widget>[
              CupertinoListTile(
                title: const Text('同步到待办'),
                subtitle: Text(
                  LibraryConfig.lastResult.isEmpty ? '把预约变成待办/日程' : LibraryConfig.lastResult,
                ),
                trailing: _busy
                    ? const CupertinoActivityIndicator()
                    : const Icon(CupertinoIcons.arrow_down_doc, size: 18),
                onTap: _busy ? null : _syncToTasks,
              ),
            ],
          ),
          // ④ 登录
          CupertinoListSection.insetGrouped(
            backgroundColor: pageBackground(context),
            header: sectionHeader(context, '登录'),
            footer: sectionFooter(
              context,
              PlatformFeatures.hasWebViewLogin
                  ? '点一下登录一次就行。'
                  : '桌面端用浏览器登录后，从 F12 → Application → Session Storage 复制 token。',
            ),
            children: <Widget>[
              if (PlatformFeatures.hasWebViewLogin)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: SizedBox(
                    width: double.infinity,
                    child: CupertinoButton.filled(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      onPressed: _busy ? null : _loginWithWebView,
                      child: const Text('用内置浏览器登录（推荐）'),
                    ),
                  ),
                ),
              if (hasToken)
                CupertinoListTile(
                  title: const Text('当前 token'),
                  subtitle: Text(LibraryConfig.maskedToken),
                  trailing: CupertinoButton(
                    padding: EdgeInsets.zero,
                    child: const Text('清除',
                        style: TextStyle(color: CupertinoColors.systemRed)),
                    onPressed: _busy ? null : _clear,
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Column(
                  children: <Widget>[
                    CupertinoTextField(
                      controller: _tokenController,
                      placeholder: '粘贴 token（桌面端兜底用）',
                      obscureText: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: CupertinoColors.tertiarySystemFill.resolveFrom(context),
                        borderRadius: BorderRadius.circular(9),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: CupertinoButton(
                        color: CupertinoColors.tertiarySystemFill.resolveFrom(context),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        onPressed: _busy ? null : _saveToken,
                        child: const Text('保存 token', style: TextStyle(fontSize: 15)),
                      ),
                    ),
                  ],
                ),
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
    var subtitle = '关闭中；把图书馆的预约变成待办';
    if (LibraryConfig.enabled) {
      final count = LibraryConfig.lastCount;
      final name = LibraryConfig.lastName;
      subtitle = '已连接' +
          (name.isEmpty ? '' : ' · ' + name) +
          ' · ' + count.toString() + ' 条预约';
    }
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
