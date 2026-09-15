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

class LoginForm extends StatefulWidget {
  const LoginForm({super.key});

  @override
  State<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<LoginForm> {
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final _optionController = Get.find<OptionController>(tag: 'optionController');
  final buttonPressed = false.obs;

  /// 密码是否明文显示。
  ///
  /// 加这个开关是为了绕开一个真机问题：部分国产 ROM（反馈来自小米 17 PM / HyperOS）
  /// 在**密码类输入框**上弹不出输入法，而粘贴能贴进去；切成明文后走的是普通文本框，
  /// 一般就能正常调出键盘了。见密码框那里的长注释。
  bool _showPassword = false;

  @override
  void initState() {
    super.initState();
    _prefillRememberedAccount();
  }

  @override
  void dispose() {
    usernameController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  /// ===== MOD: 预填上次登录的账号密码 =====
  ///
  /// 用户要求：**主动退出登录之后，登录页仍要预填好账号密码**。
  /// 退出登录会把 `username`/`password` 两个键从密钥库删掉（这是上游行为，
  /// 我们不动它），所以我们另存了一份 `mod_last_*`，退出不删 → 这里读回来填上。
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
                          // ===== MOD: 密码框在部分国产 ROM 上弹不出键盘 =====
                          //
                          // 用户反馈（小米 17 PM / HyperOS）：「输学号正常，但输密码键盘
                          // 会跳不出来」，而**粘贴是能贴进去的** —— 说明输入框本身能聚焦、
                          // 也能收文本，卡住的是"向系统要输入法"这一步。这类 ROM 对
                          // **密码类输入框**会挂自己的"安全输入法"，那个键盘起不来时
                          // 系统就什么都不弹。
                          //
                          // 所以这里：① 输入类型显式声明成 visiblePassword（而不是
                          // 让引擎按 obscureText 推成 textPassword），尽量走普通文本框那条路；
                          // ② 关掉联想/自动更正；③ 给一个「显示密码」开关 ——
                          // 万一还是弹不出来，切成明文一般就能正常输入（也能让用户
                          // 自己确认密码有没有打错）。
                          keyboardType: TextInputType.visiblePassword,
                          autocorrect: false,
                          enableSuggestions: false,
                          obscureText: !_showPassword,
                          suffix: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () =>
                                setState(() => _showPassword = !_showPassword),
                            child: Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: Icon(
                                _showPassword
                                    ? CupertinoIcons.eye_slash
                                    : CupertinoIcons.eye,
                                size: 20,
                                color: CupertinoDynamicColor.resolve(
                                    CupertinoColors.secondaryLabel, context),
                              ),
                            ),
                          ),
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
