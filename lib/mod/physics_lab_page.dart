import 'package:celechron/design/adaptive_form_body.dart';
import 'package:celechron/design/app_accent.dart';
import 'package:celechron/design/app_route.dart';
import 'package:celechron/design/page_background.dart';
import 'package:celechron/mod/physics_lab_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:webview_flutter/webview_flutter.dart';

class PhysicsLabTile extends StatelessWidget {
  const PhysicsLabTile({super.key});
  @override
  Widget build(BuildContext context) => CupertinoListTile(
        title: const Text('普物实验'),
        subtitle: const Text('登录选课系统，自动同步实验课表'),
        trailing: const CupertinoListTileChevron(),
        onTap: () => Navigator.of(context, rootNavigator: true)
            .push(appPageRoute<void>(builder: (_) => const PhysicsLabPage())),
      );
}

class PhysicsLabPage extends StatefulWidget {
  const PhysicsLabPage({super.key});
  @override
  State<PhysicsLabPage> createState() => _PhysicsLabPageState();
}

class _PhysicsLabPageState extends State<PhysicsLabPage> {
  final service = PhysicsLabService.instance;
  bool busy = true;
  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    await service.start();
    if (mounted) setState(() => busy = false);
  }

  Future<void> _refresh() async {
    setState(() => busy = true);
    await service.refresh(force: true);
    if (mounted) setState(() => busy = false);
  }

  Future<void> _login() async {
    await Navigator.of(context)
        .push(appPageRoute<void>(builder: (_) => const PhysicsLabLoginPage()));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
        backgroundColor: pageBackground(context),
        navigationBar: const CupertinoNavigationBar(middle: Text('普物实验')),
        child: SafeArea(
            child: AdaptiveFormBody(
                child: ValueListenableBuilder<String>(
          valueListenable: service.status,
          builder: (context, status, _) => ListView(children: [
            CupertinoListSection.insetGrouped(children: [
              CupertinoListTile(
                  title: const Text('登录选课系统'),
                  trailing: const CupertinoListTileChevron(),
                  onTap: busy || !service.available ? null : _login),
              CupertinoListTile(
                  title: const Text('自动同步实验课表'),
                  trailing: CupertinoSwitch(
                      value: service.enabled,
                      activeTrackColor: AppAccent.primary,
                      onChanged: busy
                          ? null
                          : (value) async {
                              setState(() => busy = true);
                              await service.setEnabled(value);
                              if (mounted) setState(() => busy = false);
                            })),
              CupertinoListTile(
                  title: const Text('立即同步'),
                  trailing: busy ? const CupertinoActivityIndicator() : null,
                  onTap: busy || !service.enabled ? null : _refresh),
            ]),
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                    service.available
                        ? '$status\n需要校园网或学校 VPN。实验显示在课程表和日历中。'
                        : '当前平台暂不支持内置网页登录',
                    style: const TextStyle(fontSize: 13))),
            if (service.lessons.isNotEmpty)
              CupertinoListSection.insetGrouped(
                  header: const Text('已选实验'),
                  footer:
                      const Text('仅提供开始时间时，参考课表转换项目按 2 小时 25 分钟显示；请核对实际安排。'),
                  children: [
                    for (final lesson in service.lessons)
                      CupertinoListTile(
                        title: Text(lesson.title),
                        subtitle: Text(
                            '${lesson.start.toIso8601String().substring(0, 16).replaceFirst('T', ' ')} · ${lesson.location}'),
                      )
                  ]),
          ]),
        ))),
      );
}

class PhysicsLabLoginPage extends StatefulWidget {
  const PhysicsLabLoginPage({super.key});
  @override
  State<PhysicsLabLoginPage> createState() => _PhysicsLabLoginPageState();
}

class _PhysicsLabLoginPageState extends State<PhysicsLabLoginPage> {
  final service = PhysicsLabService.instance;
  WebViewController? controller;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    controller = service.loginController();
    service.loadLogin();
  }

  Future<void> _finish() async {
    setState(() => busy = true);
    final success = await service.refresh(force: true, connect: true);
    if (!mounted) return;
    setState(() => busy = false);
    if (success) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !busy,
        child: CupertinoPageScaffold(
          navigationBar: CupertinoNavigationBar(
              middle: const Text('登录普物实验'),
              trailing: busy
                  ? const CupertinoActivityIndicator()
                  : CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: _finish,
                      child: const Text('完成'))),
          child: SafeArea(
              child: Column(children: [
            ValueListenableBuilder<String>(
                valueListenable: service.status,
                builder: (_, status, __) => Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text('$status\n在官网页面登录，进入“我的课表”后点击完成',
                        style: const TextStyle(fontSize: 13)))),
            Expanded(
                child: AbsorbPointer(
                    absorbing: busy,
                    child: WebViewWidget(controller: controller!))),
          ])),
        ),
      );
}
