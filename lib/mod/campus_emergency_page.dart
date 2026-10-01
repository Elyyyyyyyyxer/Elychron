import 'dart:convert';

import 'package:celechron/design/app_accent.dart';
import 'package:celechron/design/page_background.dart';
import 'package:celechron/design/section_text_style.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:url_launcher/url_launcher_string.dart';

/// ===== 校园服务：紧急电话（2026-09-30）=====
///
/// 数据来源与调研见 docs/CAMPUS_SERVICES_PLAN.md：
/// 浙大那个「紧急电话」lightapp 的数据接口就是静态 JSON，但主机是**内网地址**
/// （校外不可达），而注释里那个真后端（210.32.159.215）现在**已经不通了**。
///
/// 所以这里**随包带一份快照**（assets/campus/emergency.json）：
/// 断网、校外、紧急情况下都能打开 —— 这才是这个功能该有的样子。
/// 数据本身长期稳定（用户原话：「这种东西长期稳定」），只在必要时要更新。
class CampusEmergencyPage extends StatefulWidget {
  const CampusEmergencyPage({super.key});

  @override
  State<CampusEmergencyPage> createState() => _CampusEmergencyPageState();
}

/// 一条可拨号的记录（部门 or 人）
class _EmergencyEntry {
  const _EmergencyEntry(this.title, this.phone, this.subtitle);

  final String title;
  final String phone;
  final String subtitle;
}

class _CampusEmergencyPageState extends State<CampusEmergencyPage> {
  final TextEditingController _search = TextEditingController();

  bool _loading = true;
  bool _failed = false;
  String _updatedAt = '';
  String _source = '';
  List<_EmergencyEntry> _quick = <_EmergencyEntry>[];
  List<_EmergencyEntry> _directory = <_EmergencyEntry>[];

  @override
  void initState() {
    super.initState();
    _search.addListener(_onQueryChanged);
    _load();
  }

  @override
  void dispose() {
    _search.removeListener(_onQueryChanged);
    _search.dispose();
    super.dispose();
  }

  void _onQueryChanged() => setState(() {});

  Future<void> _load() async {
    try {
      final raw = await rootBundle.loadString('assets/campus/emergency.json');
      final decoded = jsonDecode(raw);
      final map = decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{};
      final quick = <_EmergencyEntry>[];
      for (final item in (map['quick'] as List? ?? const <dynamic>[])) {
        if (item is! Map) continue;
        final name = item['name']?.toString() ?? '';
        final phone = item['phone']?.toString() ?? '';
        if (name.isEmpty || phone.isEmpty) continue;
        quick.add(_EmergencyEntry(name, phone, ''));
      }
      final directory = <_EmergencyEntry>[];
      for (final item in (map['departments'] as List? ?? const <dynamic>[])) {
        if (item is! Map) continue;
        final name = item['name']?.toString() ?? '';
        final address = item['address']?.toString() ?? '';
        final phone = item['phone']?.toString() ?? '';
        if (name.isEmpty) continue;
        directory.add(_EmergencyEntry(name, phone, address));
        for (final staff in (item['staff'] as List? ?? const <dynamic>[])) {
          if (staff is! Map) continue;
          final staffPhone = staff['phone']?.toString() ?? '';
          if (staffPhone.isEmpty) continue;
          final title = staff['title']?.toString() ?? '';
          final person = staff['name']?.toString() ?? '';
          final label = (title + ' ' + person).trim();
          directory.add(_EmergencyEntry(
            label.isEmpty ? name : label,
            staffPhone,
            address.isEmpty ? name : name + ' · ' + address,
          ));
        }
      }
      if (!mounted) return;
      setState(() {
        _quick = quick;
        _directory = directory;
        _updatedAt = map['updatedAt']?.toString() ?? '';
        _source = map['source']?.toString() ?? '';
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  bool _matches(_EmergencyEntry entry) {
    final query = _search.text.trim();
    if (query.isEmpty) return true;
    return entry.title.contains(query) ||
        entry.phone.contains(query) ||
        entry.subtitle.contains(query);
  }

  Future<void> _call(String phone) async {
    final digits = phone.replaceAll(RegExp('[^0-9+]'), '');
    if (digits.isEmpty) return;
    try {
      await launchUrlString('tel:' + digits, mode: LaunchMode.externalApplication);
    } catch (_) {
      // 打不开拨号盘就算了，号码已经显示在屏幕上
    }
  }

  @override
  Widget build(BuildContext context) {
    final quick = _quick.where(_matches).toList();
    final directory = _directory.where(_matches).toList();
    return CupertinoPageScaffold(
      backgroundColor: pageBackground(context),
      navigationBar: const CupertinoNavigationBar(middle: Text('紧急电话')),
      child: ListView(
        padding: EdgeInsets.only(
          top: 4,
          bottom: 24 + MediaQuery.of(context).padding.bottom,
        ),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: CupertinoSearchTextField(
              controller: _search,
              placeholder: '搜索单位或号码',
            ),
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(28),
              child: Center(child: CupertinoActivityIndicator(radius: 10)),
            ),
          if (_failed)
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 20, 24, 0),
              child: Text('读不到随包的紧急电话数据（assets/campus/emergency.json）'),
            ),
          if (quick.isNotEmpty)
            _section(
              context,
              header: '常用紧急号码',
              footer: '点一下直接拨号。数据随包，断网也看得到。' +
                  (_updatedAt.isEmpty ? '' : '（快照 ' + _updatedAt + '）'),
              entries: quick,
              emphasize: true,
            ),
          if (directory.isNotEmpty)
            _section(
              context,
              header: '各单位',
              footer: _source.isEmpty ? '' : '来源：' + _source,
              entries: directory,
              emphasize: false,
            ),
        ],
      ),
    );
  }

  Widget _section(
    BuildContext context, {
    required String header,
    required String footer,
    required List<_EmergencyEntry> entries,
    required bool emphasize,
  }) =>
      CupertinoListSection.insetGrouped(
        backgroundColor: pageBackground(context),
        additionalDividerMargin: 2,
        header: sectionHeader(context, header),
        footer: footer.isEmpty ? null : sectionFooter(context, footer),
        children: <Widget>[
          for (final entry in entries)
            CupertinoListTile(
              title: Text(
                entry.title,
                style: TextStyle(
                  fontSize: emphasize ? 16 : null,
                  fontWeight: emphasize ? FontWeight.w600 : null,
                ),
              ),
              subtitle: Text(
                entry.subtitle.isEmpty
                    ? entry.phone
                    : entry.subtitle + ' · ' + entry.phone,
              ),
              trailing: Icon(
                CupertinoIcons.phone_fill,
                size: 18,
                color: AppAccent.primary,
              ),
              onTap: () => _call(entry.phone),
            ),
        ],
      );
}
