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

/// ============ 设置页里属于魔改的两个区块 ============
///
/// 上游的 `lib/page/option/option_view.dart` 一直在更新（1.3 就加了 36 行），
/// 所以把这些声明式的设置行放在这里，那个文件里只留两处挂载（见 `// ===== MOD =====`）。

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
        subtitle: const Text('全屏闹钟授权、锁屏弹出、电池白名单，一项项查'),
        trailing: const BackChervonRow(),
        onTap: () => showAlarmReliabilityDialog(context),
      ),
      CupertinoListTile(
        title: const Text('闹钟配色'),
        subtitle: const Text('浅色 + 毛玻璃，仅影响闹钟页'),
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
      subtitle: '活动按「开始前」算，截止按「截止前」算；提醒型不受影响。',
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
              subtitle: const Text('同一 Wi-Fi 下用电脑浏览器看待办、改待办，无需账号'),
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
            subtitle: const Text('导出为 JSON 文件，可自己保存或传到电脑'),
            trailing: const BackChervonRow(),
            onTap: () => modExportData(context),
          ),
          CupertinoListTile(
            title: const Text('导入数据'),
            subtitle: const Text('从 JSON 文件合并（按 uid 比对，新的生效）'),
            trailing: const BackChervonRow(),
            onTap: () => modImportData(context),
          ),
          // 一键把「机型 / 系统 / 版本 + 脱敏日志 + 反馈模板」复制到剪贴板。
          // 目的是让反馈发生在 QQ 群、论坛帖这类没门槛的地方时，也能说清现场。
          CupertinoListTile(
            title: const Text('复制反馈信息'),
            subtitle: const Text('机型、系统、版本 + 脱敏日志，直接粘到反馈渠道'),
            trailing: const BackChervonRow(),
            onTap: () => modCopyFeedback(context),
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
          : '默认 15 分钟。想连着干可以把休息设成「不休息」。',
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
      subtitle: const Text('到点自动在工作 / 休息之间交替；下一次专注生效'),
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
    if (_granted == false) return '需要「勿扰访问权限」，点这里去系统设置里授予';
    return '专注期间自动切到完全静音，结束时还原成原来的档位';
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
      subtitle: const Text('工作段走完时弹一条通知，提醒起来走走'),
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
