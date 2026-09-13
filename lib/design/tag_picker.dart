import 'package:celechron/database/database_helper.dart';
import 'package:celechron/mod/database_mod.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';

/// 从标签库里挑一个标签，或在待办上临时写一个。
///
/// **写进来的新标签只挂在这条待办上，不进标签库** —— 标签库只由
/// 「标签管理」里显式点「添加」来增加（用户明确要求：真正新建了才出现，
/// 而不是随便填一个就出现在标签管理页和筛选行里）。
///
/// 返回用户选的/写的标签；用户取消时返回 null。
Future<String?> pickTagFromLibrary(
  BuildContext context, {
  required List<String> selected,
}) async {
  final db = Get.find<DatabaseHelper>(tag: 'db');
  final library = db.getTagLibrary();

  return showCupertinoModalPopup<String>(
    context: context,
    builder: (BuildContext context) =>
        _TagPickerSheet(library: library, selected: selected),
  );
}

class _TagPickerSheet extends StatefulWidget {
  final List<String> library;
  final List<String> selected;

  const _TagPickerSheet({required this.library, required this.selected});

  @override
  State<_TagPickerSheet> createState() => _TagPickerSheetState();
}

class _TagPickerSheetState extends State<_TagPickerSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final tag = _controller.text.trim();
    if (tag.isEmpty) return;
    Navigator.of(context).pop(tag);
  }

  @override
  Widget build(BuildContext context) {
    final labelColor =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    final textColor = CupertinoTheme.of(context).textTheme.textStyle.color;
    final available =
        widget.library.where((e) => !widget.selected.contains(e)).toList();

    return Padding(
      // 键盘弹出时把整块内容顶上去，避免输入框被键盘遮挡
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        color: CupertinoDynamicColor.resolve(
            CupertinoColors.systemBackground, context),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
                child: Text(
                  '添加待办标签',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
              ),

              // 标签库
              if (available.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(left: 20, top: 10, bottom: 6),
                  child: Text('标签库',
                      style: TextStyle(fontSize: 13, color: labelColor)),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: available
                        .map(
                          (tag) => GestureDetector(
                            onTap: () => Navigator.of(context).pop(tag),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: CupertinoDynamicColor.resolve(
                                    CupertinoColors
                                        .tertiarySystemGroupedBackground,
                                    context),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: CupertinoDynamicColor.resolve(
                                      CupertinoColors.separator, context),
                                  width: 0.5,
                                ),
                              ),
                              child: Text(tag,
                                  style: TextStyle(
                                      fontSize: 15, color: textColor)),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],

              // 新建标签
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
                child: Text('新建标签',
                    style: TextStyle(fontSize: 13, color: labelColor)),
              ),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                decoration: BoxDecoration(
                  color: CupertinoDynamicColor.resolve(
                      CupertinoColors.secondarySystemGroupedBackground,
                      context),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: CupertinoTextField(
                        controller: _controller,
                        placeholder: '例如：论文、实验、社团',
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: const BoxDecoration(),
                        style: TextStyle(fontSize: 16, color: textColor),
                        onSubmitted: (_) => _submit(),
                      ),
                    ),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(36, 36),
                      onPressed: _submit,
                      child: const Icon(
                        CupertinoIcons.add_circled,
                        size: 22,
                        color: CupertinoColors.systemBlue,
                      ),
                    ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: CupertinoButton(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        color: CupertinoDynamicColor.resolve(
                            CupertinoColors.systemFill, context),
                        borderRadius: BorderRadius.circular(22),
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text('取消',
                            style: TextStyle(fontSize: 16, color: textColor)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
