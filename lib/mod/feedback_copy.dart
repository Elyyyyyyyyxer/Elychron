import 'dart:io';

import 'package:celechron/services/diagnostic_log_service.dart';
import 'package:celechron/worker/fuse.dart';
import 'package:flutter/services.dart';

/// 一键生成「反馈信息」文本：机型 / 系统 / 版本 + 脱敏日志 + 反馈模板。
///
/// 为什么做这个：GitHub Issues 对普通学生门槛太高（要注册、要邮箱验证），
/// 真实反馈多半发生在 QQ 群、论坛帖这类地方 —— 而那些地方没法自动附上日志，
/// 用户也说不清自己是什么机型、什么版本、什么系统。
/// 把该问的信息一次性复制好，反馈质量会高得多，也省去来回追问。
///
/// 日志取自 [DiagnosticLogService.recentText]，与「导出并分享」用的是同一份
/// **已脱敏**内容（密码、Cookie、Session、票据、学号都会被隐藏）。
class FeedbackCopy {
  FeedbackCopy._();

  static const MethodChannel _channel = MethodChannel('celechron/device');

  /// 日志最多带多少行：够定位问题，又不至于长到没法粘贴。
  static const int logTailLines = 120;

  /// 机型与系统版本。拿不到时退回一个不撒谎的兜底值。
  static Future<String> deviceSummary() async {
    try {
      final info = await _channel.invokeMapMethod<String, Object?>('info');
      if (info != null) {
        final name = '${info['manufacturer'] ?? ''} ${info['model'] ?? ''}'.trim();
        final release = info['release'] ?? '';
        final sdk = info['sdk'] ?? '';
        if (name.isNotEmpty) {
          return '$name ｜ Android $release (SDK $sdk)';
        }
      }
    } on Object {
      // 通道不可用时走下面的兜底
    }
    return Platform.operatingSystem;
  }

  /// 生成完整反馈文本
  static Future<String> build() async {
    final device = await deviceSummary();
    final log = await DiagnosticLogService.instance.recentText();
    final tail = tailLines(log, logTailLines);
    return '''
【Elychron 反馈】
版本：${Fuse.appVersionName} (build ${Fuse.appBuildNumber})
设备：$device

【问题描述】


【复现步骤】
1. 

【期望结果】


【实际结果】


【脱敏日志（最近 $logTailLines 行；密码 / Cookie / 学号已自动隐藏）】
$tail''';
  }

  /// 取日志的**尾部**若干行（纯函数，便于单测）。
  ///
  /// 出问题时的现场在最后，所以截尾而不是截头；空行先剔掉，免得复制出来一半是空行。
  static String tailLines(String text, int maxLines) {
    if (maxLines <= 0) return '';
    final lines = text
        .split('\n')
        .map((line) => line.trimRight())
        .where((line) => line.trim().isNotEmpty)
        .toList();
    if (lines.length <= maxLines) return lines.join('\n');
    return lines.sublist(lines.length - maxLines).join('\n');
  }
}
