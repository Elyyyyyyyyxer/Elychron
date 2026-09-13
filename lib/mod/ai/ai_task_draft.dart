import 'package:celechron/database/database_helper.dart';
import 'package:celechron/mod/ai/ai_image.dart';
import 'package:celechron/mod/ai/deepseek.dart';
import 'package:celechron/mod/ai/model_resolver.dart';
import 'package:celechron/mod/database_mod.dart';
import 'package:get/get.dart';
import 'package:celechron/model/task.dart';
import 'package:celechron/utils/utils.dart';

/// ===== P2：AI 拆出来的一步 =====
///
/// 可能是「有时有地点的一步」（团建：14:30-17:30 嗦歌KTV），
/// 也可能只是「一句话的步骤」（写论文：查文献）。时间/地点都可以为空。
class AiStepDraft {
  final String title;

  /// 这一步的注意事项（地图到 `SubTask.description`）
  final String note;

  final String location;
  final DateTime? startTime;
  final DateTime? endTime;

  const AiStepDraft({
    required this.title,
    this.note = '',
    this.location = '',
    this.startTime,
    this.endTime,
  });

  bool get hasTime => startTime != null || endTime != null;

  /// 排序与显示用的「那一刻」
  DateTime? get anchor => startTime ?? endTime;

  /// 详情页时间轴上那一行：`14:30-17:30` 或 `14:20`
  String get timeLabel {
    String hm(DateTime t) =>
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final s = startTime;
    final e = endTime;
    if (s != null && e != null && s.isBefore(e)) return '${hm(s)}-${hm(e)}';
    final one = anchor;
    return one == null ? '' : hm(one);
  }

  /// 填进任务时用（带时间/地点/注意事项）
  SubTask toSubTask() => SubTask(
        title: title,
        description: note,
        location: location,
        startTime: startTime,
        endTime: endTime,
      );

  /// 去掉时间，只留标题（预览里「全部不要时间」用）
  AiStepDraft withoutTime() => AiStepDraft(
        title: title,
        note: note,
        location: location,
      );
}

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
    required this.kind,
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

  /// 只有「活动」才有开始时间；截止 / 提醒 / 备忘为 null。
  final DateTime? startTime;

  /// ===== P1：模型划分出的时间语义（活动 / 截止 / 提醒 / 备忘）=====
  ///
  /// 不是 `fixedlegacy`（内部值，模型不许碰），且经过 `_validateKind` 白名单
  /// 与一致性校验，绝不让模型直接决定枚举值。
  final TaskType kind;

  /// 提前多少分钟提醒；0 表示用应用里的默认提前量（提醒型就是那一刻）
  final int reminderMinutes;
  final TaskPriority priority;
  final List<String> tags;
  final String location;

  /// ===== P2：结构化的子步骤（可能带时间/地点）=====
  ///
  /// 预览里可以删单条 / 改时间，靠 [copyWith] 换一份新的，不改原对象。
  final List<AiStepDraft> subtasks;


  /// 模型自报「原文里没写、我不确定」的字段名（如 截止时间 / 地点）。
  /// 这些字段会留空交给用户自己补，而不是靠模型猜。
  final List<String> uncertain;

  /// 我们改动过模型输出的地方（比如时间在过去、优先级不认识），
  /// 如实告诉用户，不做静默修补。
  final List<String> warnings;

  // ------------------------------------------------------------ 约束上限

  static const int maxInputChars = 4000;

  /// 一次最多识别几张图（多张会显著变贵，也没必要）
  static const int maxImages = 3;
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

    // 模型名可能被官方改过：还没有解析结果就先问一次 /models
    // （拿不到也不阻断，继续用兜底名；失败时由 withModelHealing 自愈重试）
    if (AiConfig.resolvedModel.isEmpty && !AiConfig.isManualModel) {
      await ModelResolver.resolve();
    }

    final json = await ModelResolver.withModelHealing(
      () => DeepSeekClient().chatJson(
        system: _buildSystemPrompt(existingTags),
        user: clipped,
        temperature: 0.1,
      ),
    );
    return _fromJson(
      json,
      existingTags: existingTags,
      clippedTooLong: text.length > maxInputChars,
    );
  }

  /// 图片输入时额外加的一段规则（文字输入时不出现，避免把模型绕晕）
  static const String _imageRules = '''
这次给你的是图片（可能是教务通知、群消息、海报或课表截图）：
- 先读出图中文字，再按下面的规则整理成待办
- 图里看不清、或没写清的字段，一律留空并写进 uncertain，绝不靠猜补齐
- 图里有多个通知时，只取最主要的那一条
- 如果整张图跟「要做的事」无关（比如只是风景照、表情包），summary 给空字符串
''';

  static String _buildSystemPrompt(List<String> existingTags,
      {bool fromImage = false}) {
    final now = DateTime.now();
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    final weekday = weekdays[now.weekday - 1];
    String two(int value) => value.toString().padLeft(2, '0');
    final today = '${now.year} 年 ${now.month} 月 ${now.day} 日'
        '（星期$weekday），现在时刻 ${two(now.hour)}:${two(now.minute)}';
    final todayIso = '${now.year}-${two(now.month)}-${two(now.day)}';

    return '''
${fromImage ? _imageRules : ''}
你是帮浙大学生把通知、聊天记录、邮件整理成待办的助手。

当前时间：$today。默认时区 +08:00。

只输出一个 json 对象，不要输出任何解释文字、不要用 markdown 代码块。字段与取值规则如下：

{
  "summary": "一句话动作短语，不超过 $maxSummaryChars 字，不要出现「待办」「任务」这类词",
  "kind": "活动 / 截止 / 提醒 / 备忘 之一，规则见下面",
  "description": "原文里对完成这件事有用的补充信息（说明、要求、链接等）；**要带的东西、着装、材料这类可打钩的清单不要写在这里**，放到 subtasks；没有就给空字符串，不要编造",
  "endTime": "截止时间，格式必须是 YYYY-MM-DDTHH:mm:ss",
  "startTime": "事件开始时间，格式同上；不是事件就留空字符串",
  "reminderMinutes": 提前多少分钟提醒；用默认值就给 0
  "priority": "只能是 low / normal / high / urgent 之一",
  "tags": ["最多 $maxTagCount 个，每个不超过 $maxTagChars 字"],
  "location": "地点；原文没提就给空字符串",
  "subtasks": ["原文里的执行步骤，**以及要带的东西 / 着装 / 材料这类可打钩的清单**，最多 $maxSubtaskCount 条；都没有才给空数组。格式见下"],
  "uncertain": ["你不确定的字段名，例如 截止时间、地点；没有就给空数组"]
}

$_stepSchemaRules

关于「清单类子待办」——学生最需要这一条（原文写「着装：白色院衫、带校徽、带雨伞」时，别把它挤进 description）：
- **着装**（穿什么、戴什么）、**要带的东西**（雨衣、纸巾、校徽、笔记本）、**要准备的材料**
  一律拆成一条条 subtasks，一条一个物件或一件事，方便到场前逐条打钩
- 标题写具体的东西或动作：写「带雨伞」「穿白色院衫」「带校徽」，不要写「准备物品」「按要求着装」这种笼统标题
- 这类条目**没有时间**：startTime / endTime 都留空字符串；不要为了凑格式编造时刻
- 只从原文提取，**不要自行补充**原文没写的物品（原文没提伞就不要加伞）
- 如果这件事既有行程步骤又有清单（例如「17:45 集合，着装：白院衫，带雨伞」），
  两类都放进来：行程步骤带时间，清单条目不带时间

用户的标签库（**优先复用**，不要另造近义词）：
${existingTags.isEmpty ? '（现在是空的，可以新建标签）' : existingTags.join('、')}
- 如果上面某个标签能表达这条待办，就**原样使用它**（例如已有「作业」就不要写「作业提交」）
- 总数不超过 $maxTagCount 个；确实没有合适的才新建，且最多新建 2 个

关于「不确定就留空」——这条比填满更重要：
- 原文没提到的地点、标签、子步骤，一律留空字符串或空数组，**不要靠常识补全**
- 不要编造原文没有的要求（原文只说「交报告」，就不要自己加「打印纸质版」这类步骤）
- 把你判断「原文没写清楚」的字段名列进 uncertain 数组，最多 5 个
- 唯一不能留空的是 endTime：完全没提到时间时用今天 23:59，并把「截止时间」列进 uncertain

${AiConfig.autoSubtasks ? '' : '注意：用户已关闭「自动生成子待办」，subtasks 一律给空数组。'}

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

区分「活动 / 截止 / 提醒 / 备忘」——这是**必给**字段，它决定这条待办怎么显示、怎么提醒：
- **活动**：有明确起止时段、要去参加的事（典礼、会议、考试、讲座、团建、面试）。
  必须给 startTime；endTime 给结束时刻，原文没说就按 startTime + 2 小时
- **截止**：有「什么时候之前要交/做完」但本身不占时段（交作业、交报告、报名、缴费、填问卷）。
  startTime 留空字符串，endTime 给截止时刻（只给日期就是当天 23:59）
- **提醒**：单个时刻要做的一件小事、没有时长（「9 点去取快递」「下午 3 点打个电话」）。
  startTime 留空字符串，endTime 给那一刻
- **备忘**：只是记一条信息、原文根本没提时间（「记得买牙膏」「问一下老师教材」）。
  startTime 与 endTime 都给空字符串，reminderMinutes 给 0

判断顺序：先看有没有明确起止时段 → 活动；再看到底是「期限」还是「某个时刻要做的小事」
→ 截止 / 提醒；都没有时间 → 备忘。拿不准就按「截止」。

reminderMinutes（提前多少分钟提醒）：
- 活动：给 30（活动前半小时）；全天/半天的大型活动给 60
- 截止：原文强调「别忘」「记得」「务必」就给 120；不强调就给 0（0 = 用应用里的默认提前量）
- 提醒：给 0（就在那一刻响）
- 备忘：给 0（备忘从不提醒）''';
  }

  /// 从图片（截图）整理草稿。
  ///
  /// 走的是官方 vision 接口（content parts + image_url 的 base64 data URI），
  /// 图片原样发送、不压缩——截图里的小字能不能读对，取决于分辨率。
  static Future<AiTaskDraft> fromImages(
    List<String> imagePaths, {
    String hint = '',
  }) async {
    await AiConfig.load();
    if (imagePaths.isEmpty) throw AiException('没有可识别的图片');

    final parts = <AiImagePart>[];
    for (final path in imagePaths.take(maxImages)) {
      try {
        parts.add(await AiImage.fromFile(path));
      } on FormatException catch (error) {
        throw AiException(error.message);
      }
    }
    if (parts.isEmpty) throw AiException('图片读不出来');

    if (AiConfig.resolvedModel.isEmpty && !AiConfig.isManualModel) {
      await ModelResolver.resolve();
    }

    final trimmed = hint.trim();
    final user = trimmed.isEmpty
        ? '请读出这张图里的内容，整理成一条待办。'
        : '请读出这张图里的内容，整理成一条待办。'
            '图之外还有这段文字可以参考（可能不完整，以图为准）：\n$trimmed';

    final existingTags = _existingTags();
    final json = await ModelResolver.withModelHealing(
      () => DeepSeekClient().chatJson(
        system: _buildSystemPrompt(existingTags, fromImage: true),
        user: user,
        images: parts,
        temperature: 0.1,
      ),
    );
    return _fromJson(json, existingTags: existingTags, fromImage: true);
  }

  // ------------------------------------------------ AI 拆子待办（单项功能）

  /// 把一条待办拆成几条可执行的子待办（P2：可能带时间与地点）。
  static Future<List<AiStepDraft>> subtasksFor(Task task) async {
    await AiConfig.load();
    final summary = task.summary.trim();
    if (summary.isEmpty) {
      throw AiException('这条待办还没有标题，先写上标题再拆');
    }
    if (AiConfig.resolvedModel.isEmpty && !AiConfig.isManualModel) {
      await ModelResolver.resolve();
    }

    final existing = task.subtasks
        .map((subtask) => subtask.title.trim())
        .where((title) => title.isNotEmpty)
        .toList();
    final buffer = StringBuffer()..writeln('待办标题：$summary');
    if (task.description.trim().isNotEmpty) {
      buffer.writeln('补充说明：${task.description.trim()}');
    }
    if (task.location.trim().isNotEmpty) {
      buffer.writeln('地点：${task.location.trim()}');
    }
    if (task.isEvent) {
      buffer.writeln('开始时间：${_fmt(task.startTime)}');
    }
    buffer.writeln('截止时间：${_fmt(task.endTime)}');
    if (existing.isNotEmpty) {
      buffer.writeln('已有的子待办（不要重复）：${existing.join('、')}');
    }

    final json = await ModelResolver.withModelHealing(
      () => DeepSeekClient().chatJson(
        system: _subtaskSystemPrompt(task),
        user: buffer.toString(),
        temperature: 0.3,
      ),
    );
    final warnings = <String>[];
    return _parseSubtasks(
      json,
      existing,
      parentStart: task.isEvent ? task.startTime : null,
      parentEnd: task.endTime,
      warnings: warnings,
    );
  }

  static String _subtaskSystemPrompt(Task task) => '''
你是帮学生把一件待办拆成可执行小步骤的助手。

只输出一个 json 对象，不要解释、不要 markdown 代码块。格式：
{"subtasks": [
  {"title": "步骤一"},
  {"title": "步骤二", "location": "三教 403", "startTime": "2026-09-11T14:30:00", "endTime": "2026-09-11T17:30:00"}
]}

$_stepSchemaRules

${task.isEvent ? '''
这条待办是一段**有起止时间的活动**（${_fmt(task.startTime)} 到 ${_fmt(task.endTime)}）。
如果输入里给了每一步的时间安排，**必须**把每步的 startTime / endTime 带出来，
而且必须落在这段时间**之内**；落在范围外的时间会被丢掉。
''' : '''
这条待办是**交付型/单时刻**的，一般没有分步时间：
没有明确时间就只给 title，**不要编造时间**。
'''}

规则：
- 3~6 条，按执行顺序排列；每条不超过 30 字，尽量以动词开头
- 每条都要是能直接动手做的事（写、查、问、交、打印、预约…），
  不要写「认真准备」「努力完成」这类空话
- **要带的东西 / 着装 / 材料也算步骤**：原文写了「着装：白院衫，带雨伞」就拆成
  「穿白色院衫」「带雨伞」两条，**不带时间**；标题写具体物件，
  不要写「准备物品」这种笼统说法
- 不要重复输入里已经列出的子待办
- 如果这件事本身没法拆（比如「给妈妈打电话」），返回 {"subtasks": []}
- 不要编造输入里没有的人名、地点、材料''';

  /// 子待办（步骤）的 JSON 约定 —— 上面两个提示词共用同一套。
  static const String _stepSchemaRules = '''
每个步骤是一个对象：
- "title"：这一步做什么，不超过 30 字，动词开头
- "location"：这一步的地点；原文没提就给空字符串
- "note"：这一步的注意事项；没有就给空字符串
- "startTime" / "endTime"：这一步的开始/结束时刻，格式 YYYY-MM-DDTHH:mm:ss；
  没给时间就留空字符串。**时间要写在这里，不要写进 title**

两种步骤都要会用：

1. **行程型**（原文给了整段行程：几点集合、几点到哪吃饭）——把每步的时间放进
   startTime/endTime、地点放进 location，标题只写做什么。
2. **清单型**（要带的东西 / 着装 / 材料，原文常写成「着装：…」「需携带：…」
   「请带好…」）——一条一个物件或一件事，**时间一律留空**，标题直接写
   「带雨伞」「穿白色院衫」「带校徽」这类能打钩的内容。
   不要写成「准备物品」「按要求着装」这种笼统标题，也不要编造时刻。''';

  /// 校验模型返回的子待办（白名单式：限量、限长、去重、剔除已有、时间越界即丢）
  static List<AiStepDraft> _parseSubtasks(
    Map<String, dynamic> json,
    List<String> existing, {
    DateTime? parentStart,
    DateTime? parentEnd,
    List<String>? warnings,
  }) {
    final raw = json['subtasks'] ?? json['steps'] ?? json['tasks'];
    if (raw is! List) return <AiStepDraft>[];

    final known = existing.map((title) => title.trim()).toSet();
    final steps = <AiStepDraft>[];
    final seen = <String>{};

    for (final item in raw) {
      // 兼容老格式（模型偶尔还是只给字符串）：那就当成没时间的步骤
      final Map<String, dynamic> source;
      if (item is String) {
        source = <String, dynamic>{'title': item};
      } else if (item is Map) {
        source = Map<String, dynamic>.from(item);
      } else {
        continue;
      }

      var title = _cleanString(source['title'] ?? source['summary'], 40);
      if (title.isEmpty) continue;

      // 模型有时会把时间写进标题（「14:30-17:30 嗦歌KTV」）。与其一删了之，
      // 不如把这段时间**抢救到时间字段里** —— 那正是用户想看的信息。
      final day = parentStart ?? parentEnd;
      DateTime? titleStart;
      DateTime? titleEnd;
      final spanMatch = RegExp(
              r'^([0-9]{1,2})[:：]([0-9]{2})\s*[-~－—到至]\s*([0-9]{1,2})[:：]([0-9]{2})\s*')
          .firstMatch(title);
      final momentMatch =
          RegExp(r'^([0-9]{1,2})[:：]([0-9]{2})\s+').firstMatch(title);
      if (spanMatch != null && day != null) {
        titleStart = DateTime(day.year, day.month, day.day,
            int.parse(spanMatch[1]!), int.parse(spanMatch[2]!));
        titleEnd = DateTime(day.year, day.month, day.day,
            int.parse(spanMatch[3]!), int.parse(spanMatch[4]!));
        title = title.substring(spanMatch.end).trim();
      } else if (momentMatch != null && day != null) {
        titleStart = DateTime(day.year, day.month, day.day,
            int.parse(momentMatch[1]!), int.parse(momentMatch[2]!));
        title = title.substring(momentMatch.end).trim();
      }
      if (title.isEmpty) continue;
      if (known.contains(title) || seen.contains(title)) continue;
      if (titleStart != null) {
        warnings?.add('第 ${steps.length + 1} 步的时间原本写在标题里，已挪到时间字段');
      }

      var start =
          _parseStepTime(source['startTime'] ?? source['beginTime']) ?? titleStart;
      var end = _parseStepTime(source['endTime']) ?? titleEnd;

      if (start != null && end != null && !start.isBefore(end)) {
        warnings?.add('第 ${steps.length + 1} 步「$title」的结束时间不晚于开始时间，这一步的时间已丢掉');
        start = null;
        end = null;
      }
      // 步骤时间必须落在父任务的时间范围内（团建的步骤不该跑到第二天）
      if (parentEnd != null) {
        if (start != null && start.isAfter(parentEnd)) {
          warnings?.add('第 ${steps.length + 1} 步「$title」的时间超出了这条待办的范围，已丢掉');
          start = null;
          end = null;
        } else if (end != null && end.isAfter(parentEnd)) {
          warnings?.add('第 ${steps.length + 1} 步「$title」的结束时间超出了这条待办的范围，已丢掉结束时间');
          end = null;
        }
      }
      // 只给结束时间、没给开始时间 → 就用结束时间当那一刻
      if (start == null && end != null && parentStart == null) {
        // 交付型：结束时间就是这一步的截止
      }

      seen.add(title);
      steps.add(AiStepDraft(
        title: title,
        note: _cleanString(source['note'] ?? source['description'], 60),
        location: _cleanString(source['location'], 40),
        startTime: start,
        endTime: end,
      ));
      if (steps.length >= maxSubtaskCount) break;
    }

    // 按时间排序，没时间的排最后（保持模型给的先后顺序）
    final timed = steps.where((s) => s.anchor != null).toList()
      ..sort((a, b) => a.anchor!.compareTo(b.anchor!));
    final timeless = steps.where((s) => s.anchor == null).toList();
    return <AiStepDraft>[...timed, ...timeless];
  }

  static DateTime? _parseStepTime(Object? raw) {
    if (raw is! String || raw.trim().isEmpty) return null;
    final text = raw.trim();
    final parsed = DateTime.tryParse(text) ??
        DateTime.tryParse(text.replaceAll('/', '-').replaceFirst(' ', 'T'));
    return parsed;
  }

  // ---------------------------------------------------- 逐字段校验（重点）

  /// **只给测试用**：直接拿一个「模型返回的 JSON 对象」走完整套校验。
  ///
  /// 走的和线上是同一个 `_fromJson`，所以钉住的就是真实行为
  /// （尤其是 P1 的时间语义划分与一致性校验）。
  static AiTaskDraft fromJsonForTest(Map<String, dynamic> json) =>
      _fromJson(json);

  static AiTaskDraft _fromJson(
    Map<String, dynamic> json, {
    List<String> existingTags = const <String>[],
    bool clippedTooLong = false,
    bool fromImage = false,
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
      // 图里 / 文字里没有可做成的待办时不要直接报错：留空让用户自己补，
      // 已经读出来的时间、地点等字段仍然有用。这是"用户反馈感"的关键一步。
      warnings.add(fromImage
          ? '这张图里没读出明确要做的事，标题先留空了，你可以自己补上'
          : '这段文字里没读出明确要做的事，标题先留空了，你可以自己补上');
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

    // ===== P1：先定时间语义，它决定后面几个字段怎么校验 =====
    var kind = _validateKind(
      source['kind'] ?? source['type'] ?? source['semantic'],
      warnings,
    );

    // --- endTime：最需要把关的字段
    final DateTime endTime;
    if (kind == TaskType.memo && _cleanString(source['endTime'], 40).isEmpty) {
      // 备忘本来就没有时间：内部给个占位值，不打扰用户（界面上不显示）
      endTime = _todayEnd();
    } else {
      endTime = _validateEndTime(
        source['endTime'] ?? source['deadline'] ?? source['due'],
        warnings,
      );
    }

    // --- startTime：只有活动才有；给了但不合理就当没有
    var startTime = _validateStartTime(
      source["startTime"] ?? source["beginTime"],
      endTime,
      warnings,
    );

    // --- 模型没给类型：按有没有开始时间来推断（老行为）
    kind ??= startTime != null ? TaskType.fixed : TaskType.deadline;

    // --- 语义一致性：以 kind 为准，改动如实记一条，不静默修补
    if (kind == TaskType.fixed) {
      // _validateStartTime 已经把「读不出来 / 不早于结束时间」的开始时间丢掉了，
      // 这里只剩两种情况：有可用的开始时间 → 真活动；没有 → 老老实实降级成截止。
      if (startTime == null) {
        warnings.add('模型说这是「活动」但没给出可用的开始时间，已按「截止」处理');
        kind = TaskType.deadline;
      }
    } else if (startTime != null) {
      warnings.add('「${taskKindName[kind]}」不需要开始时间，已忽略模型给的开始时间');
      startTime = null;
    }

    // --- subtasks：结构化步骤；用户关掉「自动生成子待办」时一律留空
    // 放在时间/类型都定好之后：步骤时间要按父任务的范围校验
    final subtasks = AiConfig.autoSubtasks
        ? _parseSubtasks(
            source,
            const <String>[],
            parentStart: kind == TaskType.fixed ? startTime : null,
            parentEnd: endTime,
            warnings: warnings,
          )
        : <AiStepDraft>[];

    // --- 提醒提前量
    var reminderMinutes = _validateReminder(
      source["reminderMinutes"] ??
          source["remindBeforeMinutes"] ??
          source["reminder"],
    );
    // 提醒型「就在那一刻」，备忘型从不提醒：这两种类型不看模型给的提前量
    if (kind == TaskType.remind || kind == TaskType.memo) {
      reminderMinutes = 0;
    }
    if (reminderMinutes > 0) {
      final anchor = kind == TaskType.fixed ? startTime! : endTime;
      final fireAt = anchor.subtract(Duration(minutes: reminderMinutes));
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
      kind: kind,
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

  // ===== P1：模型划分的时间语义 =====

  /// 模型可能写出来的类型写法（中文 / 英文 / 近义词）。
  ///
  /// 只认白名单，`fixedlegacy` 这种内部值绝不放进来。
  static const Map<String, TaskType> _kindAliases = {
    '活动': TaskType.fixed,
    '日程': TaskType.fixed,
    '事件': TaskType.fixed,
    'fixed': TaskType.fixed,
    'event': TaskType.fixed,
    'activity': TaskType.fixed,
    '截止': TaskType.deadline,
    '任务': TaskType.deadline,
    'ddl': TaskType.deadline,
    'deadline': TaskType.deadline,
    'due': TaskType.deadline,
    '提醒': TaskType.remind,
    'remind': TaskType.remind,
    'reminder': TaskType.remind,
    '备忘': TaskType.memo,
    '笔记': TaskType.memo,
    'memo': TaskType.memo,
    'note': TaskType.memo,
  };

  /// 校验模型给的 `kind`；不认识的写法和没给一样，返回 null 交给调用方推断。
  static TaskType? _validateKind(Object? raw, List<String> warnings) {
    final text = _cleanString(raw, 20).replaceAll(RegExp(r'\s+'), '').toLowerCase();
    if (text.isEmpty) return null;
    final kind = _kindAliases[text];
    if (kind == null) {
      warnings.add('模型给的「时间类型」写法「$text」不认识，已按时间去判断');
      return null;
    }
    return kind;
  }

  /// 备忘型没有时间，内部给一个占位值（今天 23:59），界面上不显示。
  static DateTime _todayEnd() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, 23, 59);
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
    task.startTime = startTime ?? endTime;
    // ===== P1：四种时间语义由模型划分，这里按类型把时间字段摆正 =====
    // applyKind 还会替「提醒型」打开提醒（就在那一刻）、替「备忘型」关掉提醒
    task.applyKind(kind);
    task.repeatEndsTime = dateOnly(endTime);
    task.priority = priority;
    if (tags.isNotEmpty) {
      task.tags = <String>[...tags];
      // 注意：**不把 AI 生成的标签写进标签库**。
      // 标签库只由「标签管理」里显式新建来增加（用户要求），AI 写上去的标签
      // 和手填的一样，只属于这条待办本身。
    }
    if (location.isNotEmpty) task.location = location;
    if (subtasks.isNotEmpty) {
      task.subtasks = <SubTask>[
        for (final step in subtasks) step.toSubTask(),
      ];
    }
    // 提醒：活动锚「开始」、截止锚「截止」，再按模型给的提前量往前推。
    // 模型没给（0）就交给应用里的默认提前量，不再硬编码。
    // 注意这里不能用 schedulesReminder —— 那需要 reminderEnabled，而我们现在才要打开它。
    if (reminderMinutes > 0 && !task.isMemo) {
      final fireAt = task.reminderAnchor
          .subtract(Duration(minutes: reminderMinutes));
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
