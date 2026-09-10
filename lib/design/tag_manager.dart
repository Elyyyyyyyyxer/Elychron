import 'package:celechron/database/database_helper.dart';
import 'package:celechron/mod/database_mod.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show ReorderableListView;
import 'package:get/get.dart';

/// 标签可选颜色
const List<Color> kTagPalette = [
  Color(0xFF007AFF), // 蓝
  Color(0xFF34C759), // 绿
  Color(0xFFFF9500), // 橙
  Color(0xFFFF3B30), // 红
  Color(0xFFAF52DE), // 紫
  Color(0xFFFF2D55), // 粉
  Color(0xFF30B0C7), // 青
  Color(0xFF5856D6), // 靛
  Color(0xFFFFCC00), // 黄
  Color(0xFF8E8E93), // 灰
];

DatabaseHelper? _db() {
  try {
    return Get.find<DatabaseHelper>(tag: 'db');
  } catch (_) {
    return null;
  }
}

/// 标签颜色：用户设过就用设的，否则按名字稳定散列到调色板
Color tagColorOf(String tag) {
  final saved = _db()?.getTagColor(tag);
  if (saved != null) return Color(saved);
  var hash = 0;
  for (final code in tag.codeUnits) {
    hash = (hash * 31 + code) & 0x7fffffff;
  }
  return kTagPalette[hash % kTagPalette.length];
}

/// 标签管理：新增 / 删除 / 拖动排序 / 选颜色
Future<void> showTagManager(
  BuildContext context, {
  VoidCallback? onChanged,
}) {
  return showCupertinoModalPopup<void>(
    context: context,
    builder: (BuildContext context) => _TagManagerSheet(onChanged: onChanged),
  );
}

class _TagManagerSheet extends StatefulWidget {
  final VoidCallback? onChanged;

  const _TagManagerSheet({this.onChanged});

  @override
  State<_TagManagerSheet> createState() => _TagManagerSheetState();
}

class _TagManagerSheetState extends State<_TagManagerSheet> {
  final _controller = TextEditingController();
  List<String> _tags = [];
  List<String> _loaded = [];

  @override
  void initState() {
    super.initState();
    final db = _db();
    _loaded = List<String>.of(db?.getTagLibrary() ?? <String>[]);
    _tags = List<String>.of(_loaded);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 只有真的改动过才写回，避免任何意外把标签库清空
  Future<void> _save() async {
    if (_tags.length == _loaded.length &&
        _tags.every((tag) => _loaded.contains(tag))) {
      return;
    }
    final db = _db();
    if (db == null) return;
    await db.setTagLibrary(_tags, allowEmpty: true);
    _loaded = List<String>.of(_tags);
    widget.onChanged?.call();
  }

  void _add() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    if (_tags.contains(name)) {
      _controller.clear();
      return;
    }
    setState(() {
      _tags.add(name);
      _controller.clear();
    });
    _save();
  }

  Future<void> _pickColor(String tag) async {
    final current = tagColorOf(tag);
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (BuildContext context) => Container(
        decoration: BoxDecoration(
          color: CupertinoDynamicColor.resolve(
              CupertinoColors.systemBackground, context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('「$tag」的颜色',
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w600)),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: kTagPalette.map((color) {
                    final selected = color.toARGB32() == current.toARGB32();
                    return GestureDetector(
                      onTap: () async {
                        await _db()?.setTagColor(tag, color.toARGB32());
                        if (context.mounted) Navigator.of(context).pop();
                        if (mounted) setState(() {});
                        widget.onChanged?.call();
                      },
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: selected
                              ? Border.all(
                                  color: CupertinoDynamicColor.resolve(
                                      CupertinoColors.label, context),
                                  width: 2.5)
                              : null,
                        ),
                        child: selected
                            ? const Icon(CupertinoIcons.checkmark,
                                size: 18, color: CupertinoColors.white)
                            : null,
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final labelColor =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    final textColor = CupertinoTheme.of(context).textTheme.textStyle.color;

    return Container(
      height: MediaQuery.of(context).size.height * 0.78,
      decoration: BoxDecoration(
        color: CupertinoDynamicColor.resolve(
            CupertinoColors.systemBackground, context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Row(
                children: [
                  const SizedBox(width: 60),
                  const Spacer(),
                  const Text('标签管理',
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(60, 44),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('完成'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: CupertinoTextField(
                      controller: _controller,
                      placeholder: '新建标签',
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: CupertinoDynamicColor.resolve(
                            CupertinoColors.tertiarySystemFill, context),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      style: TextStyle(fontSize: 15, color: textColor),
                      onSubmitted: (_) => _add(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  CupertinoButton(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                    color: CupertinoColors.systemBlue,
                    borderRadius: BorderRadius.circular(10),
                    onPressed: _add,
                    child: const Text('添加',
                        style: TextStyle(color: CupertinoColors.white)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _tags.isEmpty
                  ? Center(
                      child: Text('还没有标签，在上面输入后点「添加」',
                          style: TextStyle(fontSize: 14, color: labelColor)),
                    )
                  : ReorderableListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      buildDefaultDragHandles: false,
                      // 拖动时不加方框/阴影，直接用原样式的条目跟手
                      proxyDecorator: (child, index, animation) => child,
                      itemCount: _tags.length,
                      onReorderItem: (oldIndex, newIndex) {
                        setState(() {
                          final tag = _tags.removeAt(oldIndex);
                          _tags.insert(newIndex, tag);
                        });
                        _save();
                      },
                      itemBuilder: (context, index) {
                        final tag = _tags[index];
                        final color = tagColorOf(tag);
                        return Container(
                          key: ValueKey(tag),
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: CupertinoDynamicColor.resolve(
                                CupertinoColors.tertiarySystemGroupedBackground,
                                context),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              GestureDetector(
                                onTap: () => _pickColor(tag),
                                child: Container(
                                  width: 22,
                                  height: 22,
                                  decoration: BoxDecoration(
                                    color: color,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  tag,
                                  style:
                                      TextStyle(fontSize: 16, color: textColor),
                                ),
                              ),
                              CupertinoButton(
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(40, 40),
                                onPressed: () {
                                  setState(() => _tags.remove(tag));
                                  _save();
                                },
                                child: const Icon(CupertinoIcons.minus_circle,
                                    size: 20, color: CupertinoColors.systemRed),
                              ),
                              ReorderableDragStartListener(
                                index: index,
                                child: Icon(CupertinoIcons.bars,
                                    size: 20, color: labelColor),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
