import 'package:celechron/design/dingtalk_sheet.dart';
import 'package:celechron/design/system_alarm_picker.dart';
import 'package:celechron/utils/alarm_player.dart';
import 'package:flutter/cupertino.dart';

/// 闹钟可靠性检查面板。
///
/// 闹钟不响的原因几乎都在系统权限上，而且各 ROM 各不相同：
/// - Android 13+ 需要通知权限
/// - Android 14+ 全屏通知要**单独授权**，否则只弹通知、不弹全屏闹钟页
/// - 国产 ROM（华为/小米/OPPO/vivo）常把后台闹钟掐掉，需要加入电池优化白名单
///   （华为还要单独允许自启动后台运行）
///
/// 这里把能查的查出来、能一键跳转的给出按钮，剩下的用文字说清楚。
/// 弹层用全 App 统一的钉钉风格（见 [showDingTalkPanel]），不再用 iOS 原生对话框。
Future<void> showAlarmReliabilityDialog(BuildContext context) async {
  final canFullScreen = await AlarmPlayer.canUseFullScreenIntent();
  final channelImportance = await AlarmPlayer.alarmChannelImportance();
  final ignoreBattery = await AlarmPlayer.isIgnoringBatteryOptimizations();
  if (!context.mounted) return;

  // 哪一项没做好，就把最该点的那个按钮设成主按钮（粉色），其余放次按钮
  String? primaryLabel;
  VoidCallback? onPrimary;
  if (channelImportance >= 0 && channelImportance < 4) {
    primaryLabel = '调高渠道';
    onPrimary = AlarmPlayer.openAlarmChannelSettings;
  } else if (!canFullScreen) {
    primaryLabel = '去授权全屏闹钟';
    onPrimary = AlarmPlayer.openFullScreenIntentSettings;
  } else if (!ignoreBattery) {
    primaryLabel = '电池设置';
    onPrimary = AlarmPlayer.openBatterySettings;
  }

  await showDingTalkPanel(
    context: context,
    title: '闹钟可靠性',
    subtitle: '闹钟不响基本都出在这几项上，逐条对照即可',
    children: [
      const SizedBox(height: 4),
      DingTalkInfoRow(
        label: '全屏闹钟（Android 14+）',
        value: canFullScreen ? '已授权' : '未授权',
        ok: canFullScreen,
      ),
      // 通知渠道一旦创建就不可修改，被系统降级后就不响也不弹全屏了
      DingTalkInfoRow(
        label: '闹钟渠道重要度',
        value: channelImportance >= 4
            ? '最高'
            : (channelImportance < 0 ? '未创建' : '只有 $channelImportance'),
        ok: channelImportance >= 4,
      ),
      DingTalkInfoRow(
        label: '电池优化白名单',
        value: ignoreBattery ? '已加入' : '未加入',
        ok: ignoreBattery,
      ),
      const SizedBox(height: 6),
      DingTalkPanelNote(
        canFullScreen
            ? '全屏闹钟已就绪：到点会像系统闹钟一样直接弹到锁屏上。'
            : '没有全屏通知权限时，闹钟到点只会弹一条通知，不会自动弹全屏。点上面的按钮去开启。',
      ),
      const DingTalkPanelNote(
        '华为/小米等机型还会智能压低通知重要度：重要度低于最高时，'
        '闹钟到点只会留一条静默通知。请到通知设置把本应用的通知重要度调到最高，'
        '并允许横幅与锁屏显示。',
      ),
      DingTalkPanelNote(
        ignoreBattery
            ? '已加入电池优化白名单，后台闹钟不容易被系统掐掉。'
            : '国产 ROM 建议把本应用加入电池优化白名单，并允许自启动 / 后台运行，否则息屏后闹钟可能不响。',
      ),
      // 这条不是废话：同一条白名单还管着"App 不在前台也要干活"的一切后台行为。
      // 2026-09-15 定位桌面小组件"点了没反应"时，查出来的根因就是它
      // （后台任务根本不被调度，进 App 就正常、在桌面点就没反应）。
      // 面板以前只讲闹钟/通知，用户会以为白名单只是"闹钟的事"。
      const DingTalkPanelNote(
        '这条白名单管的不只是闹钟：后台刷新、后台同步这类"App 不在前台也要干活"的事情同样受它限制。'
        '系统里它可能叫电池优化后台运行自启动或省电策略，看到就一起允许。',
      ),
      const DingTalkPanelNote(
        '如果某件事必须叫醒你，可以手动把它交给系统时钟：优先级和起床闹钟一样。'
        '代价是系统闹钟一次性、且不会随待办删除而撤销，所以这里只做手动入口。',
      ),
    ],
    primaryLabel: primaryLabel,
    onPrimary: onPrimary == null
        ? null
        : () {
            Navigator.of(context).pop();
            onPrimary!();
          },
    secondaryActions: [
      DingTalkPanelAction(
        label: '系统闹钟',
        onTap: () {
          Navigator.of(context).pop();
          showSystemAlarmPicker(context);
        },
      ),
      DingTalkPanelAction(
        label: '通知设置',
        onTap: () {
          Navigator.of(context).pop();
          AlarmPlayer.openAppNotificationSettings();
        },
      ),
    ],
  );
}
