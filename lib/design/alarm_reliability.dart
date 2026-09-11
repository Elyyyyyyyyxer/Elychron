import 'package:celechron/utils/alarm_player.dart';
import 'package:flutter/cupertino.dart';

/// 「闹钟可靠性」检查面板。
///
/// 闹钟不响的原因几乎都在系统权限上，而且各 ROM 各不相同：
/// - Android 13+ 需要通知权限
/// - Android 14+ 全屏通知要**单独授权**，否则只弹通知、不弹全屏闹钟页
/// - 国产 ROM（华为/小米/OPPO/vivo）常把后台闹钟掐掉，需要加入电池优化白名单
///   （华为还要单独允许「自启动」「后台运行」）
///
/// 这里把能查的查出来、能一键跳转的给出按钮，剩下的用文字说清楚。
Future<void> showAlarmReliabilityDialog(BuildContext context) async {
  final canFullScreen = await AlarmPlayer.canUseFullScreenIntent();
  final channelImportance = await AlarmPlayer.alarmChannelImportance();
  final ignoreBattery = await AlarmPlayer.isIgnoringBatteryOptimizations();
  if (!context.mounted) return;

  await showCupertinoDialog<void>(
    context: context,
    builder: (BuildContext context) => CupertinoAlertDialog(
      title: const Text('闹钟可靠性'),
      content: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _row(
              context,
              '全屏闹钟（Android 14+）',
              canFullScreen ? '已授权' : '未授权',
              canFullScreen,
            ),
            // 通知渠道一旦创建就不可修改，被系统降级后就不响也不弹全屏了
            _row(
              context,
              '闹钟渠道重要度',
              channelImportance >= 4
                  ? '最高'
                  : (channelImportance < 0 ? '未创建' : '只有 '),
              channelImportance >= 4,
            ),
            _row(
              context,
              '电池优化白名单',
              ignoreBattery ? '已加入' : '未加入',
              ignoreBattery,
            ),
            const SizedBox(height: 10),
            Text(
              canFullScreen
                  ? '全屏闹钟已就绪：到点会像系统闹钟一样直接弹到锁屏上。'
                  : '没有「全屏通知」权限时，闹钟到点只会弹一条通知，不会自动弹全屏。'
                      '点下面的按钮去开启。',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 8),
            const SizedBox(height: 8),
            const Text(
              '华为/小米等机型还会「智能」压低通知重要度：如果上面显示的重要度低于「最高」，'
              '闹钟到点就会只留一条静默通知。请到「通知设置」里把本应用的通知重要度调到最高，'
              '并允许横幅与锁屏显示。',
              style: TextStyle(fontSize: 12.5),
            ),
            const SizedBox(height: 8),
            Text(
              ignoreBattery
                  ? '已加入电池优化白名单，后台闹钟不容易被系统掐掉。'
                  : '国产 ROM 建议把本应用加入电池优化白名单，并允许「自启动 / 后台运行」，'
                      '否则息屏后闹钟可能不响。',
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ),
      ),
      actions: [
        CupertinoDialogAction(
          child: const Text('关闭'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        CupertinoDialogAction(
          child: const Text('通知设置'),
          onPressed: () {
            Navigator.of(context).pop();
            AlarmPlayer.openAppNotificationSettings();
          },
        ),
        if (channelImportance < 5 && channelImportance >= 0)
          CupertinoDialogAction(
            isDefaultAction: true,
            child: const Text('调高渠道'),
            onPressed: () {
              Navigator.of(context).pop();
              AlarmPlayer.openAlarmChannelSettings();
            },
          )
        else if (!canFullScreen)
          CupertinoDialogAction(
            isDefaultAction: true,
            child: const Text('去授权'),
            onPressed: () {
              Navigator.of(context).pop();
              AlarmPlayer.openFullScreenIntentSettings();
            },
          )
        else if (!ignoreBattery)
          CupertinoDialogAction(
            isDefaultAction: true,
            child: const Text('电池设置'),
            onPressed: () {
              Navigator.of(context).pop();
              AlarmPlayer.openBatterySettings();
            },
          ),
      ],
    ),
  );
}

Widget _row(
  BuildContext context,
  String label,
  String value,
  bool ok,
) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        Icon(
          ok
              ? CupertinoIcons.check_mark_circled_solid
              : CupertinoIcons.exclamationmark_circle,
          size: 16,
          color:
              ok ? CupertinoColors.systemGreen : CupertinoColors.systemOrange,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(label, style: const TextStyle(fontSize: 13.5)),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            color:
                ok ? CupertinoColors.systemGreen : CupertinoColors.systemOrange,
          ),
        ),
      ],
    ),
  );
}
