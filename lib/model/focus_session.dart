import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

/// ===== P3：一次专注的会话记录 =====
///
/// 这是「专注」功能唯一新增的持久化结构。设计要点：
/// - 与「时间规划」彻底无关：它只回答**我实际花了多久**，不回答「什么时候做」；
/// - `endedAt == null` 表示**还没正常结束**（App 被杀掉时留下的），
///   下次启动会按最后一次 flush 的进度**如实结算**，不让用户白干；
/// - 任务侧只累加 `Task.timeSpent`（那个 Hive 字段一直被留着，正好复用），
///   不动任务本身的结构。
@HiveType(typeId: 20)
class FocusSession {
  @HiveField(0)
  String uid;

  /// 关联的待办；null = 自由专注（比如「敲代码」）
  @HiveField(1)
  String? taskUid;

  /// 会话名字：关联任务时是任务标题，自由专注时是用户起的名
  @HiveField(2)
  String label;

  @HiveField(3)
  DateTime startedAt;

  /// null = 还在进行 / 没正常结束
  @HiveField(4)
  DateTime? endedAt;

  /// 实际专注时长（**不含休息**）
  @HiveField(5)
  Duration focusedTime;

  /// 实际休息时长
  @HiveField(6)
  Duration restTime;

  /// 完成的轮数（完整走完的「工作」段数）
  @HiveField(7)
  int rounds;

  /// 本次参数，便于以后回溯（设置改了也能看出当时是几比几）
  @HiveField(8)
  int workMinutes;

  @HiveField(9)
  int restMinutes;

  /// true = 用户正常结束；false = 中途放弃或崩溃后结算
  @HiveField(10)
  bool completed;

  FocusSession({
    String? uid,
    this.taskUid,
    this.label = '',
    required this.startedAt,
    this.endedAt,
    this.focusedTime = Duration.zero,
    this.restTime = Duration.zero,
    this.rounds = 0,
    this.workMinutes = 60,
    this.restMinutes = 15,
    this.completed = false,
  }) : uid = uid ?? const Uuid().v4();

  bool get isRunning => endedAt == null;

  /// 这次专注一共经过的时间（含休息）
  Duration get totalTime => focusedTime + restTime;

  /// 会话显示名：自由专注没起名就叫「专注」
  String get displayName => label.trim().isEmpty ? '专注' : label.trim();

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'taskUid': taskUid,
        'label': label,
        'startedAt': startedAt.toIso8601String(),
        'endedAt': endedAt?.toIso8601String(),
        'focusedSeconds': focusedTime.inSeconds,
        'restSeconds': restTime.inSeconds,
        'rounds': rounds,
        'workMinutes': workMinutes,
        'restMinutes': restMinutes,
        'completed': completed,
      };

  static FocusSession fromJson(Map<String, dynamic> json) => FocusSession(
        uid: json['uid'] is String ? json['uid'] as String : null,
        taskUid: json['taskUid'] is String ? json['taskUid'] as String : null,
        label: '${json['label'] ?? ''}',
        startedAt: DateTime.tryParse('${json['startedAt']}') ?? DateTime.now(),
        endedAt: json['endedAt'] is String
            ? DateTime.tryParse(json['endedAt'] as String)
            : null,
        focusedTime: Duration(seconds: _int(json['focusedSeconds'])),
        restTime: Duration(seconds: _int(json['restSeconds'])),
        rounds: _int(json['rounds']),
        workMinutes: _int(json['workMinutes'], fallback: 60),
        restMinutes: _int(json['restMinutes'], fallback: 15),
        completed: json['completed'] == true,
      );

  static int _int(Object? raw, {int fallback = 0}) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return fallback;
  }
}
