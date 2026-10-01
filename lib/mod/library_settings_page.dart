import 'package:celechron/design/app_route.dart';
import 'package:celechron/design/page_background.dart';
import 'package:celechron/design/section_text_style.dart';
import 'package:celechron/http/library_spider.dart';
import 'package:celechron/mod/library_config.dart';
import 'package:celechron/mod/library_login_page.dart';
import 'package:celechron/utils/platform_features.dart';
import 'package:flutter/cupertino.dart';

/// ===== 设置 → 校园服务 → 图书馆预约（2026-10-01）=====
///
/// 只做"登录 + 读数据"：**我的预约**（座位 / 研讨间 / 活动）。
/// 两条获取登录态的路径，都做：
///   A 粘贴 token —— 桌面端和兜底都靠它；
///   B 内置浏览器登录 —— 安卓/iOS，注入 JS 读 sessionStorage 里的 token。
///
/// ⚠️ 这站点认证用的是 `authorization: bearer<token>`，**不是 cookie**
/// （实测只带 PHPSESSID 会被判"您尚未登录"）。详见 docs/CAMPUS_SERVICES_PLAN.md 第四节。
class LibrarySettingsPage extends StatefulWidget {
  const LibrarySettingsPage({super.key});

  @override
  State<LibrarySettingsPage> createState() => _LibrarySettingsPageState();
}

class _LibrarySettingsPageState extends State<LibrarySettingsPage> {
  final TextEditingController _tokenController = TextEditingController();
  bool _busy = false;
  String? _result;

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _run(Future<String> Function() action) async {
    setState(() {
      _busy = true;
      _result = null;
    });
    String message;
    try {
      message = await action();
    } on Object catch (error) {
      // 带上"当前存着的 token 长度"：一眼能看出是"压根没存进去"还是"存了但被服务端拒"
      message = error.toString() + '｜token 长度=' + LibraryConfig.token.length.toString();
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = message;
    });
    await LibraryConfig.setLastResult(message);
    // 副标题会被截断，所以完整文案用弹窗给（用户能看全，也能顺手截图给我）
    if (message.length > 24) {
      await showCupertinoDialog<void>(
        context: this.context,
        builder: (BuildContext context) => CupertinoAlertDialog(
          title: const Text('结果'),
          content: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(message, style: const TextStyle(fontSize: 14)),
            ),
          ),
          actions: <Widget>[
            CupertinoDialogAction(
              child: const Text('知道了'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      );
    }
  }

  /// A：粘贴 token（先验再存）
  Future<void> _saveToken() async {
    final value = _tokenController.text.trim();
    if (value.isEmpty) return;
    await _run(() async {
      final spider = LibrarySpider.withToken(value);
      try {
        final name = await spider.verify();
        await LibraryConfig.setToken(value);
        _tokenController.clear();
        return name.isEmpty ? '连接成功' : '连接成功：' + name;
      } finally {
        spider.close();
      }
    });
  }

  /// B：内置浏览器登录（安卓/iOS）
  Future<void> _loginWithWebView() async {
    final result = await Navigator.of(context, rootNavigator: true).push<String>(
      appPageRoute<String>(
        builder: (BuildContext context) => const LibraryLoginPage(),
      ),
    );
    if (!mounted || result == null) return;
    setState(() => _result = result);
    await LibraryConfig.setLastResult(result);
    await _readReservations();
  }

  /// 读一次我的预约（这是这个功能真正要的东西）
  Future<void> _readReservations() async {
    final token = LibraryConfig.token;
    if (token.isEmpty) {
      setState(() => _result = '还没填 token');
      return;
    }
    await _run(() async {
      final spider = LibrarySpider.withToken(token);
      try {
        final list = await spider.myReservations();
        if (list.isEmpty) return '已连接，当前没有预约';
        final first = list.first;
        final when = first.start == null ? '' : '（最近 ' + first.start!.toString().substring(5, 16) + '）';
        return '共 ' + list.length.toString() + ' 条预约' + when;
      } finally {
        spider.close();
      }
    });
  }

  Future<void> _clearToken() async {
    final ok = await showCupertinoDialog<bool>(
      context: this.context,
      builder: (BuildContext context) => CupertinoAlertDialog(
        title: const Text('清除图书馆登录信息'),
        content: const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('清除后不再读取预约；已经建好的待办不受影响。', style: TextStyle(fontSize: 14)),
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
    await clearLibraryWebViewCookies();
    if (mounted) setState(() => _result = null);
  }

  @override
  Widget build(BuildContext context) {
    final hasToken = LibraryConfig.token.isNotEmpty;
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
              '登上之后，图书馆的预约会变成待办/日程（预约是时段，有开始也有结束）。'
              '只读：不替你预约、也不取消。',
            ),
            children: <Widget>[
              CupertinoListTile(
                title: const Text('启用图书馆预约'),
                subtitle: Text(
                  LibraryConfig.enabled
                      ? (LibraryConfig.lastResult.isEmpty ? '已开启' : LibraryConfig.lastResult)
                      : '关闭中',
                ),
                trailing: CupertinoSwitch(
                  value: LibraryConfig.enabled,
                  onChanged: (bool value) async {
                    await LibraryConfig.setEnabled(value);
                    if (mounted) setState(() {});
                  },
                ),
              ),
            ],
          ),
          CupertinoListSection.insetGrouped(
            backgroundColor: pageBackground(context),
            header: sectionHeader(context, '登录'),
            footer: sectionFooter(
              context,
              PlatformFeatures.hasWebViewLogin
                  ? '上面那个按钮会打开内置浏览器，你正常登录一次就行。'
                      '不想用它？也可以从桌面浏览器 F12 → Application → Session Storage → 复制 token 贴到下面。'
                  : '桌面端没有内置浏览器：请在浏览器登录后 F12 → Application → Session Storage → '
                      '复制 token 贴到下面。',
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
                  title: const Text('当前'),
                  subtitle: Text(LibraryConfig.maskedToken),
                  trailing: CupertinoButton(
                    padding: EdgeInsets.zero,
                    child: const Text('清除',
                        style: TextStyle(color: CupertinoColors.systemRed)),
                    onPressed: _busy ? null : _clearToken,
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Column(
                  children: <Widget>[
                    CupertinoTextField(
                      controller: _tokenController,
                      placeholder: '粘贴 token（很长的一串）',
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
                        child: const Text('保存并测试', style: TextStyle(fontSize: 15)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          CupertinoListSection.insetGrouped(
            backgroundColor: pageBackground(context),
            header: sectionHeader(context, '数据'),
            footer: sectionFooter(context, '只读：不会替你预约、也不会取消任何预约。'),
            children: <Widget>[
              CupertinoListTile(
                title: const Text('读取我的预约'),
                subtitle: Text(_result ?? (hasToken ? '点一下看看有几条' : '先登录或粘贴 token')),
                trailing: _busy
                    ? const CupertinoActivityIndicator()
                    : const Icon(CupertinoIcons.arrow_clockwise, size: 18),
                onTap: _busy ? null : _readReservations,
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
    if (LibraryConfig.enabled) {
      final last = LibraryConfig.lastResult;
      subtitle = last.isEmpty ? '已开启' : last;
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
