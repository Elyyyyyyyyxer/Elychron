import 'dart:io';

import 'package:celechron/mod/ai/ai_image.dart';
import 'package:celechron/mod/ai/ai_settings_page.dart';
import 'package:celechron/design/date_picker_sheet.dart';
import 'package:celechron/mod/ai/ai_task_draft.dart';
import 'package:celechron/mod/ai/deepseek.dart';
import 'package:celechron/model/task.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';

/// 粘贴一段文字 → AI 整理成待办草稿 → 用户确认后填入新建页。
///
/// 这里刻意做成「两段式」：先看 AI 读出了什么，再决定要不要填进去。
/// 草稿里的每一处越界（时间在过去、优先级不认识）都会在黄色区域里列出来，
/// 不做静默修补。
Future<AiTaskDraft?> showAiComposeSheet(
  BuildContext context, {
  String initialText = '',
  List<String> imagePaths = const <String>[],
}) {
  return showCupertinoModalPopup<AiTaskDraft>(
    context: context,
    builder: (BuildContext context) => _AiComposeSheet(
      initialText: initialText,
      imagePaths: imagePaths,
    ),
  );
}

class _AiComposeSheet extends StatefulWidget {
  const _AiComposeSheet({
    required this.initialText,
    this.imagePaths = const <String>[],
  });

  final String initialText;

  /// 非空表示这次是「识别截图」模式
  final List<String> imagePaths;

  @override
  State<_AiComposeSheet> createState() => _AiComposeSheetState();
}

class _AiComposeSheetState extends State<_AiComposeSheet> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialText);
  bool _ready = false;
  bool _loading = false;
  String? _error;
  AiTaskDraft? _draft;

  /// 这次要识别的图片（分享进来 + 手动添加的都在这）
  late final List<String> _images = List<String>.of(widget.imagePaths);

  @override
  void initState() {
    super.initState();
    AiConfig.load().then((_) {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
      _draft = null;
    });
    try {
      final draft = _images.isEmpty
          ? await AiTaskDraft.fromText(_controller.text)
          : await AiTaskDraft.fromImages(_images, hint: _controller.text);
      if (!mounted) return;
      setState(() => _draft = draft);
    } on AiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 手动挑图：从相册/文件里选截图，识别前能先确认图片对不对
  Future<void> _pickImages() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: true,
      );
      if (result == null) return;
      final paths = result.paths
          .whereType<String>()
          .where(AiImage.looksLikeImage)
          .toList();
      if (paths.isEmpty) return;
      if (!mounted) return;
      setState(() {
        for (final path in paths) {
          if (_images.length >= AiTaskDraft.maxImages) break;
          if (!_images.contains(path)) _images.add(path);
        }
        _draft = null;
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = '选图失败：$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: BoxDecoration(
          color: CupertinoColors.systemBackground.resolveFrom(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        ),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.86,
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _header(context),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _body(context),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 12, 8),
      child: Row(
        children: [
          const Text(
            'AI 整理成待办',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () => Navigator.of(context).pop(),
            child: const Icon(CupertinoIcons.xmark_circle_fill, size: 24),
          ),
        ],
      ),
    );
  }

  List<Widget> _body(BuildContext context) {
    if (!_ready) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Center(child: CupertinoActivityIndicator()),
        ),
      ];
    }

    if (!AiConfig.isReady) {
      return [
        const SizedBox(height: 8),
        Text(
          AiConfig.apiKey.isEmpty
              ? '还没有配置 API key。填入自己的 DeepSeek key 之后，这里就能把一段通知或聊天记录直接整理成待办。'
              : 'AI 功能还没打开。打开开关后即可使用。',
          style: TextStyle(
            fontSize: 14,
            color: CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context),
          ),
        ),
        const SizedBox(height: 16),
        CupertinoButton.filled(
          padding: const EdgeInsets.symmetric(vertical: 12),
          onPressed: () async {
            await Navigator.of(context, rootNavigator: true).push(
              CupertinoPageRoute<void>(
                builder: (BuildContext context) => const AiSettingsPage(),
              ),
            );
            if (mounted) setState(() {});
          },
          child: const Text('去配置'),
        ),
      ];
    }

    final children = <Widget>[
      Text(
        _images.isEmpty
            ? '把通知、群消息、邮件内容粘进来，AI 会读出标题、截止时间、地点和要做的小步骤。'
            : 'AI 会读出图里的文字（通知、群消息、海报、课表截图都行），整理成待办。',
        style: TextStyle(
          fontSize: 13,
          color: CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context),
        ),
      ),
      const SizedBox(height: 12),
      // ===== 图片区：缩略图 + 手动添加（让用户一眼确认图片有没有进来）=====
      if (_images.isNotEmpty)
        SizedBox(
          height: 92,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _images.length,
            separatorBuilder: (BuildContext context, int index) =>
                const SizedBox(width: 8),
            itemBuilder: (BuildContext context, int index) => Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.file(
                    File(_images[index]),
                    width: 92,
                    height: 92,
                    fit: BoxFit.cover,
                    errorBuilder: (
                      BuildContext context,
                      Object error,
                      StackTrace? stackTrace,
                    ) =>
                        Container(
                      width: 92,
                      height: 92,
                      alignment: Alignment.center,
                      color: CupertinoColors.systemGrey5.resolveFrom(context),
                      child: const Icon(CupertinoIcons.photo, size: 22),
                    ),
                  ),
                ),
                Positioned(
                  right: 2,
                  top: 2,
                  child: GestureDetector(
                    onTap: () => setState(() => _images.removeAt(index)),
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: CupertinoColors.black,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        CupertinoIcons.xmark,
                        size: 11,
                        color: CupertinoColors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _pickImages,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              const Icon(
                CupertinoIcons.add_circled,
                size: 19,
                color: CupertinoColors.activeBlue,
              ),
              const SizedBox(width: 6),
              Text(
                _images.isEmpty ? '添加图片（截图也能识别）' : '再加一张',
                style: const TextStyle(
                  fontSize: 14.5,
                  color: CupertinoColors.activeBlue,
                ),
              ),
              const Spacer(),
              if (_images.isNotEmpty)
                Text(
                  '已选 ${_images.length} 张 · 最多 ${AiTaskDraft.maxImages} 张',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context),
                  ),
                ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 10),
      Container(
        decoration: BoxDecoration(
          color: CupertinoColors.tertiarySystemFill.resolveFrom(context),
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: CupertinoTextField(
          controller: _controller,
          placeholder: '例如：关于本周五前提交《数据结构》实验报告的通知……',
          minLines: 4,
          maxLines: 8,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: const BoxDecoration(),
          onChanged: (_) {
            if (_draft != null || _error != null) {
              setState(() {
                _draft = null;
                _error = null;
              });
            }
          },
        ),
      ),
      const SizedBox(height: 12),
      CupertinoButton.filled(
        padding: const EdgeInsets.symmetric(vertical: 12),
        onPressed: _loading ? null : _run,
        child: _loading
            ? const SizedBox(
                height: 18,
                width: 18,
                child: CupertinoActivityIndicator(color: CupertinoColors.white),
              )
            : Text(_images.isEmpty ? '开始整理' : '识别图中内容'),
      ),
    ];

    if (_error != null) {
      children.addAll([
        const SizedBox(height: 14),
        _note(context, _error!, CupertinoColors.systemRed, '出错'),
      ]);
    }

    final draft = _draft;
    if (draft != null) {
      children.addAll([
        const SizedBox(height: 16),
        _preview(context, draft),
        const SizedBox(height: 14),
        CupertinoButton.filled(
          padding: const EdgeInsets.symmetric(vertical: 12),
          onPressed: () => Navigator.of(context).pop(draft),
          child: const Text('填入待办'),
        ),
        const SizedBox(height: 6),
        CupertinoButton(
          padding: const EdgeInsets.symmetric(vertical: 8),
          onPressed: () => setState(() => _draft = null),
          child: const Text('改改文字再试'),
        ),
      ]);
    }

    return children;
  }

  /// 预览里点某一步的时间 → 改它的起点（原本有段就保留时长，没有就当成一个时刻）
  Future<void> _editStepTime(AiTaskDraft draft, int index) async {
    final step = draft.subtasks[index];
    final picked = await showDateTimeSheet(
      context,
      initial: step.anchor ?? draft.endTime,
      title: '这一步的时间',
    );
    if (picked == null || !mounted) return;

    final start = step.startTime;
    final end = step.endTime;
    final length = (start != null && end != null && end.isAfter(start))
        ? end.difference(start)
        : Duration.zero;

    final next = List<AiStepDraft>.of(draft.subtasks);
    next[index] = AiStepDraft(
      title: step.title,
      note: step.note,
      location: step.location,
      startTime: picked,
      endTime: length > Duration.zero ? picked.add(length) : null,
    );
    setState(() => _draft = draft.copyWith(subtasks: next));
  }

  Widget _preview(BuildContext context, AiTaskDraft draft) {
    final rows = <Widget>[
      _kv(context, '标题', draft.summary),
      // ===== P1：模型划分的时间语义（活动 / 截止 / 提醒 / 备忘）=====
      _kv(context, '类型', taskKindName[draft.kind] ?? ''),
      if (draft.startTime != null)
        _kv(context, '开始', _describeTime(draft.startTime!)),
      _kv(context, draft.kind == TaskType.memo ? '时间' : '截止',
          draft.kind == TaskType.memo ? '备忘不设时间' : _describeTime(draft.endTime)),
      if (draft.description.isNotEmpty) _kv(context, '描述', draft.description),
      if (draft.location.isNotEmpty) _kv(context, '地点', draft.location),
      if (draft.reminderMinutes > 0)
        _kv(
          context,
          '提醒',
          '提前 ${_describeMinutes(draft.reminderMinutes)}'
              '（${_describeTime((draft.startTime ?? draft.endTime).subtract(Duration(minutes: draft.reminderMinutes)))}）',
        ),
      if (draft.priority != TaskPriority.normal)
        _kv(context, '优先级', taskPriorityName[draft.priority] ?? ''),
      if (draft.tags.isNotEmpty) _kv(context, '标签', draft.tags.join('、')),
      // ===== P2：步骤可以在预览里直接删 / 改时间（不用先填进去再改）=====
      if (draft.subtasks.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 4),
          child: Row(
            children: [
              Text('子待办',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context))),
              const Spacer(),
              if (draft.subtasks.any((s) => s.hasTime))
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 28),
                  onPressed: () => setState(() {
                    _draft = draft.copyWith(
                      subtasks: draft.subtasks.map((s) => s.withoutTime()).toList(),
                    );
                  }),
                  child: const Text('全部不要时间', style: TextStyle(fontSize: 13)),
                ),
            ],
          ),
        ),
        ...draft.subtasks.asMap().entries.map((entry) {
          final index = entry.key;
          final step = entry.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 点时间 → 改这一步的起点（时长保留）
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _editStepTime(draft, index),
                  child: Container(
                    width: 78,
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      step.timeLabel.isEmpty ? '＋时间' : step.timeLabel,
                      style: TextStyle(
                        fontSize: 12,
                        color: step.hasTime
                            ? const Color(0xFFFF699A)
                            : CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(step.title, style: const TextStyle(fontSize: 14)),
                      if (step.location.isNotEmpty || step.note.isNotEmpty)
                        Text(
                          [
                            if (step.location.isNotEmpty) '@${step.location}',
                            if (step.note.isNotEmpty) step.note,
                          ].join(' · '),
                          style: TextStyle(
                              fontSize: 12,
                              color: CupertinoColors.secondaryLabel
                                  .resolveFrom(context)),
                        ),
                    ],
                  ),
                ),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(28, 28),
                  onPressed: () => setState(() {
                    final next = List<AiStepDraft>.of(draft.subtasks)
                      ..removeAt(index);
                    _draft = draft.copyWith(subtasks: next);
                  }),
                  child: Icon(CupertinoIcons.xmark_circle_fill,
                      size: 18,
                      color: CupertinoDynamicColor.resolve(CupertinoColors.tertiaryLabel, context)),
                ),
              ],
            ),
          );
        }),
      ],
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: CupertinoColors.secondarySystemGroupedBackground
                .resolveFrom(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: CupertinoColors.separator.resolveFrom(context),
              width: 0.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: rows,
          ),
        ),
        if (draft.uncertain.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: CupertinoColors.systemGrey.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '原文没写清、已经留空的字段：${draft.uncertain.join("、")}\n（需要的话自己补上）',
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
        if (draft.warnings.isNotEmpty) ...[
          const SizedBox(height: 10),
          _note(
            context,
            draft.warnings.map((w) => '· $w').join('\n'),
            CupertinoColors.systemOrange,
            '我替你改了几处',
          ),
        ],
      ],
    );
  }

  Widget _kv(BuildContext context, String key, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 62,
            child: Text(
              key,
              style: TextStyle(
                fontSize: 13.5,
                color: CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context),
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 14.5)),
          ),
        ],
      ),
    );
  }

  Widget _note(BuildContext context, String text, Color color, String title) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(text, style: const TextStyle(fontSize: 13.5)),
        ],
      ),
    );
  }

  /// 30 → 30 分钟；60 → 1 小时；1440 → 1 天
  static String _describeMinutes(int minutes) {
    if (minutes < 60) return '$minutes 分钟';
    if (minutes % 1440 == 0) return '${minutes ~/ 1440} 天';
    if (minutes % 60 == 0) return '${minutes ~/ 60} 小时';
    return '${minutes ~/ 60} 小时 ${minutes % 60} 分钟';
  }

  /// 「2026-09-12 23:59（后天）」——加个相对说法，方便一眼判断对不对
  static String _describeTime(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    final stamp = '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(time.year, time.month, time.day);
    final diff = target.difference(today).inDays;
    switch (diff) {
      case 0:
        return '$stamp（今天）';
      case 1:
        return '$stamp（明天）';
      case 2:
        return '$stamp（后天）';
      default:
        return diff > 2 && diff <= 7 ? '$stamp（$diff 天后）' : stamp;
    }
  }
}
