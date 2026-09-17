import 'package:celechron/design/dingtalk_sheet.dart';
import 'package:celechron/page/option/diagnostic_log_page.dart';
import 'package:celechron/page/option/option_controller.dart';
import 'package:celechron/page/scholar/scholar_controller.dart';
import 'package:celechron/services/diagnostic_log_service.dart';
import 'package:celechron/services/diagnostic_report.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';

/// ===== 「登录与接口连通性」面板（2026-09-17）=====
///
/// 用户要求：「应该提供一个**长按登录**可以查看**哪些网页链接成功**的功能」。
///
/// 现状的问题：出问题时（登录不上、课表刷不出来、成绩不更新）用户只能去
/// 「设置 → 诊断与测试」逐条翻日志 —— 那一页是给维护者看的（易读报告 + 原始日志），
/// 对普通用户信息过载。这里把用户最想问的那一句单独做出来：
///
///   **那几条接口到底通没通**（校历 / 课表 / 考试 / 成绩 / 主修 / 作业 / 素质拓展），
///   每条一句话 + 什么时候查的；没通的单独列出来。
///
/// 数据直接复用现成的诊断日志（[DiagnosticLogService]），**不额外发请求**；
/// 想看最新的就点「重新检查」，它才会真的跑一次刷新。
///
/// 入口：设置页「已登录 / 登录已失效」那一行**长按**（见 option_view.dart），
/// 以及登录页的登录按钮长按。
Future<void> showLoginConnectivityPanel(BuildContext context) async {
  final report = _latestReport();
  final modules = report?.modules ?? const <DiagnosticModuleReport>[];
  final failures =
      modules.where((m) => m.state == DiagnosticModuleState.failed).toList();
  final degraded =
      modules.where((m) => m.state == DiagnosticModuleState.cache).toList();

  await showDingTalkPanel(
    context: context,
    title: '登录与接口连通性',
    subtitle: report == null
        ? '还没有刷新记录 —— 点下面的「重新检查」跑一次'
        : '最近一次刷新：${_timeText(report.startedAtUtc)}'
            '（${_originText(report.origin)}）',
    children: [
      if (report != null) ...[
        DingTalkPanelNote(
            '成功 ${report.successCount} · 走缓存 ${report.degradedCount} · 失败 ${report.failedCount}'),
      ],
      for (final module in modules)
        DingTalkInfoRow(
          label: module.name,
          value: _stateText(module),
          ok: module.state == DiagnosticModuleState.liveSuccess,
        ),
      // 没通的单独说清楚：这是用户最想知道的
      if (failures.isNotEmpty)
        DingTalkPanelNote(
            '没连上的：${failures.map((m) => m.name).join('、')} —— '
            '多半是学校服务器暂时连不上（教务经常返回 HTTP 921 限流），过一会儿再试。'),
      if (degraded.isNotEmpty)
        DingTalkPanelNote(
            '走缓存的：${degraded.map((m) => m.name).join('、')} —— '
            '这次没连上，但本地有上次的数据，所以还能看。'),
      const DingTalkPanelNote(
          '口径：「实时成功」= 这次真的连上了学校服务器；'
          '「走缓存」= 没连上但用的是上次存下来的数据；'
          '「未参与」= 这次没查它（例如没登录）。'),
      const DingTalkPanelNote('想看每一条请求的网址和返回码，去「设置 → 测试日志」。'),
    ],
    secondaryActions: [
      DingTalkPanelAction(
        label: '重新检查',
        onTap: () async {
          Navigator.of(context).pop();
          await _runRefresh(context);
          if (context.mounted) await showLoginConnectivityPanel(context);
        },
      ),
      DingTalkPanelAction(
        label: '完整日志',
        onTap: () {
          Navigator.of(context).pop();
          Navigator.of(context, rootNavigator: true).push(
            CupertinoPageRoute(
              builder: (context) => DiagnosticLogPage(
                version: Get.isRegistered<OptionController>()
                    ? Get.find<OptionController>().celechronVersion
                    : '',
              ),
            ),
          );
        },
      ),
    ],
  );
}

/// 跑一次真实刷新（「重新检查」用）
Future<void> _runRefresh(BuildContext context) async {
  if (!Get.isRegistered<ScholarController>()) return;
  try {
    await Get.find<ScholarController>().fetchData();
  } catch (_) {
    // 刷新失败本身不用弹错：面板里会把失败的那几条列出来
  }
}

/// 从内存里的诊断日志解析出最近一次刷新报告（解析失败就当没有）
DiagnosticRefreshReport? _latestReport() {
  try {
    final text = DiagnosticLogService.instance.currentText();
    if (text.trim().isEmpty) return null;
    return const DiagnosticReportParser().parse(text).latestReport;
  } catch (_) {
    return null;
  }
}

String _stateText(DiagnosticModuleReport module) {
  final duration = module.durationMs;
  final cost = (duration == null || duration <= 0)
      ? ''
      : '（${duration >= 1000 ? '${(duration / 1000).toStringAsFixed(1)} 秒' : '$duration 毫秒'}）';
  switch (module.state) {
    case DiagnosticModuleState.liveSuccess:
      return '实时成功$cost';
    case DiagnosticModuleState.cache:
      return '走缓存';
    case DiagnosticModuleState.failed:
      return '没连上';
    case DiagnosticModuleState.notExecuted:
      return '未参与';
  }
}

String _originText(String origin) {
  switch (origin) {
    case 'background':
      return '后台刷新';
    case 'probe':
      return '探测';
    default:
      return '前台刷新';
  }
}

String _timeText(DateTime utc) {
  final local = utc.toLocal();
  final now = DateTime.now();
  final diff = now.difference(local);
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前（$hh:$mm）';
  if (diff.inHours < 24) return '${diff.inHours} 小时前（$hh:$mm）';
  return '${local.month}-${local.day} $hh:$mm';
}
