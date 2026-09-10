import 'package:celechron/database/database_helper.dart';
import 'package:celechron/mod/ai/deepseek.dart';
import 'package:celechron/mod/database_mod.dart';
import 'package:celechron/mod/tag_harvest.dart';
import 'package:get/get.dart';
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
    required this.startTime,
    required this.reminderMinutes,
    required this.priority,
    required this.tags,
    required this.location,
    required this.subtasks,
    required this.uncertain,
    required this.warnings,
  });

  final String summary;
  final String description;
  final DateTime endTime;

  /// 只有「事件」才有开始时间；交付类待办为 null。
  /// startTime < endTime 会被既有逻辑认成「日程」，正是活动该有的样子。
  final DateTime? startTime;

  /// 提前多少分钟提醒；0 表示不设提醒
  final int reminderMinutes;
  final TaskPriority priority;
  final List<String> tags;
  final String location;
  final List<String> subtasks;

  /// 模型自报「原文里没写、我不确定」的字段名（如 截止时间 / 地点）。
  /// 这些字段会留空交给用户自己补，而不是靠模型猜。
  final List<String> uncertain;

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
    final existingTags = _existingTags();
    final text = rawText.trim();
    if (text.isEmpty) {
      throw AiException('先粘贴一段文字');
    }
    final clipped =
        text.length > maxInputChars ? text.substring(0, maxInputChars) : text;

    final client = DeepSeekClient();
    final json = await client.chatJson(
      system: _buildSystemPrompt(existingTags),
      user: clipped,
      temperature: 0.1,
    );
    return _fromJson(
      json,
      existingTags: existingTags,
      clippedTooLong: text.length > maxInputChars,
    );
  }

  static String _buildSystemPrompt(List<String> existingTags) {
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
  "startTime": "事件开始时间，格式同上；不是事件就留空字符串",
  "reminderMinutes": 提前多少分钟提醒；不提醒给 0
  "priority": "只能是 low / normal / high / urgent 之一",
  "tags": ["最多 $maxTagCount 个，每个不超过 $maxTagChars 字"],
  "location": "地点；原文没提就给空字符串",
  "subtasks": ["仅当原文确实包含多个步骤时才给，最多 $maxSubtaskCount 条；否则给空数组"],
  "uncertain": ["你不确定的字段名，例如 截止时间、地点；没有就给空数组"]
}

用户的标签库（**优先复用**，不要另造近义词）：
${existingTags.isEmpty ? '（现在是空的，可以新建标签）' : existingTags.join('、')}
- 如果上面某个标签能表达这条待办，就**原样使用它**（例如已有「作业」就不要写「作业提交」）
- 总数不超过 $maxTagCount 个；确实没有合适的才新建，且最多新建 2 个

关于「不确定就留空」——这条比填满更重要：
- 原文没提到的地点、标签、子步骤，一律留空字符串或空数组，**不要靠常识补全**
- 不要编造原文没有的要求（原文只说「交报告」，就不要自己加「打印纸质版」这类步骤）
- 把你判断「原文没写清楚」的字段名列进 uncertain 数组，最多 5 个
- 唯一不能留空的是 endTime：完全没提到时间时用今天 23:59，并把「截止时间」列进 uncertain

时间换算的硬规则：
1. 今天日期是 $todayIso。所有相对时间（今天/明天/后天/本周五/下周三/月底/三天后）必须换算成绝对日期。
2. 只给了日期没给时间 → 用那天的 23:59:00。
3. 完全没提时间 → 用 $todayIso 的 23:59:00，并在 description 开头注明「原文未给出时间」。
4. 已经过去的日期不要用；如果原文暗示的是过去，就按最近一次未来的同一天算。
5. 不要编造原文没有的截止时间、地点、标签。信息不足就留空或按上面的默认值。

时段词的换算（**不要漏掉「上午/下午」这类信息**，这是学生最容易搞错的点）：
- 上午 / 早上 → 09:00；中午 → 12:00；下午 → 14:30
- 傍晚 → 18:00；晚上 → 19:30；凌晨 → 06:00
- 给了具体时刻（9:30、19:00 等）→ 原样用
- 只给了日期、连时段都没说 → 23:59，并在 description 里注明「原文未给出具体时间」

区分「事件」和「截止」——决定要不要给 startTime：
- **事件**（典礼、会议、考试、讲座、要参加的集体活动）：必须给 startTime（用上面换算出的时刻）；
  endTime 给活动结束时间，原文没说就按 startTime + 2 小时
- **交付**（交作业、交报告、报名、缴费、填问卷）：startTime 留空字符串，
  endTime 给截止时刻（只给日期就是当天 23:59）
- 判断不了就按「交付」处理（startTime 留空）

提醒（reminderMinutes = 提前多少分钟）：
- 事件类：给 30（活动前半小时）；全天/半天的大型活动给 60
- 交付类：原文强调「别忘」「记得」「务必」就给 120；不强调就给 0
- 不需要提醒一律给 0''';
  }

  // ---------------------------------------------------- 逐字段校验（重点）

  static AiTaskDraft _fromJson(
    Map<String, dynamic> json, {
    List<String> existingTags = const <String>[],
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

    // --- startTime：只有事件才有；给了但不合理就当没有
    final startTime = _validateStartTime(
      source["startTime"] ?? source["beginTime"],
      endTime,
      warnings,
    );

    // --- 提醒提前量
    final reminderMinutes = _validateReminder(
      source["reminderMinutes"] ??
          source["remindBeforeMinutes"] ??
          source["reminder"],
    );
    if (reminderMinutes > 0) {
      final fireAt =
          (startTime ?? endTime).subtract(Duration(minutes: reminderMinutes));
      if (!fireAt.isAfter(DateTime.now())) {
        warnings.add("按建议的提醒时间（${_fmt(fireAt)}）已经过去了，这条先不设提醒");
      }
    }

    // --- 标签：优先落到用户已有的标签上（大小写/空格归一后精确匹配）
    final mappedTags = _mapTagsToExisting(tags, existingTags, warnings);

    // --- uncertain：模型自报没写清的字段名
    final uncertain = _stringList(source["uncertain"], 5, 10);

    return AiTaskDraft(
      summary: summary,
      description: description,
      endTime: endTime,
      priority: priority,
      tags: mappedTags,
      location: location,
      subtasks: subtasks,
      startTime: startTime,
      reminderMinutes: reminderMinutes,
      uncertain: uncertain,
      warnings: warnings,
    );
  }

  /// 开始时间：只接受能解析、且确实早于结束时间的值；只给日期时按上午 9 点算
  static DateTime? _validateStartTime(
    Object? raw,
    DateTime endTime,
    List<String> warnings,
  ) {
    if (raw is! String || raw.trim().isEmpty) return null;
    final text = raw.trim();
    var parsed = DateTime.tryParse(text) ??
        DateTime.tryParse(text.replaceAll("/", "-").replaceFirst(" ", "T"));
    if (parsed == null) {
      warnings.add("开始时间「$text」读不出来，已按没有开始时间处理");
      return null;
    }
    if (parsed.hour == 0 && parsed.minute == 0 && parsed.second == 0) {
      parsed = DateTime(parsed.year, parsed.month, parsed.day, 9, 0);
    }
    if (!parsed.isBefore(endTime)) {
      warnings.add("开始时间不早于结束时间，已忽略开始时间");
      return null;
    }
    if (endTime.difference(parsed).inDays > 30) {
      warnings.add("开始与结束相隔超过 30 天，已忽略开始时间");
      return null;
    }
    return parsed;
  }

  /// 提醒提前量：非正数 = 不提醒；超过一周就压到一天
  static int _validateReminder(Object? raw) {
    int minutes = 0;
    if (raw is int) {
      minutes = raw;
    } else if (raw is num) {
      minutes = raw.toInt();
    } else if (raw is String) {
      minutes = int.tryParse(raw.trim()) ?? 0;
    } else if (raw is bool) {
      minutes = raw ? 30 : 0;
    }
    if (minutes <= 0) return 0;
    if (minutes > 7 * 24 * 60) return 24 * 60;
    return minutes;
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
  /// 用户标签库（拿不到就当空）
  static List<String> _existingTags() {
    try {
      if (!Get.isRegistered<DatabaseHelper>(tag: "db")) return const <String>[];
      return Get.find<DatabaseHelper>(tag: "db").getTagLibrary();
    } catch (_) {
      return const <String>[];
    }
  }

  /// 去掉大小写与所有空白，只用于「是不是同一个标签」的判断
  static String _normalizeTag(String tag) =>
      tag.replaceAll(RegExp(r"\s+"), "").toLowerCase();

  /// 把模型给的标签尽量落到用户已有的标签上：
  /// 归一化后完全一样 → 换成用户那边原本的写法（避免「作业」和「作业 」两个标签）。
  /// 只做精确匹配，不做模糊合并——「报告」和「实验报告」是两回事，不替用户决定。
  static List<String> _mapTagsToExisting(
    List<String> tags,
    List<String> existing,
    List<String> warnings,
  ) {
    if (tags.isEmpty || existing.isEmpty) return tags;
    final byNormalized = <String, String>{
      for (final tag in existing) _normalizeTag(tag): tag,
    };
    final result = <String>[];
    for (final tag in tags) {
      final matched = byNormalized[_normalizeTag(tag)];
      final finalTag = matched ?? tag;
      if (matched != null && matched != tag) {
        warnings.add("标签「$tag」并入了你已有的「$matched」");
      }
      if (!result.contains(finalTag)) result.add(finalTag);
    }
    return result;
  }

  void applyTo(Task task) {
    task.summary = summary;
    if (description.isNotEmpty) task.description = description;
    task.endTime = endTime;
    // 事件带开始时间（startTime < endTime 会在保存时被认成「日程」）
    task.startTime = startTime ?? endTime;
    task.repeatEndsTime = dateOnly(endTime);
    task.priority = priority;
    if (tags.isNotEmpty) {
      task.tags = <String>[...tags];
      // 记住 AI 用过的标签，下次它就能复用这些写法（也让标签库不再是空的）
      TagHarvest.remember(tags);
    }
    if (location.isNotEmpty) task.location = location;
    if (subtasks.isNotEmpty) {
      task.subtasks = <SubTask>[
        for (final title in subtasks) SubTask(title: title),
      ];
    }
    // 提醒：算出来的时刻必须还在未来，否则宁可不设
    if (reminderMinutes > 0) {
      final fireAt =
          (startTime ?? endTime).subtract(Duration(minutes: reminderMinutes));
      if (fireAt.isAfter(DateTime.now())) {
        task.reminderEnabled = true;
        task.reminderTime = fireAt;
      }
    }
    task.updatedAt = DateTime.now();
  }

  static String _fmt(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}';
  }
}
