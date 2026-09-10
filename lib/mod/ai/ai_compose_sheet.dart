import 'package:celechron/mod/ai/ai_settings_page.dart';
import 'package:celechron/mod/ai/ai_task_draft.dart';
import 'package:celechron/mod/ai/deepseek.dart';
import 'package:celechron/model/task.dart';
import 'package:flutter/cupertino.dart';

/// 粘贴一段文字 → AI 整理成待办草稿 → 用户确认后填入新建页。
///
/// 这里刻意做成「两段式」：先看 AI 读出了什么，再决定要不要填进去。
/// 草稿里的每一处越界（时间在过去、优先级不认识）都会在黄色区域里列出来，
/// 不做静默修补。
Future<AiTaskDraft?> showAiComposeSheet(
  BuildContext context, {
  String initialText = '',
}) {
  return showCupertinoModalPopup<AiTaskDraft>(
    context: context,
    builder: (BuildContext context) =>
        _AiComposeSheet(initialText: initialText),
  );
}

class _AiComposeSheet extends StatefulWidget {
  const _AiComposeSheet({required this.initialText});

  final String initialText;

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
      final draft = await AiTaskDraft.fromText(_controller.text);
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
            color: CupertinoColors.secondaryLabel.resolveFrom(context),
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
        '把通知、群消息、邮件内容粘进来，AI 会读出标题、截止时间、地点和要做的小步骤。',
        style: TextStyle(
          fontSize: 13,
          color: CupertinoColors.secondaryLabel.resolveFrom(context),
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
            : const Text('开始整理'),
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

  Widget _preview(BuildContext context, AiTaskDraft draft) {
    final rows = <Widget>[
      _kv(context, '标题', draft.summary),
      _kv(context, '截止', _describeTime(draft.endTime)),
      if (draft.description.isNotEmpty) _kv(context, '描述', draft.description),
      if (draft.location.isNotEmpty) _kv(context, '地点', draft.location),
      if (draft.priority != TaskPriority.normal)
        _kv(context, '优先级', taskPriorityName[draft.priority] ?? ''),
      if (draft.tags.isNotEmpty) _kv(context, '标签', draft.tags.join('、')),
      if (draft.subtasks.isNotEmpty)
        _kv(
          context,
          '子待办',
          draft.subtasks.map((s) => '· $s').join('\n'), // 多行展示，便于逐条检查
        ),
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
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
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
