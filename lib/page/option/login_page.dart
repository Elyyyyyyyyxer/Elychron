import 'package:celechron/utils/platform_features.dart';
import 'package:celechron/mod/login_criteria.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:celechron/model/scholar.dart';

import '../../worker/ecard_widget_messenger.dart';
import 'option_controller.dart';
import 'package:celechron/mod/friendly_error.dart';
import 'package:celechron/database/database_helper.dart';
import 'package:celechron/mod/database_mod.dart';

class LoginForm extends StatelessWidget {
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final _optionController = Get.find<OptionController>(tag: 'optionController');
  final buttonPressed = false.obs;

  /// ===== MOD: 预填上次登录的账号密码 =====
  ///
  /// 用户要求：**主动退出登录之后，登录页仍要预填好账号密码**。
  /// 退出登录会把 `username`/`password` 两个键从密钥库删掉（这是上游行为，
  /// 我们不动它），所以我们另存了一份 `mod_last_*`，退出不删 → 这里读回来填上。
  LoginForm({super.key}) {
    _prefillRememberedAccount();
  }

  Future<void> _prefillRememberedAccount() async {
    try {
      if (!Get.isRegistered<DatabaseHelper>(tag: 'db')) return;
      final saved =
          await Get.find<DatabaseHelper>(tag: 'db').rememberedAccount();
      if (saved.username.isNotEmpty) {
        usernameController.text = saved.username;
      }
      if (saved.password.isNotEmpty) {
        passwordController.text = saved.password;
      }
    } catch (_) {
      // 读不到就算了，用户手打也不影响
    }
  }

  @override
  Widget build(BuildContext context) {
    var brightness = CupertinoTheme.of(context).brightness ??
        MediaQuery.of(context).platformBrightness;

    return Container(
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: CupertinoDynamicColor.resolve(
                CupertinoColors.systemGroupedBackground, context)),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 6,
          right: 6,
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.only(
                    left: 16, right: 16, bottom: 8, top: 16),
                child: Text(
                  '统一身份认证登录',
                  style: CupertinoTheme.of(context).textTheme.navTitleTextStyle,
                ),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                child: Column(
                  children: [
                    SizedBox(
                        height: 48,
                        child: CupertinoTextField(
                          controller: usernameController,
                          keyboardType: TextInputType.number,
                          prefix: Container(
                              padding: const EdgeInsets.only(left: 12),
                              child: Text('学号',
                                  style: CupertinoTheme.of(context)
                                      .textTheme
                                      .textStyle)),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: brightness == Brightness.light
                                ? CupertinoColors.systemBackground
                                : CupertinoColors.secondarySystemBackground,
                            borderRadius: BorderRadius.circular(10),
                          ),
                        )),
                    const SizedBox(height: 16),
                    SizedBox(
                        height: 48,
                        child: CupertinoTextField(
                          controller: passwordController,
                          obscureText: true,
                          prefix: Container(
                            padding: const EdgeInsets.only(left: 12),
                            child: Text('密码',
                                style: CupertinoTheme.of(context)
                                    .textTheme
                                    .textStyle),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: brightness == Brightness.light
                                ? CupertinoColors.systemBackground
                                : CupertinoColors.secondarySystemBackground,
                            borderRadius: BorderRadius.circular(10),
                          ),
                        )),
                    const SizedBox(height: 16),
                    Obx(() => CupertinoButton(
                        onPressed: () async {
                          buttonPressed.value = true;
                          var scholar = Get.find<Rx<Scholar>>(tag: 'scholar');
                          scholar.update((val) {
                            val!.username = usernameController.value.text;
                            val.password = passwordController.value.text;
                            val.login().then((value) async {
                              // ===== MOD: 判据只看统一身份认证（见 LoginCriteria）=====
                              // 以前要求所有子站都登录成功，教务网一崩就「登录失败」并
                              // 卡在登录页；现在身份通过就进 App，子站失败只做提示。
                              if (LoginCriteria.succeeded(value)) {
                                await val.refresh(
                                    onPartialUpdate: scholar.refresh);
                                scholar.refresh();
                                buttonPressed.value = false;
                                _optionController.pushOnGradeChange =
                                    PlatformFeatures.hasBackgroundRefresh;
                                if (context.mounted) {
                                  Navigator.of(context).pop();
                                }
                                final hint =
                                    LoginCriteria.degradedHint(value);
                                if (hint.isNotEmpty && context.mounted) {
                                  showCupertinoDialog(
                                      context: context,
                                      builder: (context) => CupertinoAlertDialog(
                                            title: const Text('部分模块暂不可用'),
                                            content: Text(hint),
                                            actions: [
                                              CupertinoDialogAction(
                                                child: const Text('知道了'),
                                                onPressed: () => Navigator.of(
                                                        context)
                                                    .pop(),
                                              ),
                                            ],
                                          ));
                                }
                              } else {
                                buttonPressed.value = false;
                                if (!context.mounted) return;
                                // ===== MOD: 报错只说人话 =====
                                // 以前把异常原文整段贴出来（含 URL / 状态码 / 响应片段），
                                // 一屏都放不下，用户完全看不懂。现在压成一句，
                                // 细节去「设置 → 诊断与测试」里看。
                                final raw = value.firstWhere(
                                    (e) => e != null && e.trim().isNotEmpty,
                                    orElse: () => null);
                                showCupertinoDialog(
                                    context: context,
                                    builder: (context) {
                                      return CupertinoAlertDialog(
                                        title: const Text('登录失败'),
                                        content: Padding(
                                          padding:
                                              const EdgeInsets.only(top: 8),
                                          child: Text(
                                            FriendlyError.short(raw,
                                                fallback: '登录没成功，请稍后重试'),
                                            style: const TextStyle(
                                                fontSize: 15),
                                          ),
                                        ),
                                        actions: [
                                          CupertinoDialogAction(
                                            child: const Text('知道了'),
                                            onPressed: () async {
                                              Navigator.of(context).pop();
                                            },
                                          )
                                        ],
                                      );
                                    });
                              }
                              ECardWidgetMessenger.update();
                            });
                          });
                        },
                        color: buttonPressed.value
                            ? CupertinoColors.inactiveGray
                            : CupertinoColors.activeBlue,
                        child: SizedBox(
                          height: 24,
                          width: 60,
                          child: Center(
                              child: buttonPressed.value
                                  ? const CupertinoActivityIndicator()
                                  : const Text('登录',
                                      style: TextStyle(
                                          color: CupertinoColors.white))),
                        ))),
                  ],
                ),
              ),
            ],
          ),
        ));
  }
}
