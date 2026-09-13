import 'package:celechron/model/task.dart';
import 'package:celechron/services/diagnostic_log_service.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

/// 把一条待办**交给系统时钟**（而不是我们自己的通知/全屏闹钟）。
///
/// 为什么单独做这个：其他 App 的提醒在系统眼里优先级低于系统时钟，
/// 关键事项（考试、集合、赶车）交给系统时钟最稳。
///
/// ⚠️ **必须说清楚的限制**（界面上也要写）：
/// 1. 系统只提供「设置闹钟」，**没有「按标签删除闹钟」的接口** ——
///    待办删了/完成了，这个闹钟**不会跟着撤销**，时间改了也是新增一个；
/// 2. 一次性，设不了"每周重复"；
/// 3. 只有一个标题，没有「延迟/划掉」以外的交互。
///
/// 所以它只适合「必须叫醒我」的一次性关键事项，不做成常驻提醒方式。
class SystemAlarm {
  SystemAlarm._();

  static const MethodChannel _channel = MethodChannel('celechron/alarm');

  /// 这台设备有没有能接收「设置闹钟」的应用
  static Future<bool> isSupported() async {
    try {
      return await _channel.invokeMethod<bool>('canSetSystemAlarm') ?? false;
    } on Object {
      return false;
    }
  }

  /// 让系统时钟在 [at] 响一次。返回是否提交成功。
  ///
  /// 结果写进诊断日志：这个功能一旦"没反应"，用户只能看到什么都没发生，
  /// 有日志才能区分「设备没有处理程序」「系统拒绝了」「提交成功但没响」。
  static Future<bool> set({required DateTime at, required String label}) async {
    try {
      final ok = await _channel.invokeMethod<bool>('setSystemAlarm', {
            'hour': at.hour,
            'minutes': at.minute,
            'label': label,
          }) ??
          false;
      _log(ok, at, ok ? '已提交给系统时钟' : '系统时钟拒绝了这次请求');
      return ok;
    } on Object catch (error) {
      _log(false, at, '调用系统闹钟失败：$error');
      return false;
    }
  }

  static void _log(bool ok, DateTime at, String message) {
    try {
      if (!Get.isRegistered<DiagnosticLogService>()) return;
      Get.find<DiagnosticLogService>().record(
        level: ok ? CelechronLogLevel.info : CelechronLogLevel.warning,
        module: '系统闹钟',
        operation: 'setSystemAlarm',
        message: '${_two(at.hour)}:${_two(at.minute)} $message',
      );
    } catch (_) {
      // 日志本身不该影响功能
    }
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}

/// 某条待办交给系统时钟时应该定在几点。返回 null 表示它不适合（不显示在列表里）。
///
/// 规则（纯函数，便于单测）：
/// - 已完成 / 已删除 / 备忘型 → 不适合（备忘本来就不提醒）
/// - 有「提醒时间」就用它（那是用户明确设过的时刻）
/// - 否则用截止/开始时刻：活动锚**开始**、截止与提醒锚各自的时刻
/// - 已经过去的时间 → 不适合（系统闹钟设到过去只会立刻响）
DateTime? systemAlarmTimeFor(Task task, DateTime now) {
  if (task.status == TaskStatus.completed || task.status == TaskStatus.deleted) {
    return null;
  }
  if (task.isMemo) return null;

  // startTime / endTime 在模型里都是非空的（备忘型已在上面排除）
  final DateTime candidate;
  if (task.reminderEnabled) {
    final reminder = task.reminderTime;
    if (reminder == null) return null;
    candidate = reminder;
  } else if (task.isEvent) {
    candidate = task.startTime;
  } else {
    candidate = task.endTime;
  }

  // 留 1 分钟余量：正好等于此刻的时刻，交给系统再执行就已经过去了
  if (!candidate.isAfter(now.add(const Duration(minutes: 1)))) return null;
  return candidate;
}

/// 系统闹钟的标题：`Elychron · 待办标题`（在时钟 App 里能一眼认出是谁设的）
String systemAlarmLabelFor(Task task) {
  final title = task.summary.trim();
  return title.isEmpty ? 'Elychron · 待办' : 'Elychron · $title';
}
