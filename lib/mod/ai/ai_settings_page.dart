import 'dart:async';

import 'package:celechron/mod/ai/deepseek.dart';
import 'package:celechron/mod/ai/model_resolver.dart';
import 'package:flutter/cupertino.dart';
import 'package:celechron/design/page_background.dart';

/// 设置 → AI 智能助手
///
/// 只做配置 + 连通性验证。真正的功能（解析分享内容、拆子待办）在
/// `lib/mod/ai/ai_tasks.dart` 里，把这一页保持成一个纯粹的设置页。
class AiSettingsPage extends StatefulWidget {
  const AiSettingsPage({super.key});

  @override
  State<AiSettingsPage> createState() => _AiSettingsPageState();
}

class _AiSettingsPageState extends State<AiSettingsPage> {
  final _keyController = TextEditingController();
  final _baseUrlController = TextEditingController();
  bool _testing = false;
  bool _refreshing = false;
  String? _modelError;
  String? _testResult;
  bool _testOk = false;

  @override
  void initState() {
    super.initState();
    AiConfig.load().then((_) async {
      if (!mounted) return;
      setState(() {});
      // 打开设置页时顺手刷新模型列表：让用户永远看到官方真实的模型名
      if (AiConfig.apiKey.isNotEmpty &&
          !ModelResolver.isFresh(AiConfig.modelsFetchedAt)) {
        await _refreshModels();
      }
    });
    _baseUrlController.text = AiConfig.baseUrl;
  }

  @override
  void dispose() {
    _keyController.dispose();
    _baseUrlController.dispose();
    super.dispose();
  }

  Future<void> _saveKey() async {
    final value = _keyController.text.trim();
    if (value.isEmpty) return;

    // 最常见的一种填错：把文档网址当成密钥粘进来了
    if (value.startsWith('http://') || value.startsWith('https://')) {
      final useAsUrl = await showCupertinoDialog<bool>(
        context: context,
        builder: (BuildContext context) => CupertinoAlertDialog(
          title: const Text('这看起来是网址'),
          content: const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              '密钥一般是 sk- 开头的一串字符，不是网址。\n\n'
              '要把这个地址填到下面的接口地址里吗？',
              style: TextStyle(fontSize: 14),
            ),
          ),
          actions: [
            CupertinoDialogAction(
              child: const Text('重新填写'),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              child: const Text('填到接口地址'),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      );
      if (useAsUrl == true) {
        await AiConfig.setBaseUrl(value);
        _baseUrlController.text = AiConfig.baseUrl;
        _keyController.clear();
        if (mounted) setState(() => _testResult = null);
      }
      return;
    }

    await AiConfig.setApiKey(value);
    _keyController.clear();
    if (!mounted) return;
    setState(() {
      _testResult = null;
    });
  }

  /// 重新问官方要模型列表，并按便宜档优先挑一个
  Future<void> _refreshModels() async {
    if (!mounted) return;
    setState(() {
      _refreshing = true;
      _modelError = null;
    });
    try {
      final picked = await ModelResolver.resolve(force: true);
      if (picked.isEmpty && !AiConfig.isManualModel && mounted) {
        setState(() => _modelError = '未获取到模型列表。请手动填模型名。');
      }
    } on AiException catch (error) {
      if (mounted) setState(() => _modelError = error.message);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      final client = DeepSeekClient();
      final reply = await ModelResolver.withModelHealing(
        () => client.chat(
          system: '你是连通性测试助手，只回一句话。',
          user: '用不超过 5 个字回复：连接成功。',
          temperature: 0,
          timeout: const Duration(seconds: 30),
        ),
      );
      if (!mounted) return;
      setState(() {
        _testOk = true;
        _testResult = '通啦：${reply.trim()}';
      });
    } on AiException catch (error) {
      if (!mounted) return;
      setState(() {
        _testOk = false;
        _testResult = error.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _testOk = false;
        _testResult = '$error';
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _confirmClear() async {
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (BuildContext context) => CupertinoAlertDialog(
        title: const Text('清除 API key'),
        content: const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('清除后会自动停用 AI 功能，需要重新填写。', style: TextStyle(fontSize: 14)),
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
    await AiConfig.clearApiKey();
    await AiConfig.setEnabled(false);
    if (mounted) setState(() => _testResult = null);
  }

  static String _formatTime(DateTime? time) {
    if (time == null) return '未知';
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('AI 智能助手')),
      child: ValueListenableBuilder<int>(
        valueListenable: AiConfig.revision,
        builder: (BuildContext context, int _, Widget? __) {
          final hasKey = AiConfig.apiKey.isNotEmpty;
          return ListView(
            // ===== MOD ===== 底部留出系统导航栏的高度
            // 不留的话，最后一块内容会被底部导航栏压住一半（用户反馈的截图就是这样）。
            // `MediaQuery.padding.bottom` 正好是这个高度：全屏页面等于系统导航栏，
            // 标签页里则是标签栏 + 系统导航栏（首页会把它注入 MediaQuery）。
            padding: EdgeInsets.only(
              top: 12,
              bottom: 12 + MediaQuery.of(context).padding.bottom,
            ),
            children: [
              CupertinoListSection.insetGrouped(
                backgroundColor: pageBackground(context),
                header: const Text('开关'),
                footer: const Text(
                  '开启后，你选中的待办内容、或分享进来的那段文字，会发送给你配置的'
                  '模型服务商（默认是 DeepSeek 官方接口）。\n'
                  '其余数据仍然只存在本机；不需要 AI 时保持关闭即可。',
                ),
                children: [
                  CupertinoListTile(
                    title: const Text('启用 AI 功能'),
                    subtitle: Text(
                      AiConfig.isReady
                          ? '已就绪'
                          : (hasKey ? '填了 key，但还没开启' : '还没有填 API key'),
                    ),
                    trailing: CupertinoSwitch(
                      value: AiConfig.enabled,
                      onChanged: (bool value) => AiConfig.setEnabled(value),
                    ),
                  ),
                ],
              ),
              CupertinoListSection.insetGrouped(
                backgroundColor: pageBackground(context),
                header: const Text('API key'),
                footer: const Text(
                  '去 platform.deepseek.com 申请，复制那串 sk- 开头的密钥。\n'
                  '密钥存在系统密钥库，使用前需给模型厂商充值，'
                  '不会写进数据库，也不会跟着导出数据一起备份出去。',
                ),
                children: [
                  if (hasKey)
                    CupertinoListTile(
                      title: const Text('当前密钥'),
                      subtitle: Text(AiConfig.maskedKey),
                      trailing: CupertinoButton(
                        padding: EdgeInsets.zero,
                        child: const Text(
                          '清除',
                          style: TextStyle(color: CupertinoColors.systemRed),
                        ),
                        onPressed: _confirmClear,
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Column(
                      children: [
                        CupertinoTextField(
                          controller: _keyController,
                          placeholder: 'sk-…',
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
                            onPressed: _saveKey,
                            child: const Text('保存 key'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              CupertinoListSection.insetGrouped(
                backgroundColor: pageBackground(context),
                header: const Text('行为'),
                footer: const Text(
                  '关掉之后，AI 整理出的待办不会再自动带上子待办（有些通知本来就没必要拆步骤）。'
                  ' AI 拆成子待办功能不受影响',
                ),
                children: [
                  CupertinoListTile(
                    title: const Text('自动生成子待办'),
                    subtitle: Text(
                      AiConfig.autoSubtasks
                          ? '开启：AI 会顺手拆出步骤'
                          : '已关闭：只填标题 / 时间 / 地点这些',
                    ),
                    trailing: CupertinoSwitch(
                      value: AiConfig.autoSubtasks,
                      onChanged: (bool value) =>
                          AiConfig.setAutoSubtasks(value),
                    ),
                  ),
                ],
              ),
              CupertinoListSection.insetGrouped(
                backgroundColor: pageBackground(context),
                header: const Text('模型'),
                footer: Text(
                  AiConfig.isManualModel
                      ? '当前是手动指定。点自动选择可以交回给应用自动选择。'
                      : (ModelResolver.lastAutoPickReason.isEmpty
                          ? 'Elychron会自动查询可用模型，并根据价格与官方名称进行选择。'
                              '官方更名时会自动更改；Elychron无法控制模型价格变动。'
                          : '自动选择的理由：${ModelResolver.lastAutoPickReason}'),
                ),
                children: [
                  CupertinoListTile(
                    title: const Text('当前使用'),
                    subtitle: Text(
                      '${AiConfig.model}（${AiConfig.isManualModel ? '手动' : '自动'}）',
                    ),
                  ),
                  CupertinoListTile(
                    title: const Text('自动选择（推荐）'),
                    subtitle: const Text('模型更名不受影响，优先选择Flash版本'),
                    trailing: AiConfig.isManualModel
                        ? null
                        : const Icon(
                            CupertinoIcons.check_mark,
                            color: CupertinoColors.activeBlue,
                          ),
                    onTap: () => AiConfig.setAutoModel(),
                  ),
                  if (AiConfig.availableModels.isEmpty)
                    for (final model in AiConfig.models)
                      CupertinoListTile(
                        title: Text(AiConfig.modelLabel(model)),
                        subtitle: Text(AiConfig.modelNote(model)),
                        onTap: () => AiConfig.setModel(model),
                      )
                  else
                    for (final id in AiConfig.availableModels)
                      CupertinoListTile(
                        title: Text(id),
                        subtitle: Text(
                          id == AiConfig.resolvedModel &&
                                  !AiConfig.isManualModel
                              ? '自动选中'
                              : '',
                        ),
                        trailing: AiConfig.manualModel == id
                            ? const Icon(
                                CupertinoIcons.check_mark,
                                color: CupertinoColors.activeBlue,
                              )
                            : null,
                        onTap: () => AiConfig.setModel(id),
                      ),
                  CupertinoListTile(
                    title: const Text('刷新模型列表'),
                    subtitle: Text(
                      _modelError ??
                          (AiConfig.availableModels.isEmpty
                              ? '点击查询可用模型列表'
                              : '上次更新：${_formatTime(AiConfig.modelsFetchedAt)}'),
                    ),
                    trailing: _refreshing
                        ? const CupertinoActivityIndicator()
                        : const Icon(CupertinoIcons.arrow_clockwise, size: 18),
                    onTap: _refreshing ? null : _refreshModels,
                  ),
                ],
              ),
              CupertinoListSection.insetGrouped(
                backgroundColor: pageBackground(context),
                header: const Text('接口地址（进阶）'),
                footer: const Text(
                  '默认用 DeepSeek 官方接口。若使用中转服务或自建服务，'
                  '可以改成一个 OpenAI 兼容的地址。改错会导致调用失败。',
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: CupertinoTextField(
                      controller: _baseUrlController,
                      placeholder: AiConfig.defaultBaseUrl,
                      autocorrect: false,
                      keyboardType: TextInputType.url,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: CupertinoColors.tertiarySystemFill
                            .resolveFrom(context),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      onSubmitted: (String value) => AiConfig.setBaseUrl(value),
                    ),
                  ),
                  CupertinoListTile(
                    title: const Text('保存接口地址'),
                    trailing: const Icon(CupertinoIcons.arrow_right, size: 18),
                    onTap: () async {
                      await AiConfig.setBaseUrl(_baseUrlController.text);
                      _baseUrlController.text = AiConfig.baseUrl;
                    },
                  ),
                ],
              ),
              CupertinoListSection.insetGrouped(
                backgroundColor: pageBackground(context),
                header: const Text('连通性'),
                children: [
                  CupertinoListTile(
                    title: const Text('测试连接'),
                    subtitle: Text(
                      _testResult ?? '发一句最短的问话，验证 key 和网络',
                      style: TextStyle(
                        color: _testResult == null
                            ? null
                            : (_testOk
                                ? CupertinoColors.systemGreen
                                : CupertinoColors.systemRed),
                      ),
                    ),
                    trailing: _testing
                        ? const CupertinoActivityIndicator()
                        : const Icon(CupertinoIcons.bolt, size: 18),
                    onTap: _testing ? null : _test,
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
