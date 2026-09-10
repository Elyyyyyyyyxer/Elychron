import 'package:celechron/mod/ai/deepseek.dart';
import 'package:celechron/model/task.dart';
import 'package:celechron/utils/utils.dart';

/// ============ AI 生成待办草稿 ============
///
/// **核心安全原则：绝不让 AI 直接产出 Task JSON。**
///
/// 模型只输出一份**受限草稿**（下面这几个字段），然后由这里的 Dart 代码
/// 逐字段校验、越界就换成安全值并记一条提醒，最后由 `applyTo()` 去构造真正的
/// Task——所有枚举、时间、集合都由我们自己拼，模型再胡说也污染不了数据结构。
class AiTaskDraft {
  AiTaskDraft({
    required this.summary,
    required this.description,
    required this.endTime,
    required this.priority,
    required this.tags,
    required this.location,
    required this.subtasks,
    required this.warnings,
  });

  final String summary;
  final String description;
  final DateTime endTime;
  final TaskPriority priority;
  final List<String> tags;
  final String location;
  final List<String> subtasks;

  /// 我们改动过模型输出的地方（比如时间在过去、优先级不认识），
  /// 如实告诉用户，不做静默修补。
  final List<String> warnings;

  // ------------------------------------------------------------ 约束上限

  static const int maxInputChars = 4000;
  static const int maxSummaryChars = 60;
  static const int maxDescriptionChars = 2000;
  static const int maxTagCount = 3;
  static const int maxTagChars = 12;
  static const int maxLocationChars = 60;
  static const int maxSubtaskCount = 5;
  static const int maxSubtaskChars = 60;

  /// 让模型把一段文字整理成草稿。文本过长会被截断，避免烧钱又跑偏。
  static Future<AiTaskDraft> fromText(String rawText) async {
    await AiConfig.load();
    final text = rawText.trim();
    if (text.isEmpty) {
      throw AiException('先粘贴一段文字');
    }
    final clipped =
        text.length > maxInputChars ? text.substring(0, maxInputChars) : text;

    final client = DeepSeekClient();
    final json = await client.chatJson(
      system: _buildSystemPrompt(),
      user: clipped,
      temperature: 0.1,
    );
    return _fromJson(json, clippedTooLong: text.length > maxInputChars);
  }

  static String _buildSystemPrompt() {
    final now = DateTime.now();
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    final weekday = weekdays[now.weekday - 1];
    String two(int value) => value.toString().padLeft(2, '0');
    final today = '${now.year} 年 ${now.month} 月 ${now.day} 日'
        '（星期$weekday），现在时刻 ${two(now.hour)}:${two(now.minute)}';
    final todayIso = '${now.year}-${two(now.month)}-${two(now.day)}';

    return '''
你是帮浙大学生把通知、聊天记录、邮件整理成待办的助手。

当前时间：$today。默认时区 +08:00。

只输出一个 json 对象，不要输出任何解释文字、不要用 markdown 代码块。字段与取值规则如下：

{
  "summary": "一句话动作短语，不超过 $maxSummaryChars 字，不要出现「待办」「任务」这类词",
  "description": "原文里对完成这件事有用的补充信息（材料、要求、链接等）；没有就给空字符串，不要编造",
  "endTime": "截止时间，格式必须是 YYYY-MM-DDTHH:mm:ss",
  "priority": "只能是 low / normal / high / urgent 之一",
  "tags": ["最多 $maxTagCount 个，每个不超过 $maxTagChars 字"],
  "location": "地点；原文没提就给空字符串",
  "subtasks": ["仅当原文确实包含多个步骤时才给，最多 $maxSubtaskCount 条；否则给空数组"]
}

时间换算的硬规则：
1. 今天日期是 $todayIso。所有相对时间（今天/明天/后天/本周五/下周三/月底/三天后）必须换算成绝对日期。
2. 只给了日期没给时间 → 用那天的 23:59:00。
3. 完全没提时间 → 用 $todayIso 的 23:59:00，并在 description 开头注明「原文未给出时间」。
4. 已经过去的日期不要用；如果原文暗示的是过去，就按最近一次未来的同一天算。
5. 不要编造原文没有的截止时间、地点、标签。信息不足就留空或按上面的默认值。''';
  }

  // ---------------------------------------------------- 逐字段校验（重点）

  static AiTaskDraft _fromJson(
    Map<String, dynamic> json, {
    bool clippedTooLong = false,
  }) {
    final warnings = <String>[];
    if (clippedTooLong) {
      warnings.add('原文太长，只取了前 $maxInputChars 字');
    }

    // 有的模型会好心多包一层，比如 {"task": {...}}
    var source = json;
    for (final key in ['task', 'data', 'result', 'todo', 'draft']) {
      final nested = json[key];
      if (nested is Map && !json.containsKey('summary')) {
        source = Map<String, dynamic>.from(nested);
        break;
      }
    }

    // --- summary：必须有，空的话整条草稿没意义
    var summary = _cleanString(source['summary'], maxSummaryChars);
    if (summary.isEmpty) {
      summary = _cleanString(source['title'], maxSummaryChars);
    }
    if (summary.isEmpty) {
      throw AiException('模型没给出标题，换一段更清楚的话再试');
    }

    // --- description
    final description =
        _cleanString(source['description'], maxDescriptionChars);

    // --- location
    final location = _cleanString(source['location'], maxLocationChars);

    // --- priority：白名单之外一律 normal
    final rawPriority = _cleanString(source['priority'], 20).toLowerCase();
    var priority = TaskPriority.normal;
    final matched = TaskPriority.values.where((p) => p.name == rawPriority);
    if (matched.isNotEmpty) {
      priority = matched.first;
    } else if (rawPriority.isNotEmpty) {
      warnings.add('优先级「$rawPriority」不认识，按普通处理');
    }

    // --- tags：去空、去重、限长限量
    final tags = _stringList(source['tags'], maxTagCount, maxTagChars);
    // --- subtasks：同上
    final subtasks =
        _stringList(source['subtasks'], maxSubtaskCount, maxSubtaskChars);

    // --- endTime：最需要把关的字段
    final endTime = _validateEndTime(
      source['endTime'] ?? source['deadline'] ?? source['due'],
      warnings,
    );

    return AiTaskDraft(
      summary: summary,
      description: description,
      endTime: endTime,
      priority: priority,
      tags: tags,
      location: location,
      subtasks: subtasks,
      warnings: warnings,
    );
  }

  static DateTime _validateEndTime(Object? raw, List<String> warnings) {
    final now = DateTime.now();
    final todayEnd = DateTime(now.year, now.month, now.day, 23, 59);

    DateTime? parsed;
    if (raw is String) {
      parsed = DateTime.tryParse(raw.trim());
      if (parsed == null) {
        // 容忍 "2026-09-15 23:59" / "2026/09/15 23:59" 这类写法
        final cleaned = raw.trim().replaceAll('/', '-').replaceFirst(' ', 'T');
        parsed = DateTime.tryParse(cleaned);
      }
    } else if (raw is int) {
      // 有些模型会直接给毫秒时间戳
      final asDate = DateTime.fromMillisecondsSinceEpoch(raw);
      if (asDate.year >= 2000 && asDate.year <= 2100) parsed = asDate;
    }

    if (parsed == null) {
      warnings.add('模型没给出可用时间，已设为今天 23:59');
      return todayEnd;
    }

    // 只给了日期（时分秒都是 0）→ 补成当天 23:59
    if (parsed.hour == 0 && parsed.minute == 0 && parsed.second == 0) {
      parsed = DateTime(parsed.year, parsed.month, parsed.day, 23, 59);
    }

    final todayStart = DateTime(now.year, now.month, now.day);
    if (parsed.isBefore(todayStart)) {
      warnings.add('模型给出的时间（${_fmt(parsed)}）已经过去了，已改为今天 23:59');
      return todayEnd;
    }
    if (parsed.year > now.year + 5) {
      warnings.add('模型给出的时间（${_fmt(parsed)}）太远，已改为今天 23:59');
      return todayEnd;
    }
    return parsed;
  }

  static String _cleanString(Object? raw, int maxChars) {
    if (raw is! String) return '';
    // 去掉换行与多余空白，避免把多行文本塞进单行字段
    var text = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    // 去掉模型偶尔带上的 markdown 包裹
    text = text.replaceAll(RegExp(r'^[`"\s]+|[`"\s]+$'), '');
    if (text.length > maxChars) text = text.substring(0, maxChars);
    return text;
  }

  static List<String> _stringList(Object? raw, int maxCount, int maxChars) {
    if (raw is! List) return <String>[];
    final result = <String>[];
    for (final item in raw) {
      final text = _cleanString(item, maxChars);
      if (text.isEmpty) continue;
      if (result.contains(text)) continue;
      result.add(text);
      if (result.length >= maxCount) break;
    }
    return result;
  }

  /// 把草稿应用到一条待办上（新建页的临时对象）。
  ///
  /// 只写我们自己认可的字段：`type` 保持普通待办、`startTime` 与 `endTime` 对齐
  /// （与「普通待办不该有开始时间」的既有约定一致），其余一律走模型默认值。
  void applyTo(Task task) {
    task.summary = summary;
    if (description.isNotEmpty) task.description = description;
    task.endTime = endTime;
    task.startTime = endTime;
    task.repeatEndsTime = dateOnly(endTime);
    task.priority = priority;
    if (tags.isNotEmpty) {
      task.tags = <String>[...tags];
    }
    if (location.isNotEmpty) task.location = location;
    if (subtasks.isNotEmpty) {
      task.subtasks = <SubTask>[
        for (final title in subtasks) SubTask(title: title),
      ];
    }
    task.updatedAt = DateTime.now();
  }

  static String _fmt(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}';
  }
}
