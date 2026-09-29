import 'package:celechron/design/app_accent.dart';
import 'package:celechron/design/page_background.dart';
import 'package:celechron/mod/focus_device.dart';
import 'package:celechron/mod/webdav_client.dart';
import 'package:celechron/mod/webdav_config.dart';
import 'package:celechron/mod/webdav_files.dart';
import 'package:celechron/mod/webdav_providers.dart';
import 'package:celechron/mod/webdav_status.dart';
import 'package:celechron/mod/webdav_sync.dart';
import 'package:celechron/mod/webdav_sync_service.dart';
import 'package:celechron/page/option/option_view.dart' show BackChervonRow;
import 'package:flutter/cupertino.dart';
import 'package:url_launcher/url_launcher_string.dart';

/// 分组标题/脚注的灰。**与设置页其它分组用同一个值**
/// （见 page/option/option_view.dart 里的同名常量）——
/// 单独调会让一个页面里的分组标题颜色对不上。
const Color _kHeaderFooterColor = CupertinoDynamicColor(
  color: Color.fromRGBO(108, 108, 108, 1.0),
  darkColor: Color.fromRGBO(142, 142, 146, 1.0),
  highContrastColor: Color.fromRGBO(74, 74, 77, 1.0),
  darkHighContrastColor: Color.fromRGBO(176, 176, 183, 1.0),
  elevatedColor: Color.fromRGBO(108, 108, 108, 1.0),
  darkElevatedColor: Color.fromRGBO(142, 142, 146, 1.0),
  highContrastElevatedColor: Color.fromRGBO(108, 108, 108, 1.0),
  darkHighContrastElevatedColor: Color.fromRGBO(142, 142, 146, 1.0),
);

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
      // 底色显式给：下面那些分组（CupertinoListSection）自带 pageBackground
      // 的底色，Scaffold 用默认白的话，内容不满一屏时底部会露一条白边。
      backgroundColor: pageBackground(context),
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
            // 管理页（向导走完之后）不显示这两条横幅：结论、细节、"正在同步"
            // 都已经在顶部状态卡里了，再来一条就是同一句话出现两次。
            if (_step != _Step.done) ...[
              if (_busy) _busyBanner(),
              if (_syncMessage.isNotEmpty) _messageBanner(),
            ],
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
        return _doneWidgets();
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
    final color = _syncFailed ? CupertinoColors.systemRed : AppAccent.primary;
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
        header: _sectionHeader('第 1 步 / 共 3 步 · 选一个网盘'),
        footer: _sectionFooter('Elychron 会把数据存进这个网盘的 Elychron 文件夹里，'
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
    // ===== 真机上发现的坑（2026-09-28）=====
    // 服务商那句说明原来当**输入框占位符**用：又长又被截断，
    // 而且里面写着 markdown 的星号加粗 —— 输入框不渲染它，屏幕上直接冒出一对 **。
    // 现在放说明文字里：不截断，也不用加粗。
    final providerNote = provider == null ? '' : provider.usernameHint + '\n\n';
    final footerText = '这里要填的是【应用密码】，不是登录密码。\n'
            '应用密码是专门给第三方程序用的，随时可以单独删掉，'
            '泄露了也不影响你的账号。\n\n' +
        providerNote +
        'Elychron 只把这组账号存在本机（密码存系统密钥库），'
            '不会上传给任何人。';
    return CupertinoListSection.insetGrouped(
      backgroundColor: pageBackground(context),
      additionalDividerMargin: 2,
      header: _sectionHeader(
        provider == null
            ? '第 2 步 / 共 3 步 · 填账号'
            : '第 2 步 / 共 3 步 · ' + provider.name + ' 的账号',
      ),
      footer: _sectionFooter(footerText),
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
          hint: provider == null
              ? '登录名'
              : (provider.usernameIsEmail ? '注册邮箱' : '用户名'),
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
      header: _sectionHeader('第 3 步 / 共 3 步 · 试一下'),
      footer: _sectionFooter('会在这个网盘上真的建一个文件夹、写一个小文件再读回来，'
          '能通过就说明这台设备以后同步没问题。'),
      children: <Widget>[
        CupertinoListTile(
          title: const Text('测试连接'),
          subtitle: check == null
              ? const Text('还没测过')
              : Text(
                  check.message,
                  style: TextStyle(
                    color: check.ok ? AppAccent.primary : CupertinoColors.systemRed,
                  ),
                ),
          trailing: check != null && check.ok
              ? Icon(CupertinoIcons.checkmark_alt, color: AppAccent.primary)
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
  //
  // ===== 2026-09-29 重做（用户原话：「现在的手机端全平台同步界面有点丑」）=====
  //
  // 旧版是一列 CupertinoListTile，把开关、按钮、流量、账号、断开同步全塞进
  // 同一个分组里 —— 而且"断开同步"就在中间，手指一滑就点到了。
  //
  // 现在从上到下的顺序 = 从"你最常看"到"你几乎不会碰"：
  //   1. 状态卡：一句话结论 + 上次同步时间 + 具体细节 + 一个大按钮
  //   2. 流量卡（只在传附件时出现）：进度条，别让用户自己算数字
  //   3. 开关分组：自动同步 / 同步附件文件
  //   4. 账号分组：网盘 + 账号（点进去能改）
  //   5. 危险分组：断开同步，单独一块，沉底
  List<Widget> _doneWidgets() {
    final name = WebDavConfig.providerName.isNotEmpty
        ? WebDavConfig.providerName
        : (_provider?.name ?? '自建');
    return <Widget>[
      _statusCard(name),
      if (_fileSync) _trafficCard(),
      _switchSection(),
      _accountSectionDone(name),
      _dangerSection(),
    ];
  }

  // ------------------------------------------------------------ 取色
  //
  // 全部走 Cupertino 的动态色（深色模式自动跟着变），不要在界面里写死颜色。

  Color get _secondary =>
      CupertinoColors.secondaryLabel.resolveFrom(context);

  Color get _tertiary => CupertinoColors.tertiaryLabel.resolveFrom(context);

  Color get _cardColor => CupertinoDynamicColor.resolve(
      CupertinoColors.secondarySystemGroupedBackground, context);

  Color get _fillColor =>
      CupertinoDynamicColor.resolve(CupertinoColors.tertiarySystemFill, context);

  /// 状态色：成功用品牌粉（与"测试连接"那个对勾同一套），失败红，其余灰。
  Color _statusColor(SyncStatusKind kind) {
    switch (kind) {
      case SyncStatusKind.ok:
      case SyncStatusKind.syncing:
        return AppAccent.primary;
      case SyncStatusKind.failed:
        return CupertinoColors.systemRed.resolveFrom(context);
      case SyncStatusKind.never:
      case SyncStatusKind.paused:
        return CupertinoColors.systemGrey.resolveFrom(context);
    }
  }

  Widget _card({
    required Widget child,
    Color? border,
    EdgeInsetsGeometry padding = const EdgeInsets.fromLTRB(16, 14, 16, 14),
  }) =>
      Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        padding: padding,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: _cardColor,
          border: border == null ? null : Border.all(color: border, width: 1),
          // 页面底色统一成白之后，白卡在白底上会"消失"（只有一圈粉边那张还能看出来）。
          // 所以用日程/待办那套卡片的投影口径（见 design/round_rectangle_card.dart）：
          // 浅色下投影，深色下不投影（深色里靠底色区分本来就够）。
          boxShadow: CupertinoTheme.of(context).brightness == Brightness.dark
              ? null
              : const <BoxShadow>[
                  BoxShadow(
                    color: CupertinoColors.systemGrey5,
                    spreadRadius: 0,
                    blurRadius: 12,
                    offset: Offset(0, 6),
                  ),
                ],
        ),
        child: child,
      );

  /// 分组标题 / 脚注的字号。
  ///
  /// CupertinoListSection 默认拿 textTheme.textStyle（17pt、正文色）当标题 ——
  /// 那样分组标题会比卡片里的列表项本身还抢眼，整页看起来又黑又乱。
  /// 真机上就是这么发现它跟设置页其它分组对不上的。
  TextStyle get _sectionTextStyle => CupertinoTheme.of(context)
      .textTheme
      .textStyle
      .merge(TextStyle(
        fontSize: 13.0,
        color: CupertinoDynamicColor.resolve(_kHeaderFooterColor, context),
      ));

  Widget _sectionHeader(String text) => Container(
        padding: const EdgeInsets.only(left: 16),
        child: Text(text, style: _sectionTextStyle),
      );

  Widget _sectionFooter(String text) => Container(
        padding: const EdgeInsets.only(left: 16),
        child: Text(text, style: _sectionTextStyle),
      );

  Widget _pill(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      );

  // ------------------------------------------------------------ 1 状态卡

  Widget _statusCard(String name) {
    final service = WebDavSyncService.instance;
    final busy = _busy || service.running;
    final status = describeSyncStatus(
      enabled: _enabled,
      running: busy,
      lastSyncAt: WebDavConfig.lastSyncAt,
      lastSummary: WebDavConfig.lastSummary,
      lastFailed: WebDavConfig.lastFailed,
    );
    final color = _statusColor(status.kind);
    return _card(
      border: AppAccent.soft(0.30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 8,
                height: 8,
                decoration:
                    BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 7),
              Text(
                name,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _secondary,
                ),
              ),
              const Spacer(),
              _pill(_enabled ? '自动同步中' : '已暂停', color),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            status.headline,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            status.timeLine,
            style: TextStyle(fontSize: 12.5, color: _tertiary),
          ),
          if (status.detail.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: _fillColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                status.detail,
                style: const TextStyle(fontSize: 13, height: 1.35),
              ),
            ),
          ],
          const SizedBox(height: 14),
          _syncButton(busy),
        ],
      ),
    );
  }

  Widget _syncButton(bool busy) => SizedBox(
        width: double.infinity,
        child: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          borderRadius: BorderRadius.circular(12),
          color: AppAccent.primary,
          disabledColor: AppAccent.soft(0.45),
          onPressed: busy ? null : _syncNow,
          child: SizedBox(
            height: 44,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (busy) ...<Widget>[
                    const CupertinoActivityIndicator(
                      radius: 8,
                      color: CupertinoColors.white,
                    ),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    busy ? '正在同步…' : '立即同步',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: CupertinoColors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  // ------------------------------------------------------------ 2 流量卡

  Widget _trafficCard() {
    final up = WebDavConfig.uploadedBytesThisMonth;
    final down = WebDavConfig.downloadedBytesThisMonth;
    const budget = WebDavConfig.monthlyUploadBudget;
    final left = WebDavConfig.uploadBudgetLeft;
    final ratio = budget <= 0 ? 0.0 : (up / budget).clamp(0.0, 1.0);
    // 用了一点点也要看得见：2.6% 的进度条在手机上就是一条看不见的缝，
    // 用户会以为"没在传"。给一个最小可见宽度（纯视觉，数字还是真的）。
    final shown = ratio <= 0 ? 0.0 : (ratio < 0.03 ? 0.03 : ratio);
    final tight = left < 100 * 1024 * 1024;
    final color = tight
        ? CupertinoColors.systemOrange.resolveFrom(context)
        : AppAccent.primary;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                '本月流量',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _secondary,
                ),
              ),
              const Spacer(),
              Text(
                WebDavFiles.formatBytes(up) +
                    ' / ' +
                    WebDavFiles.formatBytes(budget),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: tight ? color : _tertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 7,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  ColoredBox(color: _fillColor),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: shown,
                      heightFactor: 1,
                      child: ColoredBox(color: color),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 9),
          Text(
            tight
                ? '本月上传额度快用完了（还剩 ' +
                    WebDavFiles.formatBytes(left) +
                    '），到 900MB 会暂停传附件'
                : '本月已下载 ' +
                    WebDavFiles.formatBytes(down) +
                    ' · 坚果云免费版每月上传 1GB，这里留了余量（到 900MB 停）',
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              color: tight ? color : _tertiary,
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ 3 开关分组

  Widget _switchSection() => CupertinoListSection.insetGrouped(
        backgroundColor: pageBackground(context),
        additionalDividerMargin: 2,
        header: _sectionHeader('同步设置'),
        children: <Widget>[
          CupertinoListTile(
            title: const Text('自动同步'),
            subtitle: Text(
              _enabled ? '改动后上传，启动时检查，每 3 分钟问一次' : '已暂停，只能手动同步',
            ),
            trailing: CupertinoSwitch(
              value: _enabled,
              onChanged: (bool value) async {
                setState(() => _enabled = value);
                await WebDavSyncService.instance.setEnabled(value);
              },
            ),
          ),
          // ===== W4：附件本体 =====
          //
          // 默认关：第一次打开就把几年的照片全传上去，会把坚果云免费版
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
                // 打开后立刻跑一轮：否则要等到下一次数据改动才会上传附件，
                // 用户会以为开关没生效（真机验收时就是这么发现的：开关是绿的，
                // 流量却一直是 0 B）。
                if (value) await _syncNow();
              },
            ),
          ),
        ],
      );

  // ------------------------------------------------------------ 4 账号分组

  Widget _accountSectionDone(String name) => CupertinoListSection.insetGrouped(
        backgroundColor: pageBackground(context),
        additionalDividerMargin: 2,
        header: _sectionHeader('账号'),
        footer: _sectionFooter('数据以明文存放在你自己的网盘里（Elychron 文件夹），'
            'Elychron 不提供、也看不到这些数据。'),
        children: <Widget>[
          CupertinoListTile(
            title: Text(name + ' · ' + WebDavConfig.username),
            subtitle: Text(
              WebDavConfig.url,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const BackChervonRow(),
            onTap: () => setState(() => _step = _Step.account),
          ),
        ],
      );

  // ------------------------------------------------------------ 5 危险分组

  Widget _dangerSection() => CupertinoListSection.insetGrouped(
        backgroundColor: pageBackground(context),
        additionalDividerMargin: 2,
        children: <Widget>[
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
