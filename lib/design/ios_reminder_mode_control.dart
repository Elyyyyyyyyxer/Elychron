import 'package:celechron/mod/system_alarm.dart';
import 'package:flutter/cupertino.dart';

class IosReminderModeControl extends StatelessWidget {
  final int mode;
  final ValueChanged<int> onChanged;

  const IosReminderModeControl({
    super.key,
    required this.mode,
    required this.onChanged,
  });

  Future<void> _select(BuildContext context, int? value) async {
    if (value == null || value == mode) return;
    if (value == 1 && !await SystemAlarm.isSupported()) {
      if (!context.mounted) return;
      await showCupertinoDialog<void>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('原生闹钟暂不可用'),
          content: const Text(
              '需要 iOS / iPadOS 26 或更新版本，并允许 Elychron 使用闹钟。仍可选择通知提醒。'),
          actions: [
            CupertinoDialogAction(
              child: const Text('好'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      );
      return;
    }
    if (context.mounted) onChanged(value);
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('提醒方式', style: TextStyle(fontSize: 15)),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: CupertinoSlidingSegmentedControl<int>(
                groupValue: mode,
                children: const {0: Text('通知'), 1: Text('原生闹钟')},
                onValueChanged: (value) => _select(context, value),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '保存后生效；原生闹钟不可用时改用通知。',
              style: TextStyle(
                fontSize: 12,
                color: CupertinoDynamicColor.resolve(
                    CupertinoColors.secondaryLabel, context),
              ),
            ),
          ],
        ),
      );
}
