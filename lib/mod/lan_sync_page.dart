import 'dart:async';

import 'package:celechron/design/page_background.dart';
import 'package:celechron/design/round_rectangle_card.dart';
import 'package:celechron/design/sub_title.dart';
import 'package:celechron/mod/lan_conflicts_page.dart';
import 'package:celechron/mod/lan_sync_client.dart';
import 'package:celechron/mod/lan_sync_conflict.dart';
import 'package:celechron/mod/lan_sync_server.dart';
import 'package:celechron/page/option/option_view.dart' show BackChervonRow;
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// ===== 局域网同步（设置 → 数据 → 局域网同步）=====
///
/// 2026-09-19 按用户要求重做界面：
/// 「只有两个圆角方框，一个是发起连接，一个是连接设备，点进去就自动打开监听。
///   后面的流程一样，只不过用钉钉化的风格，简洁大气优雅。两端都要改」
///
/// 所以这个页面是**一个入口 + 两套流程**：
///
///   发起连接 —— 点一下就把本机变成接收方（不用再找一个开关去开）
///   连接设备 —— 去连另一台点了「发起连接」的设备
///
/// 手机端与桌面端共用这一个页面，两端长得一样（桌面端由 DesktopFrame 统一限宽）。
class LanSyncPage extends StatefulWidget {
  const LanSyncPage({super.key});

  @override
  State<LanSyncPage> createState() => _LanSyncPageState();
}

/// 当前停留在哪一步
enum _Step { choose, hosting, connecting }

class _LanSyncPageState extends State<LanSyncPage> {
  final _server = LanSyncServer.instance;
  final _client = LanSyncClient.instance;
  final _addressController = TextEditingController();
  final _codeController = TextEditingController();

  _Step _step = _Step.choose;
  bool _busy = false;

  /// 待处理的同步冲突条数（入口卡片上显示）
  int get _conflictCount => LanSyncConflictStore.load().length;

  static const Color _accent = Color(0xFFFF699A);

  @override
  void initState() {
    super.initState();
    _client.load();
    if (_client.address.isNotEmpty) _addressController.text = _client.address;
    // 已经在监听的话（比如上次没停）直接进"发起连接"那一步，不给用户一个死开关
    if (_server.isRunning) _step = _Step.hosting;
  }

  @override
  void dispose() {
    _addressController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------- 流程

  /// 发起连接：点一下就开监听
  Future<void> _startHosting() async {
    setState(() => _busy = true);
    await _server.start();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _step = _Step.hosting;
    });
    if (_server.lastError != null) {
      await _toast('打不开', _server.lastError!);
    }
  }

  Future<void> _stopHosting() async {
    setState(() => _busy = true);
    await _server.stop();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _step = _Step.choose;
    });
  }

  /// 连接设备：用配对码换 token，成功就顺手同步一次
  Future<void> _connect() async {
    setState(() => _busy = true);
    final ok = await _client.pair(
      address: _addressController.text,
      code: _codeController.text,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      await _toast('连不上', _client.lastError ?? '未知原因');
      return;
    }
    await _sync(bothWays: true);
  }

  Future<void> _sync({required bool bothWays, bool pullOnly = false}) async {
    setState(() => _busy = true);
    final bool ok;
    if (pullOnly) {
      ok = await _client.pull();
    } else if (bothWays) {
      ok = await _client.syncBothWays();
    } else {
      ok = await _client.push();
    }
    if (!mounted) return;
    setState(() => _busy = false);
    await _toast(
      ok ? '同步完成' : '同步失败',
      ok ? _client.lastSyncSummary : (_client.lastError ?? '未知原因'),
    );
  }

  Future<void> _toast(String title, String message) async {
    if (!mounted) return;
    await showCupertinoDialog<void>(
      context: context,
      builder: (BuildContext context) => CupertinoAlertDialog(
        title: Text(title),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(message, style: const TextStyle(fontSize: 14)),
        ),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            child: const Text('好'),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    await _toast('已复制', text);
  }

  // ------------------------------------------------------------- 界面

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: pageBackground(context),
      navigationBar: CupertinoNavigationBar(
        middle: const Text('局域网同步'),
        // 进去之后给一个"回到选择"的入口（顶部返回键是退出整个页面）
        trailing: _step == _Step.choose
            ? null
            : CupertinoButton(
                padding: EdgeInsets.zero,
                child: const Text('切换'),
                onPressed: () => setState(() => _step = _Step.choose),
              ),
      ),
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.only(
            top: 16,
            bottom: 24 + MediaQuery.of(context).padding.bottom,
          ),
          children: switch (_step) {
            _Step.choose => _chooseView(context),
            _Step.hosting => _hostingView(context),
            _Step.connecting => _connectingView(context),
          },
        ),
      ),
    );
  }

  /// 第一步：两个大卡片
  List<Widget> _chooseView(BuildContext context) {
    return <Widget>[
      _entryCard(
        context,
        icon: CupertinoIcons.wifi,
        title: '发起连接',
        subtitle: '把这台设备变成接收方，让另一台连过来',
        onTap: _busy ? null : _startHosting,
      ),
      const SizedBox(height: 12),
      _entryCard(
        context,
        icon: CupertinoIcons.link,
        title: '连接设备',
        subtitle: '去连另一台已经点了「发起连接」的设备',
        onTap: _busy ? null : () => setState(() => _step = _Step.connecting),
      ),
      if (_conflictCount > 0) ...[
        const SizedBox(height: 20),
        _actionTile(
          title: '处理冲突（' + _conflictCount.toString() + ' 条）',
          subtitle: '两边都改过的待办，逐字段选一下保留哪边',
          accent: true,
          onTap: () async {
            await Navigator.of(context, rootNavigator: true).push(
              CupertinoPageRoute<void>(
                builder: (BuildContext context) => const LanConflictsPage(),
              ),
            );
            if (mounted) setState(() {});
          },
        ),
      ],
      if (_client.isPaired) ...[
        const SizedBox(height: 22),
        SubSubtitleRow(subtitle: '已连接 · ' + _client.address),
        const SizedBox(height: 8),
        _actionTile(
          title: '双向同步',
          subtitle: '先把本机改动推过去，再把对方的改动拉回来',
          onTap: _busy ? null : () => _sync(bothWays: true),
        ),
        _actionTile(
          title: '变动时自动同步',
          subtitle: _client.autoSyncEnabled
              ? '本机一有改动（新增/修改待办）就自动推给对方，并每分钟拉一次'
              : '已关闭：只能手动点上面的「双向同步」',
          onTap: () async {
            await _client.setAutoSync(!_client.autoSyncEnabled);
            if (mounted) setState(() {});
          },
        ),
        _actionTile(
          title: '断开连接',
          subtitle: '只清掉配对信息，不影响数据',
          onTap: () async {
            await _client.forget();
            if (mounted) setState(() {});
          },
        ),
      ],
      const SizedBox(height: 22),
      const _Footnotes(),
    ];
  }

  /// 发起连接：地址 + 二维码 + 配对码
  List<Widget> _hostingView(BuildContext context) {
    final url = _server.url;
    final labelColor =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    return <Widget>[
      _statusHeader(
        context,
        icon: CupertinoIcons.wifi,
        title: _server.isRunning ? '正在等待连接' : '没有开起来',
        subtitle: _server.isRunning
            ? '在另一台设备上点「连接设备」，把下面的地址与配对码填进去'
            : (_server.lastError ?? '未知原因'),
      ),
      if (url != null) ...[
        const SizedBox(height: 18),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: RoundRectangleCard(
            padding: const EdgeInsets.symmetric(vertical: 22),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: CupertinoColors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: QrImageView(data: url, size: 168),
                ),
                const SizedBox(height: 16),
                Text(url,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 0),
                  onPressed: () => _copy(url),
                  child: const Text('复制地址',
                      style: TextStyle(
                          fontSize: 13, color: CupertinoColors.systemBlue)),
                ),
                const SizedBox(height: 18),
                Text('配对码', style: TextStyle(fontSize: 13, color: labelColor)),
                const SizedBox(height: 2),
                GestureDetector(
                  onTap: () => _copy(_server.code),
                  child: Text(
                    _server.code,
                    style: const TextStyle(
                      fontSize: 38,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 10,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_server.lastSyncAt != null) ...[
          const SizedBox(height: 18),
          _actionTile(
            title: '最近一次同步',
            subtitle:
                _server.lastSyncSummary + ' · ' + _format(_server.lastSyncAt!),
          ),
        ],
        const SizedBox(height: 12),
        _actionTile(
          title: '停止等待',
          subtitle: '关掉之后别的设备就连不进来了',
          destructive: true,
          onTap: _busy ? null : _stopHosting,
        ),
      ],
    ];
  }

  /// 连接设备：填地址与配对码
  List<Widget> _connectingView(BuildContext context) {
    return <Widget>[
      _statusHeader(
        context,
        icon: CupertinoIcons.link,
        title: '连接另一台设备',
        subtitle: '对方点了「发起连接」之后，它页面上会显示地址与配对码',
      ),
      const SizedBox(height: 18),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: RoundRectangleCard(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Column(
            children: [
              _field(
                label: '对方地址',
                controller: _addressController,
                hint: '例如 192.168.31.61:8686',
                keyboardType: TextInputType.url,
              ),
              Container(
                height: 0.5,
                color: CupertinoColors.separator.resolveFrom(context),
              ),
              _field(
                label: '配对码',
                controller: _codeController,
                hint: '对方显示的 6 位数字',
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 18),
      _actionTile(
        title: _busy ? '连接中…' : '连接',
        subtitle: '连上之后会自动做一次双向同步',
        accent: true,
        onTap: _busy ? null : _connect,
      ),
      if (_client.lastError != null) ...[
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 26),
          child: Text(
            _client.lastError!,
            style:
                const TextStyle(fontSize: 13, color: CupertinoColors.systemRed),
          ),
        ),
      ],
      const SizedBox(height: 22),
      const _Footnotes(),
    ];
  }

  // ------------------------------------------------------------- 小组件

  /// 入口大卡片：图标 + 标题 + 说明 + 箭头
  Widget _entryCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    final labelColor =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: RoundRectangleCard(
        onTap: onTap,
        animate: true,
        padding: const EdgeInsets.fromLTRB(18, 18, 16, 18),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: _accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, size: 23, color: _accent),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style: TextStyle(fontSize: 13, color: labelColor)),
                ],
              ),
            ),
            Icon(CupertinoIcons.chevron_forward, size: 15, color: labelColor),
          ],
        ),
      ),
    );
  }

  /// 顶部状态块
  Widget _statusHeader(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final labelColor =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 4, 26, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: labelColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(subtitle,
                    style: TextStyle(fontSize: 13, color: labelColor)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 一行动作（钉钉那种整块的浅色行）
  Widget _actionTile({
    required String title,
    String? subtitle,
    VoidCallback? onTap,
    bool accent = false,
    bool destructive = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: RoundRectangleCard(
        onTap: onTap,
        animate: true,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w500,
                      color: destructive
                          ? CupertinoColors.systemRed
                          : (accent ? _accent : null),
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(subtitle,
                        style: const TextStyle(
                            fontSize: 12.5, color: CupertinoColors.systemGrey)),
                  ],
                ],
              ),
            ),
            const BackChervonRow(),
          ],
        ),
      ),
    );
  }

  /// 表单里的一行
  Widget _field({
    required String label,
    required TextEditingController controller,
    required String hint,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 76,
            child: Text(label, style: const TextStyle(fontSize: 15)),
          ),
          Expanded(
            child: CupertinoTextField(
              controller: controller,
              keyboardType: keyboardType,
              autocorrect: false,
              padding: const EdgeInsets.symmetric(vertical: 10),
              placeholder: hint,
            ),
          ),
        ],
      ),
    );
  }

  static String _format(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return time.year.toString() +
        '-' +
        two(time.month) +
        '-' +
        two(time.day) +
        ' ' +
        two(time.hour) +
        ':' +
        two(time.minute);
  }
}

/// 底部说明（放最后，不抢主流程注意力）
class _Footnotes extends StatelessWidget {
  const _Footnotes();

  @override
  Widget build(BuildContext context) {
    final labelColor =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    const items = <String>[
      '同一 Wi-Fi 才能连上，跨网络连不上（局域网直连的固有限制）',
      '数据只在这两台设备之间直接传输，不经过任何服务器，也不需要账号',
      '两台设备都要装 Elychron；谁发起、谁连接都行',
      '只在 App 打开时可用，切后台太久可能被系统暂停',
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('· ' + item,
                  style: TextStyle(fontSize: 12, color: labelColor)),
            ),
        ],
      ),
    );
  }
}
