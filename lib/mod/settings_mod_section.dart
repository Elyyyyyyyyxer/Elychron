import 'package:celechron/design/alarm_reliability.dart';
import 'package:celechron/design/alarm_theme_picker.dart';
import 'package:celechron/design/dingtalk_sheet.dart';
import 'package:celechron/database/database_helper.dart';
import 'package:celechron/mod/database_mod.dart';
import 'package:celechron/mod/do_not_disturb.dart';
import 'package:celechron/mod/ai/ai_settings_page.dart';
import 'package:celechron/mod/ai/deepseek.dart';
import 'package:celechron/mod/lan_sync_page.dart';
import 'package:celechron/mod/settings_data_actions.dart';
import 'package:celechron/page/focus/focus_stats_page.dart';
import 'package:celechron/page/option/option_controller.dart';
import 'package:celechron/page/option/option_view.dart' show BackChervonRow;
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:celechron/tutorial/tutorial_entry.dart';
import 'package:celechron/tutorial/tutorial_registry.dart';
import 'package:celechron/tutorial/tutorial_store.dart';

/// ============ 设置页里属于魔改的两个区块 ============
///
/// 上游的 `lib/page/option/option_view.dart` 一直在更新（1.3 就加了 36 行），
/// 所以把这些声明式的设置行放在这里，那个文件里只留两处挂载（见 `// ===== MOD =====`）。

/// 教程中心的入口区块。
///
/// 教程内容在 `lib/tutorial/modules/` 下，**加一篇教程不需要改这个文件** ——
/// 这里只负责"入口"，列表由 `TutorialCenterPage` 按注册表自动生成。
Widget modTutorialSection(
  BuildContext context, {
  required TextStyle? headerStyle,
  required EdgeInsetsGeometry margin,
}) =>
    SliverToBoxAdapter(
        child: CupertinoListSection.insetGrouped(
            additionalDividerMargin: 2,
            margin: margin,
            header: Container(
                padding: const EdgeInsets.only(left: 16),
                child: Text('教程', style: headerStyle)),
            children: <CupertinoListTile>[
          CupertinoListTile(
            title: const Text('使用教程'),
            // ⚠️ 副标题是"还有几篇没看"，必须跟着教程状态刷新 ——
            // 否则看完一篇回到设置页还显示旧数字（真机上就是这么发现的）。
            subtitle: ValueListenableBuilder<int>(
              valueListenable: TutorialStore.instance.revision,
              builder: (context, _, __) => Text(_tutorialSubtitle()),
            ),
            trailing: const BackChervonRow(),
            onTap: () => openTutorialCenter(context),
          ),
        ]));

/// 副标题：让用户一眼看到"还有几篇没看"
String _tutorialSubtitle() {
  try {
    final pending = TutorialStore.instance.pending().length;
    final total = TutorialRegistry.all.length;
    if (total == 0) return '教程还在写';
    if (pending == 0) return '共 $total 篇，都看过了';
    return '共 $total 篇，还有 $pending 篇没看';
  } catch (_) {
    return '按功能一篇篇看，随时可以重看';
  }
}

/// 是否开放「局域网同步」（多端协同）入口。
///
/// **公开发布这版先关掉**：功能尚未完工（用户决定）。代码、网页面板与测试都保留，
/// 把这里改回 `true` 就能恢复入口，不需要改别的地方。
const bool kLanSyncEnabled = false;

/// 待办提醒方式 / 默认提前量 / 闹钟配色
List<Widget> modReminderTiles(
  BuildContext context,
  OptionController optionController,
) =>
    [
      CupertinoListTile(
        title: const Text('待办提醒方式'),
        subtitle: const Text('通知：横幅弹出+响铃；闹钟：全屏响铃，可延迟或划掉'),
        trailing: Obx(() => CupertinoSlidingSegmentedControl<int>(
              children: const {
                0: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: Text('通知')),
                1: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: Text('闹钟')),
              },
              groupValue: optionController.reminderMode.value,
              onValueChanged: (value) {
                if (value != null) {
                  optionController.setReminderMode(value);
                }
              },
            )),
      ),
      // ===== P1：默认提醒提前量 =====
      // 活动锚「开始」、截止锚「截止」，各自再提前这么多；提醒型就是那一刻。
      const _ReminderLeadTile(),
      // ===== P3：专注参数 + 休息提醒 =====
      const _FocusParamTile(),
      const _FocusRestNotifyTile(),
      const _FocusDndTile(),
      const _FocusCourseTile(),
      // ===== P4：专注记录 / 统计 =====
      CupertinoListTile(
        title: const Text('专注记录'),
        subtitle: const Text('今天 / 本周 / 本月时长、最近七天、按任务分布'),
        trailing: const BackChervonRow(),
        onTap: () async {
          await Navigator.of(context, rootNavigator: true).push(
            CupertinoPageRoute<void>(
              builder: (BuildContext context) => const FocusStatsPage(),
            ),
          );
        },
      ),
      CupertinoListTile(
        title: const Text('闹钟可靠性'),
        subtitle: const Text('全屏闹钟授权、锁屏弹出、电池白名单'),
        trailing: const BackChervonRow(),
        onTap: () => showAlarmReliabilityDialog(context),
      ),
      CupertinoListTile(
        title: const Text('闹钟配色'),
        subtitle: const Text('闹钟页面四种配色'),
        trailing: const BackChervonRow(),
        onTap: () => showAlarmThemePicker(
          context,
          onChanged: () {},
        ),
      ),
    ];

/// 「默认提醒提前量」这一行：点开选一个值，存进 optionsBox。
class _ReminderLeadTile extends StatefulWidget {
  const _ReminderLeadTile();

  @override
  State<_ReminderLeadTile> createState() => _ReminderLeadTileState();
}

class _ReminderLeadTileState extends State<_ReminderLeadTile> {
  /// 可选的提前量（分钟）。0 = 准时，1440 = 提前一天。
  static const List<int> _options = [0, 5, 10, 15, 30, 60, 120, 1440];

  DatabaseHelper? get _db {
    if (!Get.isRegistered<DatabaseHelper>(tag: 'db')) return null;
    return Get.find<DatabaseHelper>(tag: 'db');
  }

  int get _minutes => _db?.getReminderLeadMinutes() ?? 30;

  static String leadLabel(int minutes) {
    if (minutes <= 0) return '准时';
    if (minutes % 1440 == 0) return '提前 ${minutes ~/ 1440} 天';
    if (minutes % 60 == 0) return '提前 ${minutes ~/ 60} 小时';
    return '提前 $minutes 分钟';
  }

  Future<void> _pick() async {
    // 钉钉风格弹层（原先是 iOS 原生 ActionSheet，风格与 App 其它弹层不一致）
    final picked = await showDingTalkSheet<int>(
      context: context,
      title: '默认提前多久提醒',
      subtitle: '活动按开始前算，截止按截止前算，提醒型不受影响。',
      current: _minutes,
      options: [
        for (final minutes in _options)
          DingTalkSheetOption(label: leadLabel(minutes), value: minutes),
      ],
    );
    if (picked == null) return;
    _db?.setReminderLeadMinutes(picked);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoListTile(
      title: const Text('默认提醒提前量'),
      subtitle: Text('新建活动/截止时默认 ${leadLabel(_minutes)} 提醒'),
      trailing: BackChervonRow(child: Text(leadLabel(_minutes))),
      onTap: _pick,
    );
  }
}

/// 数据（导出 / 导入）
Widget modDataSection(
  BuildContext context, {
  required TextStyle? headerStyle,
  required EdgeInsetsGeometry margin,
}) =>
    SliverToBoxAdapter(
        child: CupertinoListSection.insetGrouped(
            additionalDividerMargin: 2,
            margin: margin,
            header: Container(
                padding: const EdgeInsets.only(left: 16),
                child: Text('数据', style: headerStyle)),
            children: <CupertinoListTile>[
          // 「局域网同步」（多端协同）尚未完工，公开发布这版先不开放入口。
          // 代码与网页面板都还在 `lib/mod/lan_*.dart` 里，改回 true 即可恢复。
          if (kLanSyncEnabled) ...[
            CupertinoListTile(
              title: const Text('局域网同步'),
              subtitle: const Text('同局域网下可从电脑浏览器访问'),
              trailing: const BackChervonRow(),
              onTap: () async {
                await Navigator.of(context, rootNavigator: true).push(
                  CupertinoPageRoute<void>(
                    builder: (BuildContext context) => const LanSyncPage(),
                  ),
                );
              },
            ),
          ],
          CupertinoListTile(
            title: const Text('导出数据'),
            subtitle: const Text('导出为 JSON 文件'),
            trailing: const BackChervonRow(),
            onTap: () => modExportData(context),
          ),
          CupertinoListTile(
            title: const Text('导入数据'),
            subtitle: const Text('从 JSON 文件合并'),
            trailing: const BackChervonRow(),
            onTap: () => modImportData(context),
          ),
          // 一键把「机型 / 系统 / 版本 + 脱敏日志 + 反馈模板」复制到剪贴板。
          // 目的是让反馈发生在 QQ 群、论坛帖这类没门槛的地方时，也能说清现场。
          CupertinoListTile(
            title: const Text('复制反馈信息'),
            subtitle: const Text('机型、系统、版本、脱敏日志'),
            trailing: const BackChervonRow(),
            onTap: () => modCopyFeedback(context),
          ),
          // 导入 iCal（.ics）：把别的日历/课程表导出的日程变成待办。
          // 与「导出为 iCal 文件」成对，但那条在上游的设置区块里，
          // 这里放在数据区块，避免改上游文件。
          CupertinoListTile(
            title: const Text('导入 iCal 文件'),
            subtitle: const Text('把 .ics 里的日程导入成待办（重复导入不会重复）'),
            trailing: const BackChervonRow(),
            onTap: () => modImportIcal(context),
          ),
        ]));

/// ===== P3：专注参数（工作 / 休息分钟数）=====
///
/// 默认 60 / 15（用户拍板）。改动只影响**下一次**开始专注，
/// 正在跑的那次会保留它自己的参数。
class _FocusParamTile extends StatefulWidget {
  const _FocusParamTile();

  @override
  State<_FocusParamTile> createState() => _FocusParamTileState();
}

class _FocusParamTileState extends State<_FocusParamTile> {
  static const List<int> _workOptions = [15, 25, 30, 45, 60, 90, 120];
  static const List<int> _restOptions = [0, 5, 10, 15, 20, 30];

  DatabaseHelper? get _db {
    if (!Get.isRegistered<DatabaseHelper>(tag: 'db')) return null;
    return Get.find<DatabaseHelper>(tag: 'db');
  }

  int get _work => _db?.getFocusWorkMinutes() ?? 60;
  int get _rest => _db?.getFocusRestMinutes() ?? 15;

  static String label(int minutes) {
    if (minutes <= 0) return '不休息';
    if (minutes % 60 == 0) return '${minutes ~/ 60} 小时';
    return '$minutes 分钟';
  }

  Future<void> _pick({required bool isWork}) async {
    final options = isWork ? _workOptions : _restOptions;
    // 钉钉风格弹层（与「默认提醒提前量」统一）
    final picked = await showDingTalkSheet<int>(
      context: context,
      title: isWork ? '一段专注多久' : '每轮休息多久',
      subtitle: isWork
          ? '默认 60 分钟。到点会自动进入休息。'
          : '默认 15 分钟。想连着干可以把休息设成不休息。',
      current: isWork ? _work : _rest,
      options: [
        for (final minutes in options)
          DingTalkSheetOption(label: label(minutes), value: minutes),
      ],
    );
    if (picked == null) return;
    if (isWork) {
      _db?.setFocusWorkMinutes(picked);
    } else {
      _db?.setFocusRestMinutes(picked);
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoListTile(
      title: const Text('专注时长'),
      subtitle: const Text('轮流进入工作/休息模式；仅对下一次专注生效'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: const Size(48, 36),
            onPressed: () => _pick(isWork: true),
            child: Text(label(_work)),
          ),
          const Text(' / ', style: TextStyle(fontSize: 14)),
          CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: const Size(48, 36),
            onPressed: () => _pick(isWork: false),
            child: Text(label(_rest)),
          ),
        ],
      ),
      onTap: () => _pick(isWork: true),
    );
  }
}

/// ===== 专注自动计入课程（默认开）=====
///
/// 用户 2026-09-14 拍板的三条之一：自由专注若**开始时间**落在某节课里，
/// 就算那门课的专注；并且**做成开关**。
/// 口径与实现见 `mod/course_mount_store.dart` 的 `courseIdForFocusStart`。
class _FocusCourseTile extends StatefulWidget {
  const _FocusCourseTile();

  @override
  State<_FocusCourseTile> createState() => _FocusCourseTileState();
}

class _FocusCourseTileState extends State<_FocusCourseTile> {
  DatabaseHelper? get _db {
    if (!Get.isRegistered<DatabaseHelper>(tag: 'db')) return null;
    return Get.find<DatabaseHelper>(tag: 'db');
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _db?.getFocusAttributeToCourse() ?? true;
    return CupertinoListTile(
      title: const Text('专注自动计入课程'),
      subtitle: const Text('上课时段里开始的专注，按开始时间记到那门课上'),
      trailing: CupertinoSwitch(
        value: enabled,
        onChanged: (value) {
          _db?.setFocusAttributeToCourse(value);
          setState(() {});
        },
      ),
    );
  }
}

/// ===== 专注时自动免打扰（默认开）=====
///
/// 免打扰要「勿扰访问权限」，那是特殊权限、装机不自动授予。
/// 所以这里不仅是个开关：没授权时点它会直接跳到系统授权页，并在副标题里说明状态。
class _FocusDndTile extends StatefulWidget {
  const _FocusDndTile();

  @override
  State<_FocusDndTile> createState() => _FocusDndTileState();
}

class _FocusDndTileState extends State<_FocusDndTile> {
  DatabaseHelper? get _db {
    if (!Get.isRegistered<DatabaseHelper>(tag: 'db')) return null;
    return Get.find<DatabaseHelper>(tag: 'db');
  }

  bool? _granted;

  @override
  void initState() {
    super.initState();
    DoNotDisturb.isGranted().then((value) {
      if (mounted) setState(() => _granted = value);
    });
  }

  String get _subtitle {
    if (_granted == null) return '专注期间自动把手机静音，结束时还原';
    if (_granted == false) return '需要勿扰访问权限，点这里去系统设置里授予';
    return '专注期间自动切到完全静音，结束时自动恢复';
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _db?.getFocusDndEnabled() ?? true;
    return CupertinoListTile(
      title: const Text('专注时自动免打扰'),
      subtitle: Text(_subtitle),
      trailing: CupertinoSwitch(
        value: enabled,
        onChanged: (value) async {
          _db?.setFocusDndEnabled(value);
          setState(() {});
          // 打开开关但没授权 → 直接带用户去授权，别让他以为已经生效
          if (value && _granted == false) {
            await DoNotDisturb.openSettings();
            final granted = await DoNotDisturb.isGranted();
            if (mounted) setState(() => _granted = granted);
          }
        },
      ),
      // 没授权时点整行也去授权，免得用户找不到入口
      onTap: _granted == false
          ? () async {
              await DoNotDisturb.openSettings();
              final granted = await DoNotDisturb.isGranted();
              if (mounted) setState(() => _granted = granted);
            }
          : null,
    );
  }
}

/// ===== P3：休息开始时提醒一句（默认开）=====
class _FocusRestNotifyTile extends StatefulWidget {
  const _FocusRestNotifyTile();

  @override
  State<_FocusRestNotifyTile> createState() => _FocusRestNotifyTileState();
}

class _FocusRestNotifyTileState extends State<_FocusRestNotifyTile> {
  DatabaseHelper? get _db {
    if (!Get.isRegistered<DatabaseHelper>(tag: 'db')) return null;
    return Get.find<DatabaseHelper>(tag: 'db');
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoListTile(
      title: const Text('休息时提醒我'),
      subtitle: const Text('起来休息一下啦'),
      trailing: CupertinoSwitch(
        value: _db?.getFocusRestNotify() ?? true,
        onChanged: (value) {
          _db?.setFocusRestNotify(value);
          setState(() {});
        },
      ),
    );
  }
}

/// AI 智能助手（配置 API key / 模型 / 测试连接）
Widget modAiSection(
  BuildContext context, {
  required TextStyle? headerStyle,
  required EdgeInsetsGeometry margin,
}) =>
    ValueListenableBuilder<int>(
      valueListenable: AiConfig.revision,
      builder: (BuildContext context, int _, Widget? __) => SliverToBoxAdapter(
        child: CupertinoListSection.insetGrouped(
          additionalDividerMargin: 2,
          margin: margin,
          header: Container(
              padding: const EdgeInsets.only(left: 16),
              child: Text('智能', style: headerStyle)),
          children: <CupertinoListTile>[
            CupertinoListTile(
              title: const Text('AI 智能助手'),
              subtitle: Text(
                AiConfig.isReady
                    ? '已启用 · ${AiConfig.model}'
                    : '默认关闭；填自己的 DeepSeek key 后可用',
              ),
              trailing: const BackChervonRow(),
              onTap: () async {
                await AiConfig.load();
                if (!context.mounted) return;
                await Navigator.of(context, rootNavigator: true).push(
                  CupertinoPageRoute<void>(
                    builder: (BuildContext context) => const AiSettingsPage(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
