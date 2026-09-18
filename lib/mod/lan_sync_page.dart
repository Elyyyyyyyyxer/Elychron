import 'dart:async';

import 'package:celechron/mod/lan_sync_client.dart';
import 'package:celechron/page/option/option_view.dart' show BackChervonRow;
import 'package:celechron/mod/lan_sync_server.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:celechron/design/page_background.dart';

/// 设置 → 数据 → 局域网同步
///
/// 本机当服务器，同一 Wi-Fi 下另一台设备用浏览器打开面板就能看待办、打钩、新建、
/// 导出导入。不注册账号、不上传数据到任何第三方。
class LanSyncPage extends StatefulWidget {
  const LanSyncPage({super.key});

  @override
  State<LanSyncPage> createState() => _LanSyncPageState();
}

class _LanSyncPageState extends State<LanSyncPage> {
  final _server = LanSyncServer.instance;
  final _client = LanSyncClient.instance;
  final _addressController = TextEditingController();
  final _codeController = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // 读回上次的配对信息（有的话直接显示同步按钮，不用重新输码）
    _client.load();
    if (_client.address.isNotEmpty) _addressController.text = _client.address;
  }

  @override
  void dispose() {
    _addressController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  /// 连接另一台设备
  Future<void> _connectPeer() async {
    setState(() => _busy = true);
    final ok = await _client.pair(
      address: _addressController.text,
      code: _codeController.text,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      // 连上之后立刻做一次双向同步，省得用户还要再点一下
      await _syncPeer(bothWays: true);
    } else {
      await _showResult('连不上', _client.lastError ?? '未知原因');
    }
  }

  /// 拉取 / 推送 / 双向
  Future<void> _syncPeer({
    required bool bothWays,
    bool pullOnly = false,
  }) async {
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
    await _showResult(
      ok ? '同步完成' : '同步失败',
      ok ? _client.lastSyncSummary : (_client.lastError ?? '未知原因'),
    );
  }

  Future<void> _showResult(String title, String message) async {
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

  Future<void> _toggle(bool value) async {
    setState(() => _busy = true);
    if (value) {
      await _server.start();
    } else {
      await _server.stop();
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (value && _server.lastError != null) {
      await showCupertinoDialog<void>(
        context: context,
        builder: (BuildContext context) => CupertinoAlertDialog(
          title: const Text('打不开'),
          content: Padding(
            padding: const EdgeInsets.only(top: 8),
            child:
                Text(_server.lastError!, style: const TextStyle(fontSize: 14)),
          ),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              child: const Text('知道了'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    await showCupertinoDialog<void>(
      context: context,
      builder: (BuildContext context) => CupertinoAlertDialog(
        title: const Text('已复制'),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(text, style: const TextStyle(fontSize: 14)),
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

  @override
  Widget build(BuildContext context) {
    final url = _server.url;
    final running = _server.isRunning;
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('局域网同步')),
      child: ListView(
        // ===== MOD ===== 底部留出系统导航栏的高度（否则最后一块内容会被压掉一半）
        padding: EdgeInsets.only(
          top: 12,
          bottom: 12 + MediaQuery.of(context).padding.bottom,
        ),
        children: [
          CupertinoListSection.insetGrouped(
            backgroundColor: pageBackground(context),
            header: const Text('开关'),
            children: [
              CupertinoListTile(
                title: const Text('开启局域网同步'),
                subtitle: Text(
                  running ? '正在监听，另一台设备可以连进来了' : '默认关闭；只在打开期间监听',
                ),
                trailing: _busy
                    ? const CupertinoActivityIndicator()
                    : CupertinoSwitch(
                        value: running,
                        onChanged: (bool value) => _toggle(value),
                      ),
              ),
            ],
          ),
          if (running && url != null) ...[
            CupertinoListSection.insetGrouped(
              backgroundColor: pageBackground(context),
              header: const Text('① 把这台设备当服务器：地址与配对码'),
              children: [
                CupertinoListTile(
                  title: const Text('访问地址'),
                  subtitle: Text(url, style: const TextStyle(fontSize: 15)),
                  trailing: CupertinoButton(
                    padding: EdgeInsets.zero,
                    child: const Text('复制'),
                    onPressed: () => _copy(url),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: CupertinoColors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: QrImageView(data: url, size: 168),
                    ),
                  ),
                ),
              ],
            ),
            CupertinoListSection.insetGrouped(
              backgroundColor: pageBackground(context),
              header: const Text('② 配对码（另一台设备要输的）'),
              footer: const Text('配对码每次开启都会重新生成，请填写最新的配对码。'),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Center(
                    child: Text(
                      _server.code,
                      style: const TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
          // ===== 连接另一台设备（客户端）=====
          //
          // 用户口径：手机连接电脑端。所以这一块是"我这台去连别人"，
          // 上面那两块是"别人来连我"，两个方向都在这一页里。
          CupertinoListSection.insetGrouped(
            backgroundColor: pageBackground(context),
            header: const Text('③ 连接另一台设备'),
            footer: Text(_client.isPaired
                ? '已连接到 ${_client.address}。改动会按更新时间双向合并，较新的一侧说了算。'
                : '在另一台设备上打开本页，把它显示的地址和配对码填进来即可。'),
            children: [
              if (!_client.isPaired) ...[
                CupertinoListTile(
                  title: const Text('对方地址'),
                  subtitle: CupertinoTextField(
                    controller: _addressController,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    placeholder: '例如 192.168.31.61:8686',
                  ),
                ),
                CupertinoListTile(
                  title: const Text('配对码'),
                  subtitle: CupertinoTextField(
                    controller: _codeController,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    placeholder: '对方页面上显示的 6 位数字',
                  ),
                ),
                CupertinoListTile(
                  title: const Text('连接'),
                  subtitle: Text(_client.lastError ?? '填好上面两项后点这里'),
                  trailing: _busy
                      ? const CupertinoActivityIndicator()
                      : const BackChervonRow(),
                  onTap: _busy ? null : _connectPeer,
                ),
              ] else ...[
                CupertinoListTile(
                  title: const Text('双向同步'),
                  subtitle: const Text('先把本机改动推过去，再把对方的改动拉回来'),
                  trailing: const BackChervonRow(),
                  onTap: _busy ? null : () => _syncPeer(bothWays: true),
                ),
                CupertinoListTile(
                  title: const Text('从对方拉取'),
                  subtitle: const Text('只把对方的数据合并到本机'),
                  trailing: const BackChervonRow(),
                  onTap: _busy
                      ? null
                      : () => _syncPeer(bothWays: false, pullOnly: true),
                ),
                CupertinoListTile(
                  title: const Text('推送给对方'),
                  subtitle: const Text('只把本机的数据发给对方合并'),
                  trailing: const BackChervonRow(),
                  onTap: _busy ? null : () => _syncPeer(bothWays: false),
                ),
                if (_client.lastSyncAt != null)
                  CupertinoListTile(
                    title: Text('上次同步 · ${_client.lastSyncSummary}'),
                    subtitle: Text(_format(_client.lastSyncAt!)),
                  ),
                CupertinoListTile(
                  title: const Text('断开连接'),
                  subtitle: const Text('只清掉配对信息，不影响数据'),
                  onTap: () async {
                    await _client.forget();
                    if (mounted) setState(() {});
                  },
                ),
              ],
            ],
          ),
          if (_server.lastSyncAt != null)
            CupertinoListSection.insetGrouped(
              backgroundColor: pageBackground(context),
              header: const Text('最近一次同步'),
              children: [
                CupertinoListTile(
                  title: Text('来自另一台设备 · ${_server.lastSyncSummary}'),
                  subtitle: Text(_format(_server.lastSyncAt!)),
                ),
              ],
            ),
          CupertinoListSection.insetGrouped(
            backgroundColor: pageBackground(context),
            header: const Text('说明'),
            footer: const Text(
              '数据只在局域网内直接传输，不经过任何服务器，也不需要注册账号。\n'
              '两端都要装 Elychron：一台当服务器，另一台填地址与配对码连过来。',
            ),
            children: const [
              CupertinoListTile(
                title: Text('同一 Wi-Fi 才能用'),
                subtitle: Text('跨网络连不上，这是局域网直连的固有限制'),
              ),
              CupertinoListTile(
                title: Text('只在 App 打开时可用'),
                subtitle: Text('切到后台过久可能被系统暂停监听；要连的时候回到这个页面看一眼即可'),
              ),
              CupertinoListTile(
                title: Text('两边都可以当服务器'),
                subtitle: Text('桌面端当服务器更顺手（键盘在旁边）；手机连电脑、电脑连手机都行'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _format(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}';
  }
}
