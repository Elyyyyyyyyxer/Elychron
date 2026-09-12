import 'package:hive/hive.dart';
import 'package:celechron/model/task.dart';

class DeadlineStatusAdapter extends TypeAdapter<TaskStatus> {
  @override
  final typeId = 7;

  @override
  void write(BinaryWriter writer, TaskStatus obj) => writer.writeInt(obj.index);

  @override
  TaskStatus read(BinaryReader reader) => TaskStatus.values[reader.readInt()];
}

class DeadlineTypeAdapter extends TypeAdapter<TaskType> {
  @override
  final typeId = 10;

  @override
  void write(BinaryWriter writer, TaskType obj) => writer.writeInt(obj.index);

  @override
  TaskType read(BinaryReader reader) => TaskType.values[reader.readInt()];
}

class DeadlineRepeatTypeAdapter extends TypeAdapter<TaskRepeatType> {
  @override
  final typeId = 11;

  @override
  void write(BinaryWriter writer, TaskRepeatType obj) =>
      writer.writeInt(obj.index);

  @override
  TaskRepeatType read(BinaryReader reader) =>
      TaskRepeatType.values[reader.readInt()];
}

class TaskPriorityAdapter extends TypeAdapter<TaskPriority> {
  @override
  final typeId = 17;

  @override
  void write(BinaryWriter writer, TaskPriority obj) =>
      writer.writeInt(obj.index);

  @override
  TaskPriority read(BinaryReader reader) =>
      TaskPriority.values[reader.readInt()];
}

class SubTaskAdapter extends TypeAdapter<SubTask> {
  @override
  final typeId = 14;

  @override
  void write(BinaryWriter writer, SubTask obj) {
    // 字段数 9 → 11：P2 追加了 startTime(9) 与 reminderMinutes(10)
    writer
      ..writeByte(11)
      ..writeByte(0)
      ..write(obj.uid)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.done)
      ..writeByte(3)
      ..write(obj.description)
      ..writeByte(4)
      ..write(obj.endTime)
      ..writeByte(5)
      ..write(obj.priority)
      ..writeByte(6)
      ..write(obj.tags)
      ..writeByte(7)
      ..write(obj.attachments)
      ..writeByte(8)
      ..write(obj.location)
      ..writeByte(9)
      ..write(obj.startTime)
      ..writeByte(10)
      ..write(obj.reminderMinutes);
  }

  @override
  SubTask read(BinaryReader reader) {
    var numOfFields = reader.readByte();
    var fields = <int, dynamic>{
      for (var i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SubTask(
      uid: fields[0] as String?,
      title: fields[1] as String? ?? '',
      done: fields[2] as bool? ?? false,
      description: fields[3] as String? ?? '',
      endTime: fields[4] as DateTime?,
      priority: fields[5] as TaskPriority? ?? TaskPriority.normal,
      tags:
          (fields[6] as List?)?.map((e) => e as String).toList() ?? <String>[],
      attachments:
          (fields[7] as List?)?.map((e) => e as TaskAttachment).toList() ??
              <TaskAttachment>[],
      location: fields[8] as String? ?? '',
      // 老数据没有这两项 → null，就是「清单型」步骤，行为不变
      startTime: fields[9] as DateTime?,
      reminderMinutes: fields[10] as int?,
    );
  }
}

class TaskAttachmentAdapter extends TypeAdapter<TaskAttachment> {
  @override
  final typeId = 15;

  @override
  void write(BinaryWriter writer, TaskAttachment obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.name)
      ..writeByte(1)
      ..write(obj.path)
      ..writeByte(2)
      ..write(obj.size);
  }

  @override
  TaskAttachment read(BinaryReader reader) {
    var numOfFields = reader.readByte();
    var fields = <int, dynamic>{
      for (var i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return TaskAttachment(
      name: fields[0] as String? ?? '',
      path: fields[1] as String? ?? '',
      size: fields[2] as int? ?? 0,
    );
  }
}

class TaskCommentAdapter extends TypeAdapter<TaskComment> {
  @override
  final typeId = 16;

  @override
  void write(BinaryWriter writer, TaskComment obj) {
    writer
      ..writeByte(2)
      ..writeByte(0)
      ..write(obj.content)
      ..writeByte(1)
      ..write(obj.time);
  }

  @override
  TaskComment read(BinaryReader reader) {
    var numOfFields = reader.readByte();
    var fields = <int, dynamic>{
      for (var i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return TaskComment(
      content: fields[0] as String? ?? '',
      time: fields[1] as DateTime? ?? DateTime.now(),
    );
  }
}

class DeadlineAdapter extends TypeAdapter<Task> {
  @override
  final typeId = 6;

  @override
  void write(BinaryWriter writer, Task obj) {
    writer
      ..writeByte(23) // P5：不再写 4 / 8 / 14 三个废弃序号
      ..writeByte(0)
      ..write(obj.uid)
      ..writeByte(1)
      ..write(obj.status)
      ..writeByte(2)
      ..write(obj.description)
      ..writeByte(3)
      ..write(obj.timeSpent)
      ..writeByte(5)
      ..write(obj.endTime)
      ..writeByte(6)
      ..write(obj.location)
      ..writeByte(7)
      ..write(obj.summary)
      ..writeByte(9)
      ..write(obj.type)
      ..writeByte(10)
      ..write(obj.startTime)
      ..writeByte(11)
      ..write(obj.repeatType)
      ..writeByte(12)
      ..write(obj.repeatPeriod)
      ..writeByte(13)
      ..write(obj.repeatEndsTime)
      ..writeByte(15)
      ..write(obj.fromUid)
      ..writeByte(16)
      ..write(obj.subtasks)
      ..writeByte(17)
      ..write(obj.priority)
      ..writeByte(18)
      ..write(obj.reminderEnabled)
      ..writeByte(19)
      ..write(obj.reminderTime)
      ..writeByte(20)
      ..write(obj.attachments)
      ..writeByte(21)
      ..write(obj.comments)
      ..writeByte(22)
      ..write(obj.tags)
      ..writeByte(23)
      ..write(obj.starred)
      ..writeByte(24)
      ..write(obj.createdAt)
      ..writeByte(25)
      ..write(obj.updatedAt);
  }

  @override
  Task read(BinaryReader reader) {
    var numOfFields = reader.readByte();
    var fields = <int, dynamic>{
      for (var i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Task(
      endTime: DateTime.now(),
      startTime: DateTime.now(),
      repeatEndsTime: DateTime.now(),
    )
      ..uid = fields[0] as String
      ..status = fields[1] as TaskStatus
      ..description = fields[2] as String
      ..timeSpent = fields[3] as Duration
      ..endTime = fields[5] as DateTime
      ..location = fields[6] as String
      ..summary = fields[7] as String
      ..type = fields[9] as TaskType? ?? TaskType.deadline
      ..startTime = fields[10] as DateTime? ?? (fields[5] as DateTime)
      ..repeatType = fields[11] as TaskRepeatType? ?? TaskRepeatType.norepeat
      ..repeatPeriod = fields[12] as int? ?? 1
      ..repeatEndsTime = fields[13] as DateTime? ?? (fields[5] as DateTime)
      ..fromUid = fields[15] as String?
      ..subtasks = (fields[16] as List?)?.map((e) => e as SubTask).toList() ??
          <SubTask>[]
      ..priority = fields[17] as TaskPriority? ?? TaskPriority.normal
      ..reminderEnabled = fields[18] as bool? ?? false
      ..reminderTime = fields[19] as DateTime?
      ..attachments =
          (fields[20] as List?)?.map((e) => e as TaskAttachment).toList() ??
              <TaskAttachment>[]
      ..comments =
          (fields[21] as List?)?.map((e) => e as TaskComment).toList() ??
              <TaskComment>[]
      ..tags =
          (fields[22] as List?)?.map((e) => e as String).toList() ?? <String>[]
      ..starred = fields[23] as bool? ?? false
      ..createdAt = fields[24] as DateTime?
      ..updatedAt = fields[25] as DateTime?;
  }
}
