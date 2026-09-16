import 'package:celechron/model/focus_session.dart';
import 'package:hive/hive.dart';

/// P3 专注会话的 Hive 适配器（typeId 20，新增类型，不影响既有数据）。
class FocusSessionAdapter extends TypeAdapter<FocusSession> {
  @override
  final typeId = 20;

  @override
  void write(BinaryWriter writer, FocusSession obj) {
    writer
      ..writeByte(12)
      ..writeByte(0)
      ..write(obj.uid)
      ..writeByte(1)
      ..write(obj.taskUid)
      ..writeByte(2)
      ..write(obj.label)
      ..writeByte(3)
      ..write(obj.startedAt)
      ..writeByte(4)
      ..write(obj.endedAt)
      ..writeByte(5)
      ..write(obj.focusedTime)
      ..writeByte(6)
      ..write(obj.restTime)
      ..writeByte(7)
      ..write(obj.rounds)
      ..writeByte(8)
      ..write(obj.workMinutes)
      ..writeByte(9)
      ..write(obj.restMinutes)
      ..writeByte(10)
      ..write(obj.completed)
      // ===== MOD: 课程归属（见 FocusSession.courseId）=====
      ..writeByte(11)
      ..write(obj.courseId);
  }

  @override
  FocusSession read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (var i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    final startedAt = fields[3] as DateTime? ?? DateTime.now();
    return FocusSession(
      uid: fields[0] as String?,
      taskUid: fields[1] as String?,
      label: fields[2] as String? ?? '',
      startedAt: startedAt,
      endedAt: fields[4] as DateTime?,
      focusedTime: fields[5] as Duration? ?? Duration.zero,
      restTime: fields[6] as Duration? ?? Duration.zero,
      rounds: fields[7] as int? ?? 0,
      workMinutes: fields[8] as int? ?? 60,
      restMinutes: fields[9] as int? ?? 15,
      completed: fields[10] as bool? ?? false,
      // 老会话没有这一项 → null，正好表示"没归到任何课程"
      courseId: fields[11] as String?,
    );
  }
}
