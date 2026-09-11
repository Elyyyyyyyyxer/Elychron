import 'dart:async';
import 'dart:ui';

import 'package:celechron/design/alarm_theme.dart';
import 'package:celechron/database/database_helper.dart';
import 'package:celechron/mod/database_mod.dart';
import 'package:celechron/model/task.dart';
import 'package:celechron/utils/alarm_player.dart';
import 'package:celechron/page/task/task_controller.dart';
import 'package:celechron/utils/task_alarm_center.dart';
import 'package:get/get.dart';
import 'package:celechron/utils/task_reminder.dart';
import 'package:celechron/utils/time_helper.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

/// 闹钟模式：全屏提醒，可以「延迟提醒」或「划掉」，铃声循环播放。
class TaskAlarmPage extends StatefulWidget {
  final Task task;

  /// 预览模式：不响铃、不震动，底部只显示「返回」
  final bool preview;

  /// 预览时强制使用的配色 id
  final String? themeId;

  const TaskAlarmPage({
    super.key,
    required this.task,
    this.preview = false,
    this.themeId,
  });

  @override
  State<TaskAlarmPage> createState() => _TaskAlarmPageState();
}

class _TaskAlarmPageState extends State<TaskAlarmPage> {
  Timer? _ticker;
  bool _handled = false;
  AlarmTheme _theme = kAlarmThemes.first;

  @override
  void initState() {
    super.initState();
    try {
      _theme = alarmThemeOf(widget.themeId ??
          Get.find<DatabaseHelper>(tag: 'db').getAlarmTheme());
    } catch (_) {
      _theme = alarmThemeOf(widget.themeId);
    }
    if (!widget.preview) {
      AlarmPlayer.start();
      // 边响边震，直到用户处理
      _ticker = Timer.periodic(const Duration(seconds: 2), (_) {
        HapticFeedback.heavyImpact();
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    AlarmPlayer.stop();
    super.dispose();
  }

  Future<void> _snooze() async {
    if (_handled) return;
    _handled = true;
    await TaskReminder.snooze(widget.task, const Duration(minutes: 10));
    // 提醒时间已经往后挪，立刻落盘 —— 这样即使马上被系统杀掉也不会再弹旧的
    if (Get.isRegistered<TaskController>()) {
      await Get.find<TaskController>().saveDeadlineListToDb();
    }
    _close();
  }

  Future<void> _dismiss() async {
    if (_handled) return;
    _handled = true;
    await TaskReminder.dismissAlarm(widget.task);
    _close();
  }

  void _close() {
    TaskAlarmCenter.clear();
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final now = DateTime.now();
    final theme = _theme;

    return CupertinoPageScaffold(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [theme.backgroundStart, theme.backgroundEnd],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              // 背景装饰光斑，衬托毛玻璃
              Positioned(
                left: -60,
                top: 40,
                child: _blob(theme.primary.withValues(alpha: 0.45), 220),
              ),
              Positioned(
                right: -70,
                bottom: 120,
                child: _blob(theme.primary.withValues(alpha: 0.32), 260),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Column(
                  children: [
                    const Spacer(),
                    // 毛玻璃卡片
                    ClipRRect(
                      borderRadius: BorderRadius.circular(28),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 22, vertical: 28),
                          decoration: BoxDecoration(
                            color: theme.glass,
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(
                              color:
                                  CupertinoColors.white.withValues(alpha: 0.65),
                              width: 1,
                            ),
                          ),
                          child: Column(
                            children: [
                              Text(
                                '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
                                style: TextStyle(
                                  fontSize: 56,
                                  fontWeight: FontWeight.w300,
                                  color: theme.text,
                                  height: 1.1,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '待办提醒',
                                style: TextStyle(
                                  fontSize: 14,
                                  letterSpacing: 2,
                                  color: theme.text.withValues(alpha: 0.55),
                                ),
                              ),
                              const SizedBox(height: 22),
                              Icon(
                                CupertinoIcons.bell_fill,
                                size: 34,
                                color: theme.primary,
                              ),
                              const SizedBox(height: 14),
                              Text(
                                task.summary.isEmpty ? '(未命名待办)' : task.summary,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w600,
                                  color: theme.text,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                '截止 ${TimeHelper.chineseDateTime(task.endTime)}',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: theme.text.withValues(alpha: 0.6),
                                ),
                              ),
                              if (task.description.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  task.description,
                                  textAlign: TextAlign.center,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: theme.text.withValues(alpha: 0.5),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (widget.preview)
                      SizedBox(
                        width: double.infinity,
                        child: CupertinoButton(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          color: theme.primary,
                          borderRadius: BorderRadius.circular(18),
                          onPressed: () => Navigator.of(context).maybePop(),
                          child: const Text(
                            '返回',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: CupertinoColors.white,
                            ),
                          ),
                        ),
                      )
                    else ...[
                      SizedBox(
                        width: double.infinity,
                        child: CupertinoButton(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          color: CupertinoColors.white.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(18),
                          onPressed: _snooze,
                          child: Text(
                            '延迟提醒（10 分钟）',
                            style: TextStyle(fontSize: 17, color: theme.text),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: CupertinoButton(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          color: theme.primary,
                          borderRadius: BorderRadius.circular(18),
                          onPressed: _dismiss,
                          child: const Text(
                            '划掉',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: CupertinoColors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _blob(Color color, double size) {
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ),
    );
  }
}
