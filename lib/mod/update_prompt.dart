import 'package:celechron/worker/fuse.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher_string.dart';

/// ===== 启动后的更新检查 + 提示（手机端 / 桌面端共用）=====
///
/// 原来这套逻辑写在手机端首页的 initState 里（`HomePage.initFuse`）。
/// v1.5.0 加了桌面端主界面之后，两端都要做同一件事，所以抽到这里：
/// 壳不一样，更新检查的口径必须一样（大版本强制、小版本只提醒一次）。
///
/// 注意延迟 1 秒再查：启动瞬间还在读库、连网，抢在一起会让首屏发顿。
Future<void> checkUpdateOnStart(BuildContext context) async {
  await Future<void>.delayed(const Duration(seconds: 1));
  final Fuse fuse;
  try {
    fuse = Get.find<Rx<Fuse>>(tag: 'fuse').value;
  } catch (_) {
    return; // 还没注册（测试等场景），安静跳过
  }
  final update = await fuse.checkUpdate().whenComplete(() {
    try {
      Get.find<Rx<Fuse>>(tag: 'fuse').refresh();
    } catch (_) {}
  });
  if (update == null) return;
  if (!context.mounted) return;

  // 大版本 → 强制更新：没有忽略，只能去下载（或退出应用）。
  // 小版本 → 普通提醒，可忽略；同一个版本只提醒一次（由 Fuse 记录）。
  await showCupertinoDialog<void>(
      context: context,
      barrierDismissible: !update.forced,
      builder: (BuildContext context) {
        return CupertinoAlertDialog(
          title: Text(update.forced ? '需要更新后才能继续使用' : '更新可用'),
          content: Text(
            update.forced
                ? '当前版本 ${Fuse.appVersionName} 已经太旧，'
                    '请更新到 ${update.tag}。\n\n${update.summary}'
                : update.message,
          ),
          actions: <Widget>[
            if (!update.forced)
              CupertinoDialogAction(
                child: const Text('忽略'),
                onPressed: () => Navigator.of(context).pop(),
              ),
            if (update.forced)
              CupertinoDialogAction(
                child: const Text('退出'),
                onPressed: () => SystemNavigator.pop(),
              ),
            CupertinoDialogAction(
              isDefaultAction: true,
              child: const Text('去下载'),
              onPressed: () async {
                // 打开**实际回答的那个源**的 Release 页：
                // 国内用户多半连不上 GitHub；如果这次是 Gitee 查到的更新，
                // 就必须跳 Gitee， 否则他看得到更新却打不开下载页。
                await launchUrlString(
                  update.downloadUrl,
                  mode: LaunchMode.externalApplication,
                );
                // 强制更新时对话框留着，装完新版本自然会消失
                if (!update.forced && context.mounted) {
                  Navigator.of(context).pop();
                }
              },
            ),
          ],
        );
      });
}
