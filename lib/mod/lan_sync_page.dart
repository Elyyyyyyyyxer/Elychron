import 'dart:async';

import 'package:celechron/mod/lan_sync_server.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// 设置 → 数据 → 局域网同步
///
/// 手机当服务器，同一 Wi-Fi 下的电脑用浏览器打开面板就能看待办、打钩、新建、
/// 导出导入。不注册账号、不上传数据到任何第三方。
class LanSyncPage extends StatefulWidget {
  const LanSyncPage({super.key});

  @override
  State<LanSyncPage> createState() => _LanSyncPageState();
}

class _LanSyncPageState extends State<LanSyncPage> {
  final _server = LanSyncServer.instance;
  bool _busy = false;

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
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          CupertinoListSection.insetGrouped(
            header: const Text('开关'),
            children: [
              CupertinoListTile(
                title: const Text('开启局域网同步'),
                subtitle: Text(
                  running ? '正在监听，电脑可以连了' : '默认关闭；只在打开期间监听',
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
              header: const Text('① 电脑浏览器打开这个地址'),
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
              header: const Text('② 在电脑上输入配对码'),
              footer: const Text('配对码每次开启都会重新生成；只有输入正确的电脑才能读到数据。'),
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
          if (_server.lastSyncAt != null)
            CupertinoListSection.insetGrouped(
              header: const Text('最近一次同步'),
              children: [
                CupertinoListTile(
                  title: Text('来自电脑 · ${_server.lastSyncSummary}'),
                  subtitle: Text(_format(_server.lastSyncAt!)),
                ),
              ],
            ),
          CupertinoListSection.insetGrouped(
            header: const Text('说明'),
            footer: const Text(
              '数据只在局域网内直接传输，不经过任何服务器，也不需要注册账号。\n'
              '电脑上的「导出」会下载整份 JSON 到电脑，「导入」会按 uid + 更新时间合并回手机。\n'
              '删除会记墓碑，多台设备之间不会「删了又回来」。',
            ),
            children: const [
              CupertinoListTile(
                title: Text('同一 Wi-Fi 才能用'),
                subtitle: Text('跨网络（比如用流量）连不上，这是局域网直连的固有限制'),
              ),
              CupertinoListTile(
                title: Text('只在 App 打开时可用'),
                subtitle: Text('切到后台过久可能被系统暂停监听；要连的时候回到这个页面看一眼即可'),
              ),
              CupertinoListTile(
                title: Text('电脑端会自动同步'),
                subtitle: Text('网页每 30 秒自动刷新，切回那个标签页也会立刻刷新；'
                    '在电脑上保存的改动会马上写回手机'),
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
