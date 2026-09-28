import 'package:celechron/design/page_background.dart';
import 'package:celechron/mod/focus_device.dart';
import 'package:celechron/mod/webdav_client.dart';
import 'package:celechron/mod/webdav_config.dart';
import 'package:celechron/mod/webdav_files.dart';
import 'package:celechron/mod/webdav_providers.dart';
import 'package:celechron/mod/webdav_sync.dart';
import 'package:celechron/mod/webdav_sync_service.dart';
import 'package:celechron/page/option/option_view.dart' show BackChervonRow;
import 'package:flutter/cupertino.dart';
import 'package:url_launcher/url_launcher_string.dart';

/// ===== 全平台同步（W3）：设置向导 =====
///
/// 用户的原话：「我想要尽可能简化用户操作流程」。
///
/// 所以这里刻意**不提供**"填地址 + 填用户名 + 填密码 + 保存"那种裸表单，
/// 而是把 WebDAV 接入最常见的三个坑各自堵死：
///
///   坑 1：不知道填什么地址 → 点一家网盘，地址自动填好（预设表）；
///   坑 2：不知道要填"应用密码"而不是登录密码 → 副标题写清 + 直接给跳转按钮；
///   坑 3：填完不知道对不对 → 点"测试连接"，实测一次写读删，给一句人话结论；
///      连不上时也**先落地再说话**（坚果云用户名大写 → 401，这里会自动转小写）。
///
/// 三步走完才算配置好，走完立刻同步一次 —— 用户不需要理解"什么时候会同步"。
class WebDavSettingsPage extends StatefulWidget {
  const WebDavSettingsPage({super.key});

  @override
  State<WebDavSettingsPage> createState() => _WebDavSettingsPageState();
}

enum _Step { choose, account, done }

class _WebDavSettingsPageState extends State<WebDavSettingsPage> {
  _Step _step = _Step.choose;
  WebDavProvider? _provider;

  final _urlController = TextEditingController();
  final _userController = TextEditingController();
  final _passController = TextEditingController();

  bool _busy = false;
  String _busyText = '';
  WebDavCheck? _check;
  String _syncMessage = '';
  bool _syncFailed = false;
  bool _obscure = true;
  bool _enabled = false;
  bool _fileSync = false;

  static const Color _accent = Color(0xFFFF699A);

  @override
  void initState() {
    super.initState();
    _enabled = WebDavConfig.enabled;
    _load();
  }

  Future<void> _load() async {
    if (!WebDavConfig.loaded) await WebDavConfig.load();
    if (!mounted) return;
    setState(() {
      _enabled = WebDavConfig.enabled;
      _fileSync = WebDavConfig.fileSyncEnabled;
      _urlController.text = WebDavConfig.url;
      _userController.text = WebDavConfig.username;
      if (WebDavConfig.isConfigured) {
        _provider = WebDavProvider.match(WebDavConfig.url);
        _step = _Step.done;
      }
    });
  }

  @override
  void dispose() {
    _urlController.dispose();
    _userController.dispose();
    _passController.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------- 步骤

  void _pickProvider(WebDavProvider? provider) {
    setState(() {
      _provider = provider;
      _urlController.text = provider?.url ?? '';
      _check = null;
      _step = _Step.account;
    });
  }

  /// 用户名输入：这一家要求全小写的话，边打边转 —— 比事后报 401 再解释强得多。
  void _onUsernameChanged(String value) {
    if (_provider?.lowercaseUsername != true) return;
    final lower = value.toLowerCase();
    if (lower == value) return;
    _userController.value = TextEditingValue(
      text: lower,
      selection: TextSelection.collapsed(offset: lower.length),
    );
  }

  String get _usernameLabel {
    final provider = _provider;
    if (provider == null) return '用户名';
    return provider.usernameIsEmail ? '用户名（邮箱）' : '用户名';
  }

  // ------------------------------------------------------------- 测试连接

  Future<void> _test() async {
    if (_busy) return;
    final url = WebDavConfig.normalizeUrl(_urlController.text);
    if (WebDavConfig.looksLikeTemplate(url)) {
      setState(() => _check = const WebDavCheck(false, '请先把地址换成你自己的（现在是示例地址）'));
      return;
    }
    if (_userController.text.trim().isEmpty) {
      setState(() => _check = const WebDavCheck(false, '用户名还没填'));
      return;
    }
    if (_passController.text.trim().isEmpty) {
      setState(() => _check = const WebDavCheck(false, '应用密码还没填'));
      return;
    }
    setState(() {
      _busy = true;
      _busyText = '正在连接…';
      _check = null;
    });
    final client = WebDavClient(
      baseUrl: url,
      username: _userController.text.trim(),
      password: _passController.text.trim(),
      // 手机在弱网下可能好几秒没响应，别让用户以为界面卡死了
      timeout: const Duration(seconds: 20),
    );
    final sync = WebDavSync(
      client,
      deviceId: 'probe',
      deviceName: FocusDevice.current,
    );
    final result = await sync.selfCheck();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _busyText = '';
      _check = result;
      _urlController.text = url;
      // 自检可能把用户名改成了小写（坚果云的坑），界面要跟着显示出来，
      // 否则用户保存的还是那个错的大小写，下次又连不上。
      _userController.text = client.username;
    });
  }

  // ------------------------------------------------------------- 保存

  Future<void> _finish() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _busyText = '正在保存…';
    });
    await WebDavConfig.save(
      url: _urlController.text,
      username: _userController.text,
      password: _passController.text,
      providerName: _provider?.name ?? '自建',
    );
    await WebDavSyncService.instance.setEnabled(true);
    if (!mounted) return;
    setState(() {
      _enabled = true;
      _busy = false;
      _busyText = '';
      _step = _Step.done;
    });
    // 走完向导立刻同步一次：让用户马上看到"成了"，而不是等下次改动
    await _syncNow();
  }

  Future<void> _syncNow() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _busyText = '正在同步…';
      _syncMessage = '';
    });
    final result = await WebDavSyncService.instance.syncNow();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _busyText = '';
      _syncMessage = result?.message ?? '还没设置好，同步没跑';
      _syncFailed = result?.failed ?? true;
    });
  }

  Future<void> _disconnect() async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (BuildContext context) => CupertinoAlertDialog(
        title: const Text('断开同步？'),
        content: const Text('只是本机不再同步，网盘上已经存着的数据不会删。\n'
            '下次重新填一遍账号还能接着用。'),
        actions: [
          CupertinoDialogAction(
            child: const Text('取消'),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('断开'),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await WebDavConfig.clear();
    if (!mounted) return;
    setState(() {
      _enabled = false;
      _check = null;
      _syncMessage = '';
      _passController.text = '';
      _userController.text = '';
      _urlController.text = '';
      _provider = null;
      _step = _Step.choose;
    });
  }

  Future<void> _openPasswordPage() async {
    final url = _provider?.passwordPageUrl ?? '';
    if (url.isEmpty) return;
    try {
      await launchUrlString(url, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      setState(
          () => _check = const WebDavCheck(false, '打不开浏览器，请手动到网页版里生成应用密码'));
    }
  }

  // ------------------------------------------------------------- 界面

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('全平台同步'),
        trailing: _busy ? const CupertinoActivityIndicator(radius: 9) : null,
      ),
      child: AnimatedBuilder(
        animation: Listenable.merge(<Listenable>[
          WebDavConfig.revision,
          WebDavSyncService.revision,
        ]),
        builder: (BuildContext context, Widget? _) => ListView(
          padding: EdgeInsets.only(
            top: 12,
            bottom: 12 + MediaQuery.of(context).padding.bottom,
          ),
          children: [
            if (_busy) _busyBanner(),
            if (_syncMessage.isNotEmpty) _messageBanner(),
            ..._stepWidgets(),
          ],
        ),
      ),
    );
  }

  List<Widget> _stepWidgets() {
    switch (_step) {
      case _Step.choose:
        return <Widget>[_chooseSection()];
      case _Step.account:
        return <Widget>[_accountSection(), _actionsSection()];
      case _Step.done:
        return <Widget>[_doneSection()];
    }
  }

  Widget _busyBanner() => Padding(
        padding: const EdgeInsets.fromLTRB(32, 0, 32, 8),
        child: Row(
          children: [
            const CupertinoActivityIndicator(radius: 8),
            const SizedBox(width: 8),
            Text(_busyText, style: const TextStyle(fontSize: 13)),
          ],
        ),
      );

  Widget _messageBanner() {
    final color = _syncFailed ? CupertinoColors.systemRed : _accent;
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            _syncFailed
                ? CupertinoIcons.exclamationmark_circle_fill
                : CupertinoIcons.checkmark_circle_fill,
            size: 17,
            color: color,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _syncMessage,
              style: TextStyle(fontSize: 13, color: color),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------ 第 1 步：选网盘

  Widget _chooseSection() => CupertinoListSection.insetGrouped(
        backgroundColor: pageBackground(context),
        additionalDividerMargin: 2,
        header: const Text('第 1 步 / 共 3 步 · 选一个网盘'),
        footer: const Text('Elychron 会把数据存进这个网盘的 Elychron 文件夹里，'
            '不经过任何第三方服务器。\n'
            '别的设备（手机 / 电脑）填同一个账号，就能互相同步。'),
        children: <Widget>[
          for (final provider in WebDavProvider.presets)
            CupertinoListTile(
              title: Text(provider.name),
              subtitle: Text(
                provider.url,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const BackChervonRow(),
              onTap: () => _pickProvider(provider),
            ),
          CupertinoListTile(
            title: const Text('其他 / 自建'),
            subtitle: const Text('自己有 WebDAV 地址（Alist、服务器、其它网盘…）'),
            trailing: const BackChervonRow(),
            onTap: () => _pickProvider(null),
          ),
        ],
      );

  // ------------------------------------------------ 第 2 步：填账号

  Widget _accountSection() {
    final provider = _provider;
    return CupertinoListSection.insetGrouped(
      backgroundColor: pageBackground(context),
      additionalDividerMargin: 2,
      header: Text(
        provider == null
            ? '第 2 步 / 共 3 步 · 填账号'
            : '第 2 步 / 共 3 步 · ' + provider.name + ' 的账号',
      ),
      footer: Text('这里要填的是【应用密码】，不是登录密码。\n'
          '应用密码是专门给第三方程序用的，随时可以单独删掉，'
          '泄露了也不影响你的账号。\n\n'
          'Elychron 只把这组账号存在本机（密码存系统密钥库），'
          '不会上传给任何人。'),
      children: <Widget>[
        _textField(
          label: '地址',
          controller: _urlController,
          hint: 'https://dav.jianguoyun.com/dav/',
          keyboard: TextInputType.url,
        ),
        _textField(
          label: _usernameLabel,
          controller: _userController,
          hint: provider?.usernameHint ?? '登录名',
          onChanged: _onUsernameChanged,
          autocorrect: false,
        ),
        _textField(
          label: '应用密码',
          controller: _passController,
          hint: '不是登录密码',
          obscure: _obscure,
          autocorrect: false,
          trailing: CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: const Size(44, 32),
            onPressed: () => setState(() => _obscure = !_obscure),
            child: Icon(
              _obscure ? CupertinoIcons.eye : CupertinoIcons.eye_slash,
              size: 18,
            ),
          ),
        ),
        if (provider != null && provider.passwordPageUrl.isNotEmpty)
          CupertinoListTile(
            title: const Text('去生成应用密码'),
            subtitle: Text(provider.passwordHint),
            trailing: const BackChervonRow(),
            onTap: _openPasswordPage,
          )
        else if (provider != null)
          CupertinoListTile(
            title: const Text('应用密码在哪'),
            subtitle: Text(provider.passwordHint),
          ),
      ],
    );
  }

  Widget _textField({
    required String label,
    required TextEditingController controller,
    required String hint,
    TextInputType? keyboard,
    bool obscure = false,
    bool autocorrect = true,
    ValueChanged<String>? onChanged,
    Widget? trailing,
  }) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: CupertinoTextField(
                    controller: controller,
                    placeholder: hint,
                    obscureText: obscure,
                    autocorrect: autocorrect,
                    enableSuggestions: autocorrect,
                    keyboardType: keyboard,
                    onChanged: onChanged,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: CupertinoColors.tertiarySystemFill
                          .resolveFrom(context),
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 6),
                  trailing,
                ],
              ],
            ),
          ],
        ),
      );

  Widget _actionsSection() {
    final check = _check;
    return CupertinoListSection.insetGrouped(
      backgroundColor: pageBackground(context),
      additionalDividerMargin: 2,
      header: const Text('第 3 步 / 共 3 步 · 试一下'),
      footer: const Text('会在这个网盘上真的建一个文件夹、写一个小文件再读回来，'
          '能通过就说明这台设备以后同步没问题。'),
      children: <Widget>[
        CupertinoListTile(
          title: const Text('测试连接'),
          subtitle: check == null
              ? const Text('还没测过')
              : Text(
                  check.message,
                  style: TextStyle(
                    color: check.ok ? _accent : CupertinoColors.systemRed,
                  ),
                ),
          trailing: check != null && check.ok
              ? Icon(CupertinoIcons.checkmark_alt, color: _accent)
              : const BackChervonRow(),
          onTap: _busy ? null : _test,
        ),
        CupertinoListTile(
          title: const Text('保存并开始同步'),
          subtitle: Text(
            check != null && check.ok ? '点了就完成，并立刻同步一次' : '建议先点上面的"测试连接"',
          ),
          trailing: const BackChervonRow(),
          onTap: (_busy || check == null || !check.ok) ? null : _finish,
        ),
        CupertinoListTile(
          title: Text(
            '换一个网盘',
            style: TextStyle(
                color: CupertinoColors.systemGrey.resolveFrom(context)),
          ),
          onTap: _busy ? null : () => _pickProvider(null),
        ),
      ],
    );
  }

  // ------------------------------------------------ 已配置：管理

  Widget _doneSection() {
    final provider = _provider;
    final name = provider?.name ?? '自建';
    return CupertinoListSection.insetGrouped(
      backgroundColor: pageBackground(context),
      additionalDividerMargin: 2,
      header: const Text('同步'),
      footer: const Text('数据以明文存放在你自己的网盘里（Elychron 文件夹），'
          'Elychron 不提供、也看不到这些数据。'),
      children: <Widget>[
        CupertinoListTile(
          title: const Text('自动同步'),
          subtitle: Text(
            _enabled ? '改动后自动上传，启动时自动检查' : '已暂停，只能手动同步',
          ),
          trailing: CupertinoSwitch(
            value: _enabled,
            onChanged: (bool value) async {
              setState(() => _enabled = value);
              await WebDavSyncService.instance.setEnabled(value);
            },
          ),
        ),
        CupertinoListTile(
          title: const Text('立即同步'),
          subtitle: Text(WebDavSyncService.describeLastSync()),
          trailing: const BackChervonRow(),
          onTap: _busy ? null : _syncNow,
        ),
        // ===== W4：附件本体 =====
        //
        // 默认**关**：第一次打开就把几年的照片全传上去，会把坚果云免费版
        // 每月 1GB 的额度一把打光，而额度用尽是"整个同步都不动了"，
        // 比"有些文件没传"严重得多。所以由用户自己决定什么时候开。
        CupertinoListTile(
          title: const Text('同步附件文件'),
          subtitle: Text(
            _fileSync
                ? '照片、PPT 这些也会传（超过 50MB 或超出本月额度就不传）'
                : '关闭时只同步附件信息（名字/大小），文件本体不传',
          ),
          trailing: CupertinoSwitch(
            value: _fileSync,
            onChanged: (bool value) async {
              setState(() => _fileSync = value);
              await WebDavConfig.setFileSyncEnabled(value);
            },
          ),
        ),
        if (_fileSync)
          CupertinoListTile(
            title: const Text('本月流量'),
            subtitle: Text(
              '上传 ' +
                  WebDavFiles.formatBytes(WebDavConfig.uploadedBytesThisMonth) +
                  ' · 下载 ' +
                  WebDavFiles.formatBytes(
                      WebDavConfig.downloadedBytesThisMonth) +
                  '\n坚果云免费版每月上传 1GB（这里留了余量，到 900MB 就停）',
            ),
            trailing: WebDavConfig.uploadBudgetLeft < 100 * 1024 * 1024
                ? const Icon(CupertinoIcons.exclamationmark_triangle,
                    color: CupertinoColors.systemOrange)
                : null,
          ),
        CupertinoListTile(
          title: const Text('账号'),
          subtitle: Text(
            name + ' · ' + WebDavConfig.url + '\n' + WebDavConfig.username,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const BackChervonRow(),
          onTap: () => setState(() => _step = _Step.account),
        ),
        CupertinoListTile(
          title: Text(
            '断开同步',
            style: TextStyle(
                color: CupertinoColors.systemRed.resolveFrom(context)),
          ),
          subtitle: const Text('只清本机的账号，网盘上的数据不动'),
          trailing: const BackChervonRow(),
          onTap: _busy ? null : _disconnect,
        ),
      ],
    );
  }
}
