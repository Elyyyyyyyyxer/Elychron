import 'package:celechron/services/diagnostic_log_service.dart';

/// ============ 循环保护 / 卡死诊断 ============
///
/// 背景：App 出现过「用着用着突然卡死，只能重启」的情况，而且**没有 ANR 记录、
/// 没有崩溃日志**——这几乎只可能是 **UI 线程上的死循环**（Dart 代码在同一个
/// isolate 里转圈，系统看不到 ANR，但因为一直不返回，界面完全没响应）。
///
/// 项目里有一批「理论上有限、但依赖数据正确性」的 while 循环（重复日程滚动、
/// 排程、锁文件重试……）。只要数据里出现一个畸形值（比如 repeatPeriod 异常、
/// 时间字段损坏），这些循环就可能永远不前进。
///
/// 所以这里做两件事：
///   1. `LoopGuard`：给这类循环加一个硬上限，超限就中断并记诊断日志（而不是卡死）
///   2. `SlowWatch`：给每秒定时器测耗时，超过阈值就记一条，方便定位是谁在拖
///
/// 记下的日志会出现在「设置 → 诊断与测试 → 测试日志」里，用户可以直接复制出来。
class LoopGuard {
  LoopGuard(this.what, {this.limit = defaultLimit});

  /// 任何「应该有限」的循环都不该迭代超过这个次数
  static const int defaultLimit = 2000;

  final String what;
  final int limit;
  int _iterations = 0;

  /// 每轮循环开头调用；返回 true 表示「已经超限，请立刻 break」
  bool tick() {
    _iterations++;
    if (_iterations <= limit) return false;
    DiagnosticLogService.instance.record(
      level: CelechronLogLevel.error,
      module: '可靠性',
      operation: what,
      message: '循环超过 $limit 次仍未结束，已强制中断（否则界面会卡死）。'
          '这通常意味着某条数据畸形（例如重复周期异常、时间字段损坏）。',
    );
    return true;
  }

  /// 循环正常结束后调用，用于记录"离上限还有多远"（只在接近上限时记，避免刷屏）
  void done() {
    if (_iterations > limit ~/ 2) {
      DiagnosticLogService.instance.record(
        level: CelechronLogLevel.warning,
        module: '可靠性',
        operation: what,
        message: '循环迭代 $_iterations 次（上限 $limit），已接近危险值，建议检查数据。',
      );
    }
  }
}

/// 给「每秒跑一次」的逻辑测耗时：慢过阈值就记一条日志，用来说明卡在哪一步
class SlowWatch {
  SlowWatch(this.what, {this.thresholdMs = 400});

  final String what;
  final int thresholdMs;
  final Stopwatch _watch = Stopwatch();

  void start() => _watch
    ..reset()
    ..start();

  /// 返回耗时（毫秒）
  int stop({String detail = ''}) {
    _watch.stop();
    final ms = _watch.elapsedMilliseconds;
    if (ms >= thresholdMs) {
      DiagnosticLogService.instance.record(
        level: CelechronLogLevel.warning,
        module: '性能',
        operation: what,
        message: '$what 耗时 ${ms}ms（阈值 ${thresholdMs}ms）'
            '${detail.isEmpty ? '' : '：$detail'}',
      );
    }
    return ms;
  }
}
