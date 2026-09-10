import 'dart:async';

import 'package:celechron/mod/ai/deepseek.dart';
import 'package:flutter/cupertino.dart';

/// 设置 → AI 智能助手
///
/// 只做「配置 + 连通性验证」。真正的功能（解析分享内容、拆子待办）在
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
  String? _testResult;
  bool _testOk = false;

  @override
  void initState() {
    super.initState();
    AiConfig.load();
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
    await AiConfig.setApiKey(value);
    _keyController.clear();
    if (!mounted) return;
    setState(() {
      _testResult = null;
    });
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      final client = DeepSeekClient();
      final reply = await client.chat(
        system: '你是连通性测试助手，只回一句话。',
        user: '用不超过 15 个字回复：连接成功。',
        temperature: 0,
        timeout: const Duration(seconds: 30),
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
          child: Text('清除后 AI 功能会停用，需要重新填写。', style: TextStyle(fontSize: 14)),
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

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('AI 智能助手')),
      child: ValueListenableBuilder<int>(
        valueListenable: AiConfig.revision,
        builder: (BuildContext context, int _, Widget? __) {
          final hasKey = AiConfig.apiKey.isNotEmpty;
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 12),
            children: [
              CupertinoListSection.insetGrouped(
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
                header: const Text('API key'),
                footer: const Text(
                  '去 platform.deepseek.com 申请，复制那串 sk- 开头的密钥。\n'
                  '密钥存在系统密钥库（Android Keystore / iOS Keychain），'
                  '不会写进数据库，也不会跟着「导出数据」一起备份出去。',
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
                header: const Text('模型'),
                footer: const Text(
                  'deepseek-chat 快、便宜，适合解析文字和拆子待办；\n'
                  'deepseek-reasoner 会先推理再回答，更准但更慢也更贵。',
                ),
                children: [
                  for (final model in AiConfig.models)
                    CupertinoListTile(
                      title: Text(model),
                      trailing: AiConfig.model == model
                          ? const Icon(
                              CupertinoIcons.check_mark,
                              color: CupertinoColors.activeBlue,
                            )
                          : null,
                      onTap: () => AiConfig.setModel(model),
                    ),
                ],
              ),
              CupertinoListSection.insetGrouped(
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
