import 'package:celechron/design/alarm_theme_picker.dart';
import 'package:celechron/mod/ai/ai_settings_page.dart';
import 'package:celechron/mod/ai/deepseek.dart';
import 'package:celechron/mod/lan_sync_page.dart';
import 'package:celechron/mod/settings_data_actions.dart';
import 'package:celechron/page/option/option_controller.dart';
import 'package:celechron/page/option/option_view.dart' show BackChervonRow;
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';

/// ============ 设置页里属于魔改的两个区块 ============
///
/// 上游的 `lib/page/option/option_view.dart` 一直在更新（1.3 就加了 36 行），
/// 所以把这些声明式的设置行放在这里，那个文件里只留两处挂载（见 `// ===== MOD =====`）。

/// 待办提醒方式 / 闹钟配色
List<CupertinoListTile> modReminderTiles(
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
        ]));

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
