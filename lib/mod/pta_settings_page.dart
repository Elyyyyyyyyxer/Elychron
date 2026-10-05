import 'package:celechron/design/app_route.dart';
import 'package:celechron/design/page_background.dart';
import 'package:celechron/design/section_text_style.dart';
import 'package:celechron/mod/pta_homework.dart';
import 'package:celechron/mod/pta_login_page.dart';
import 'package:celechron/utils/platform_features.dart';
import 'package:celechron/utils/utils.dart';
import 'package:flutter/cupertino.dart';
import 'package:url_launcher/url_launcher_string.dart';

/// ===== 设置 → 校园服务 → PTA（拼题A）=====
///
/// 只做一件事：把 PTA 上**还没截止**的题目集/考试读回来，交给 App 当成作业
/// （于是自动进待办、提醒、通知，和学在浙大作业同等对待）。
///
/// 认证只有一条路：粘贴浏览器里的 PTASession（实测「学号登录」对这个账号
/// 没开、手机号登录要过腾讯验证码）。所以这一页的重点是把"去哪拿、怎么算过期"
/// 说清楚，而不是堆选项。侦察结论见 docs/PTA_RECON.md。
class PtaSettingsPage extends StatefulWidget {
  const PtaSettingsPage({super.key});

  @override
  State<PtaSettingsPage> createState() => _PtaSettingsPageState();
}

class _PtaSettingsPageState extends State<PtaSettingsPage> {
  final TextEditingController _cookieController = TextEditingController();
  bool _busy = false;
  String? _result;

  @override
  void dispose() {
    _cookieController.dispose();
    super.dispose();
  }

  Future<void> _run(Future<String> Function() action) async {
    setState(() {
      _busy = true;
      _result = null;
    });
    final result = await action();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = result;
    });
  }

  Future<void> _saveCookie() async {
    final value = _cookieController.text.trim();
    if (value.isEmpty) return;
    await PtaHomework.setCookie(value);
    _cookieController.clear();
    if (!mounted) return;
    // 存完顺手验一次，省得用户猜"到底填对没有"
    await _run(() => PtaHomework.testConnection());
  }

  Future<void> _clearCookie() async {
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (BuildContext context) => CupertinoAlertDialog(
        title: const Text('清除 PTA 登录信息'),
        content: const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
              '清除后不再自动更新 PTA 作业；内置浏览器里的登录状态也会一起清掉'
              '（下次要重新登录一次）。已经建好的待办不受影响。',
              style: TextStyle(fontSize: 14)),
        ),
        actions: [
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
    await PtaHomework.clearCookie();
    // 只清 App 里那份是不够的：内置浏览器有它自己的 cookie 库，
    // 不清的话下次打开登录页会"自动通过"（实测踩过）。两份一起清。
    await clearPtaWebViewCookies();
    if (mounted) setState(() => _result = null);
  }

  /// 用内置浏览器登录（安卓/iOS）。成功就顺手把开关打开 —— 用户点这个按钮，
  /// 意思就是要用它。
  Future<void> _loginWithWebView() async {
    final result = await Navigator.of(context, rootNavigator: true).push<String>(
      appPageRoute<String>(
        builder: (BuildContext context) => const PtaLoginPage(),
      ),
    );
    if (!mounted || result == null) return;
    await PtaHomework.setEnabled(true);
    if (!mounted) return;
    await _run(() => PtaHomework.refresh(force: true));
  }

  Future<void> _openPintia() async {
    try {
      await launchUrlString('https://pintia.cn/', mode: LaunchMode.externalApplication);
    } catch (_) {
      // 打不开浏览器就算了
    }
  }

  String get _lastSyncText {
    final raw = PtaHomework.lastSyncAt;
    if (raw.isEmpty) return '还没同步过';
    final at = DateTime.tryParse(raw);
    if (at == null) return '还没同步过';
    return '上次同步：' + toStringHumanReadable(at);
  }

  @override
  Widget build(BuildContext context) {
    final hasCookie = PtaHomework.cookie.isNotEmpty;
    return CupertinoPageScaffold(
      backgroundColor: pageBackground(context),
      navigationBar: const CupertinoNavigationBar(middle: Text('PTA 拼题A')),
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
              'PTA 上还没截止的作业会自动变成待办（和学在浙大作业一样）。'
              '当堂实验 / 上机不算。',
            ),
            children: <Widget>[
              CupertinoListTile(
                title: const Text('启用 PTA 作业'),
                subtitle: Text(
                  PtaHomework.configured
                      ? (PtaHomework.lastResult.isEmpty
                          ? '已配置'
                          : PtaHomework.lastResult)
                      : (hasCookie ? '填了，但还没开启' : '还没有填 PTASession'),
                ),
                trailing: CupertinoSwitch(
                  value: PtaHomework.enabled,
                  onChanged: (bool value) async {
                    await PtaHomework.setEnabled(value);
                    if (!mounted) return;
                    setState(() {});
                    if (value && PtaHomework.cookie.isNotEmpty) {
                      await _run(() => PtaHomework.refresh(force: true));
                    }
                  },
                ),
              ),
              CupertinoListTile(
                title: const Text('当堂实验 / 上机也算作业'),
                subtitle: Text(
                  PtaHomework.includeInClass
                      ? '也算：课上做的也会变成待办'
                      : '不算：只把课后作业变成待办（推荐）',
                ),
                trailing: CupertinoSwitch(
                  value: PtaHomework.includeInClass,
                  onChanged: (bool value) async {
                    await PtaHomework.setIncludeInClass(value);
                    if (!mounted) return;
                    setState(() {});
                    await _run(() => PtaHomework.refresh(force: true));
                  },
                ),
              ),
            ],
          ),
          CupertinoListSection.insetGrouped(
            backgroundColor: pageBackground(context),
            header: sectionHeader(context, 'PTASession'),
            footer: sectionFooter(
              context,
              '上面那个按钮会打开内置浏览器，你正常登录一次就行。'
              '不想用它？也可以从桌面浏览器按 F12 → Application → Cookies 复制 '
              'PTASession 的值贴到下面。它不是密码，但别发给别人。',
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
              if (hasCookie)
                CupertinoListTile(
                  title: const Text('当前'),
                  subtitle: Text(PtaHomework.maskedCookie),
                  trailing: CupertinoButton(
                    padding: EdgeInsets.zero,
                    child: const Text('清除',
                        style: TextStyle(color: CupertinoColors.systemRed)),
                    onPressed: _busy ? null : _clearCookie,
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Column(
                  children: <Widget>[
                    CupertinoTextField(
                      controller: _cookieController,
                      placeholder: '粘贴 PTASession 的值',
                      obscureText: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: CupertinoColors.tertiarySystemFill
                            .resolveFrom(context),
                        borderRadius: BorderRadius.circular(9),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: CupertinoButton.filled(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        onPressed: _busy ? null : _saveCookie,
                        child: const Text('保存并测试'),
                      ),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: double.infinity,
                      child: CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: _openPintia,
                        child: const Text('打开 pintia.cn 去登录',
                            style: TextStyle(fontSize: 14)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          CupertinoListSection.insetGrouped(
            backgroundColor: pageBackground(context),
            header: sectionHeader(context, '同步'),
            footer: sectionFooter(
              context,
              '只读：不会提交作业，也不会改你的账号。',
            ),
            children: <Widget>[
              CupertinoListTile(
                title: const Text('测试连接'),
                subtitle: Text(_result ?? '验证 cookie 还有没有效'),
                trailing: _busy
                    ? const CupertinoActivityIndicator()
                    : const Icon(CupertinoIcons.bolt, size: 18),
                onTap: _busy ? null : () => _run(() => PtaHomework.testConnection()),
              ),
              CupertinoListTile(
                title: const Text('立即同步'),
                subtitle: Text(_lastSyncText),
                trailing: _busy
                    ? const CupertinoActivityIndicator()
                    : const Icon(CupertinoIcons.arrow_clockwise, size: 18),
                onTap: _busy ? null : () => _run(() => PtaHomework.refresh(force: true)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// ===== 设置页里的那一行（校园服务分组）=====
///
/// 副标题要能一眼看出"开没开、上次同步成不成功"，因为用户不会为了确认
/// 专门点进去（和全平台同步那一行同一个思路）。
class PtaHomeworkTile extends StatefulWidget {
  const PtaHomeworkTile({super.key});

  @override
  State<PtaHomeworkTile> createState() => _PtaHomeworkTileState();
}

class _PtaHomeworkTileState extends State<PtaHomeworkTile> {
  String get _subtitle {
    if (!PtaHomework.enabled) return '关闭中；把 PTA 的作业也变成待办';
    if (PtaHomework.cookie.isEmpty) return '已开启，但还没填 PTASession';
    if (PtaHomework.lastResult.isEmpty) return '已开启';
    return PtaHomework.lastResult;
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoListTile(
      // 用户要求：显示名从「PTA 拼题A」简化成「PTA」（包名/类名/文件名都不动）
      title: const Text('PTA'),
      subtitle: Text(_subtitle),
      trailing: const Icon(CupertinoIcons.arrow_right,
          size: 18, color: CupertinoColors.tertiaryLabel),
      onTap: () async {
        await Navigator.of(context, rootNavigator: true).push(
          appPageRoute<void>(
            builder: (BuildContext context) => const PtaSettingsPage(),
          ),
        );
        if (mounted) setState(() {});
      },
    );
  }
}
