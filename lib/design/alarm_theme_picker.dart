import 'dart:ui';

import 'package:celechron/design/alarm_theme.dart';
import 'package:celechron/database/database_helper.dart';
import 'package:celechron/mod/database_mod.dart';
import 'package:celechron/model/task.dart';
import 'package:celechron/page/task/task_alarm_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';

/// 闹钟配色选择：每个预设都带一个小预览
Future<void> showAlarmThemePicker(
  BuildContext context, {
  required VoidCallback onChanged,
}) {
  return showCupertinoModalPopup<void>(
    context: context,
    builder: (BuildContext context) =>
        _AlarmThemePickerSheet(onChanged: onChanged),
  );
}

class _AlarmThemePickerSheet extends StatefulWidget {
  final VoidCallback onChanged;

  const _AlarmThemePickerSheet({required this.onChanged});

  @override
  State<_AlarmThemePickerSheet> createState() => _AlarmThemePickerSheetState();
}

class _AlarmThemePickerSheetState extends State<_AlarmThemePickerSheet> {
  String _current = 'tianyi';

  @override
  void initState() {
    super.initState();
    try {
      _current = Get.find<DatabaseHelper>(tag: 'db').getAlarmTheme();
    } catch (_) {}
  }

  Future<void> _select(String id) async {
    setState(() => _current = id);
    try {
      await Get.find<DatabaseHelper>(tag: 'db').setAlarmTheme(id);
    } catch (_) {}
    widget.onChanged();
    if (!mounted) return;
    // 选中后直接打开真实的闹钟页做预览
    await Navigator.of(context, rootNavigator: true).push(
      CupertinoPageRoute(
        fullscreenDialog: true,
        builder: (BuildContext context) => TaskAlarmPage(
          task: _previewTask(),
          preview: true,
          themeId: id,
        ),
      ),
    );
  }

  /// 预览用的示例待办
  Task _previewTask() {
    final end = DateTime.now().add(const Duration(hours: 3));
    final task = Task(
      summary: '写给自己的一封信',
      description: '这是预览效果，真实提醒时会显示待办内容和截止时间',
      endTime: end,
      startTime: end,
      repeatEndsTime: DateTime(end.year, end.month, end.day),
    );
    task.reset();
    task.summary = '写给自己的一封信';
    task.description = '这是预览效果，真实提醒时会显示待办内容和截止时间';
    task.startTime = end;
    task.endTime = end;
    task.repeatEndsTime = DateTime(end.year, end.month, end.day);
    return task;
  }

  /// 迷你预览：模拟闹钟页的样子
  Widget _preview(AlarmTheme theme) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 96,
        width: 150,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [theme.backgroundStart, theme.backgroundEnd],
          ),
        ),
        child: Stack(
          children: [
            // 毛玻璃小球，体现质感
            Positioned(
              left: 18,
              top: 16,
              child: ClipOval(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: theme.glass,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 84,
              top: 24,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 9,
                    decoration: BoxDecoration(
                      color: theme.text.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                  const SizedBox(height: 7),
                  Container(
                    width: 34,
                    height: 7,
                    decoration: BoxDecoration(
                      color: theme.text.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 14,
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 16,
                      decoration: BoxDecoration(
                        color: theme.glass,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: theme.primary.withValues(alpha: 0.5)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 46,
                    height: 16,
                    decoration: BoxDecoration(
                      color: theme.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final labelColor =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    final textColor = CupertinoTheme.of(context).textTheme.textStyle.color;

    return Container(
      decoration: BoxDecoration(
        color: CupertinoDynamicColor.resolve(
            CupertinoColors.systemBackground, context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
              child: Row(
                children: [
                  const SizedBox(width: 64),
                  const Spacer(),
                  Text('闹钟配色',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: textColor)),
                  const Spacer(),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(64, 44),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('完成'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: kAlarmThemes.map((theme) {
                  final selected = _current == theme.id;
                  return GestureDetector(
                    onTap: () => _select(theme.id),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: selected
                              ? theme.primary
                              : CupertinoDynamicColor.resolve(
                                  CupertinoColors.separator, context),
                          width: selected ? 2 : 0.5,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _preview(theme),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (selected) ...[
                                Icon(CupertinoIcons.checkmark_circle_fill,
                                    size: 16, color: theme.primary),
                                const SizedBox(width: 4),
                              ],
                              Text(
                                theme.name,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: selected
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  color: textColor,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            Text('点一下配色即可看到真实闹钟页预览',
                style: TextStyle(fontSize: 12, color: labelColor)),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
