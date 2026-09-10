/// 删除墓碑：记录「某条待办在某时刻被删掉了」。
///
/// 同步时如果只传"现存待办"，另一端会把已被删除的待办又推回来。
/// 所以删除不只是在本地移除，还要留下墓碑，让合并时知道这条是被删的。
class TaskTombstone {
  final String uid;
  final DateTime deletedAt;

  const TaskTombstone({required this.uid, required this.deletedAt});

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'deletedAt': deletedAt.toIso8601String(),
      };

  static TaskTombstone? fromJson(Map<String, dynamic> json) {
    final uid = json['uid'];
    final deletedAt = DateTime.tryParse('${json['deletedAt']}');
    if (uid is! String || uid.isEmpty || deletedAt == null) return null;
    return TaskTombstone(uid: uid, deletedAt: deletedAt);
  }

  @override
  String toString() => 'TaskTombstone($uid @ $deletedAt)';
}
