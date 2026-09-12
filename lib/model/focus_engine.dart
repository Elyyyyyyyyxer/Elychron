/// ===== P3：专注计时的**纯逻辑** =====
///
/// 刻意不碰 UI、不碰数据库、不依赖 Flutter —— 状态机最容易写错，
/// 单独放一个文件才能用单测把「工作→休息→工作」的边界钉住。
///
/// 时间推进用**墙上时钟**（`tick(now)` 传入当前时刻）而不是累加 1 秒：
/// 切后台、锁屏、甚至系统把定时器挂起之后，回到前台第一次 tick 就会把
/// 落下的时间补上，不会因为「定时器没跑」而少算。
library;

/// 专注倒计时的显示：`59:58` / `1:00:00`。
///
/// 三个坑都踩过，所以写在这里：
/// 1. 分钟必须**对 3600 取模** —— 否则刚满一小时是 `1:60:00`，90 分钟是 `1:90:00`；
/// 2. [withHours] 为 true 时**始终**带小时位 —— 否则倒计时从 `1:00:00` 走到下一秒
///    会变成 `59:59`，位数变了看着像掉了一格。调用方按**这一段的总时长**决定，
///    这样整段格式稳定；
/// 3. 秒数**向上取整**（剩 59:58.7 显示 59:59）—— 定时器晚几十毫秒是常态，
///    截断就会出现「1:00:00 → 0:59:58」这种一次跳两秒的观感。
String focusClock(Duration d, {bool withHours = false}) {
  final ms = d.inMilliseconds;
  final total = ms <= 0 ? 0 : (ms / 1000).ceil();
  final hours = total ~/ 3600;
  final minutes = ((total % 3600) ~/ 60).toString().padLeft(2, '0');
  final seconds = (total % 60).toString().padLeft(2, '0');
  return (withHours || hours > 0)
      ? '$hours:$minutes:$seconds'
      : '$minutes:$seconds';
}

/// 专注时长的口语化写法：`1 小时 20 分` / `45 分` / `30 秒`。
String focusHuman(Duration d) {
  final total = d.isNegative ? -d : d;
  final hours = total.inHours;
  final minutes = total.inMinutes % 60;
  if (hours > 0) return minutes > 0 ? '$hours 小时 $minutes 分' : '$hours 小时';
  if (minutes > 0) return '$minutes 分';
  return '${total.inSeconds} 秒';
}

enum FocusPhase {  /// 还没开始 / 已经结束
  idle,

  /// 工作段
  working,

  /// 休息段
  resting,

  /// 暂停（记住暂停前是工作还是休息）
  paused,
}

class FocusEngine {
  FocusEngine({
    required int workMinutes,
    required int restMinutes,
    DateTime? now,
  })  : workMinutes = workMinutes < 1 ? 1 : workMinutes,
        restMinutes = restMinutes < 0 ? 0 : restMinutes,
        _now = now;

  /// 本轮参数（分钟）
  final int workMinutes;
  final int restMinutes;

  FocusPhase _phase = FocusPhase.idle;
  FocusPhase _pausedFrom = FocusPhase.working;
  Duration _remaining = Duration.zero;
  Duration _focused = Duration.zero;
  Duration _rested = Duration.zero;
  int _rounds = 0;
  DateTime? _now;

  FocusPhase get phase => _phase;

  /// 当前这一段还剩多久
  Duration get remaining => _remaining;

  /// 累计专注时长（不含休息）
  Duration get focused => _focused;

  /// 累计休息时长
  Duration get rested => _rested;

  /// 已完成的轮数（走完一个完整的工作段算一轮）
  int get rounds => _rounds;

  bool get isIdle => _phase == FocusPhase.idle;
  bool get isPaused => _phase == FocusPhase.paused;
  bool get isWorking => _phase == FocusPhase.working;
  bool get isResting => _phase == FocusPhase.resting;

  /// 当前这一段的进度 0..1（大圆环用）
  double get progress {
    final total = _totalOf(_phase == FocusPhase.paused ? _pausedFrom : _phase);
    if (total <= Duration.zero) return 0;
    final done = total - _remaining;
    final value = done.inMilliseconds / total.inMilliseconds;
    return value.clamp(0.0, 1.0);
  }

  Duration _totalOf(FocusPhase phase) => switch (phase) {
        FocusPhase.working => Duration(minutes: workMinutes),
        FocusPhase.resting => Duration(minutes: restMinutes),
        _ => Duration(minutes: workMinutes),
      };

  /// 开始专注（从工作段起步）
  void start(DateTime now) {
    _phase = FocusPhase.working;
    _pausedFrom = FocusPhase.working;
    _remaining = Duration(minutes: workMinutes);
    _focused = Duration.zero;
    _rested = Duration.zero;
    _rounds = 0;
    _now = now;
  }

  /// 推进到 [now]。
  ///
  /// 落下的时间一次算完，跨过的段也会依次切换（比如锁屏两小时回来，
  /// 会把工作段、休息段都正确结算）。
  void tick(DateTime now) {
    final last = _now;
    _now = now;
    if (last == null) return;
    if (_phase != FocusPhase.working && _phase != FocusPhase.resting) return;

    var delta = now.difference(last);
    if (delta <= Duration.zero) return;

    // 一次 tick 最多只结算一段的时间量，避免异常时钟把统计算爆
    var guard = 0;
    while (delta > Duration.zero && guard < 1000) {
      guard++;
      if (_phase == FocusPhase.working) {
        final take = delta < _remaining ? delta : _remaining;
        _focused += take;
        _remaining -= take;
        delta -= take;
        if (_remaining <= Duration.zero) _enterRest();
      } else if (_phase == FocusPhase.resting) {
        final take = delta < _remaining ? delta : _remaining;
        _rested += take;
        _remaining -= take;
        delta -= take;
        if (_remaining <= Duration.zero) _enterWork();
      } else {
        break;
      }
    }
  }

  void _enterRest() {
    _rounds++;
    if (restMinutes <= 0) {
      // 没设休息就直接接下一轮工作（休息时长可以为 0）
      _enterWork();
      return;
    }
    _phase = FocusPhase.resting;
    _remaining = Duration(minutes: restMinutes);
  }

  void _enterWork() {
    _phase = FocusPhase.working;
    _remaining = Duration(minutes: workMinutes);
  }

  /// 暂停：记住暂停前是工作还是休息，继续时回到那一段
  void pause() {
    if (_phase != FocusPhase.working && _phase != FocusPhase.resting) return;
    _pausedFrom = _phase;
    _phase = FocusPhase.paused;
  }

  void resume(DateTime now) {
    if (_phase != FocusPhase.paused) return;
    _phase = _pausedFrom;
    _now = now;
  }

  /// 跳过休息，直接开始下一轮工作（不影响已统计的专注时长）
  void skipRest() {
    if (_phase != FocusPhase.resting) return;
    _enterWork();
  }

  /// 结束（提前结束也是它）
  void stop() {
    _phase = FocusPhase.idle;
    _remaining = Duration.zero;
  }
}
