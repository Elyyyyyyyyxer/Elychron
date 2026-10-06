import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:celechron/database/database_helper.dart';
import 'package:celechron/http/calendar_bundled_config.dart';
import 'package:celechron/model/scholar.dart';
import 'package:celechron/mod/physics_lab_bridge.dart';
import 'package:celechron/mod/physics_lab_courses.dart';
import 'package:celechron/utils/platform_features.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:webview_flutter/webview_flutter.dart';

class PhysicsLabService {
  PhysicsLabService._();
  @visibleForTesting
  PhysicsLabService.forTesting();
  Worker? _observer;
  void dispose() {
    _observer?.dispose();
    status.dispose();
  }

  static final instance = PhysicsLabService._();
  static final courseUrl =
      Uri.parse('http://10.203.16.55:86/lab-course/studentCourse');
  static const _enabledKey = 'physicsLabEnabled';
  static const _cacheKey = 'physicsLabCourseCache';
  static const _statusKey = 'physicsLabStatus';
  final status = ValueNotifier<String>('尚未连接');
  List<PhysicsLabLesson> _lessons = [];
  final Map<String, Map<String, dynamic>> _calendars = {};
  final Set<String> _createdSemesterNames = {};
  bool _attaching = false;
  String _ownerScope = '';
  String _linkedScholarScope = '';
  WebViewController? _controller;
  Completer<void>? _loading;
  Future<void>? _starting;
  Future<bool>? _refreshing;
  DateTime? _lastAttempt;

  DatabaseHelper get _db => Get.find<DatabaseHelper>(tag: 'db');
  Rx<Scholar> get _scholar => Get.find<Rx<Scholar>>(tag: 'scholar');
  bool get available => PlatformFeatures.hasWebViewLogin;
  bool get enabled =>
      _db.optionsBox.get(_enabledKey, defaultValue: false) == true;
  String _scope(String account) => account.isEmpty
      ? ''
      : sha256.convert(utf8.encode(account)).toString().substring(0, 16);
  String get _scholarScope => _scope(_scholar.value.username ?? '');
  bool get _canDisplay => _scholarScope.isEmpty
      ? _linkedScholarScope.isEmpty
      : _scholarScope == _ownerScope;
  List<PhysicsLabLesson> get lessons =>
      List.unmodifiable(_canDisplay ? _lessons : <PhysicsLabLesson>[]);

  Future<void> start() => _starting ??= _start();
  Future<void> _start() async {
    status.value =
        _db.optionsBox.get(_statusKey, defaultValue: '尚未连接').toString();
    _observer = ever<Scholar>(_scholar, (_) => _attach());
    try {
      await _loadCalendars();
      final raw = _db.optionsBox.get(_cacheKey);
      if (raw is String && raw.isNotEmpty) {
        final cache = jsonDecode(raw) as Map;
        _ownerScope = cache['ownerScope'] as String;
        _linkedScholarScope = cache['linkedScholarScope'] as String;
        _createdSemesterNames
            .addAll((cache['createdSemesters'] as List).cast<String>());
        _lessons = (cache['lessons'] as List)
            .map((row) =>
                PhysicsLabLesson.fromJson(Map<String, dynamic>.from(row)))
            .toList();
      }
      _attach();
    } on Object {
      status.value = '实验缓存无法读取，请重新同步';
    }
  }

  Future<void> setEnabled(bool value) async {
    await start();
    await _db.optionsBox.put(_enabledKey, value);
    _attach();
    _scholar.refresh();
    if (value) await refresh(force: true);
  }

  bool _allowed(String url) {
    final uri = Uri.tryParse(url);
    return uri != null &&
        uri.scheme == 'http' &&
        uri.host == courseUrl.host &&
        uri.port == courseUrl.port &&
        uri.path.startsWith('/lab-course/');
  }

  WebViewController loginController() {
    if (!available) throw StateError('当前平台没有内置浏览器');
    _controller ??= WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (request) => _allowed(request.url)
            ? NavigationDecision.navigate
            : NavigationDecision.prevent,
        onPageFinished: (_) {
          if (_loading != null && !_loading!.isCompleted) _loading!.complete();
        },
        onWebResourceError: (error) {
          if (error.isForMainFrame == true &&
              _loading != null &&
              !_loading!.isCompleted) {
            _loading!.complete();
          }
        },
      ));
    return _controller!;
  }

  Future<void> loadLogin() async {
    try {
      final controller = loginController();
      await controller.loadRequest(courseUrl);
    } on Object {
      status.value = '选课页面加载失败，请检查校园网或 ZJU 代理';
    }
  }

  Future<bool> refresh({bool force = false, bool connect = false}) async {
    await start();
    if ((!enabled && !connect) || !available) return false;
    final pending = _refreshing;
    if (pending != null) return await pending;
    if (!force &&
        _lastAttempt != null &&
        DateTime.now().difference(_lastAttempt!) < const Duration(minutes: 5)) {
      return false;
    }
    _lastAttempt = DateTime.now();
    final future = _readAndApply(connect: connect);
    _refreshing = future;
    try {
      return await future;
    } finally {
      if (identical(_refreshing, future)) _refreshing = null;
    }
  }

  Future<bool> _readAndApply({required bool connect}) async {
    final scholarScope = _scholarScope;
    status.value = '正在同步实验课表…';
    try {
      final controller = loginController();
      final loading = Completer<void>();
      _loading = loading;
      await controller.loadRequest(courseUrl);
      await loading.future.timeout(const Duration(seconds: 20));
      await controller
          .runJavaScript(physicsLabReadScript)
          .timeout(const Duration(seconds: 5));
      final deadline = DateTime.now().add(const Duration(seconds: 40));
      Map<String, dynamic>? response;
      while (DateTime.now().isBefore(deadline)) {
        final raw = await controller
            .runJavaScriptReturningResult(
                'JSON.stringify(window.__elychronPhysics || {state:"pending"})')
            .timeout(const Duration(seconds: 5));
        Object? decoded = raw;
        if (decoded is String) decoded = jsonDecode(decoded);
        if (decoded is String) decoded = jsonDecode(decoded);
        if (decoded is Map && decoded['state'] != 'pending') {
          response = Map<String, dynamic>.from(decoded);
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      if (response == null) throw TimeoutException('课表读取超时');
      if (response['state'] == 'login') {
        status.value = '请在官网页面登录后点击“完成”';
        return false;
      }
      if (response['state'] != 'ready') throw const FormatException('官网课表读取失败');
      if (!connect && !enabled) return false;
      final ownerScope = _scope(response['owner']?.toString() ?? '');
      if (_scholarScope != scholarScope ||
          (scholarScope.isNotEmpty && scholarScope != ownerScope)) {
        status.value = '实验账号与当前教务账号不一致，请重新登录';
        return false;
      }
      final lessons = parsePhysicsLabCourses(response, calendars: _calendars);
      final semesters = _scholar.value.semesters;
      // Validate every session before saving a replacement cache or changing live data.
      final plan = planPhysicsLabCourses(semesters, lessons, _calendars);
      final created = {
        ..._createdSemesterNames,
        ...plan
            .where((p) => !semesters.any((s) => s.name == p.name))
            .map((s) => s.name)
      };
      final successStatus = '已同步 ${lessons.length} 次实验';
      await _db.optionsBox.putAll({
        _cacheKey: jsonEncode({
          'lessons': lessons.map((l) => l.toJson()).toList(),
          'ownerScope': ownerScope,
          'linkedScholarScope': scholarScope,
          'createdSemesters': created.toList(),
        }),
        if (connect) _enabledKey: true,
        _statusKey: successStatus,
      });
      _lessons = lessons;
      _ownerScope = ownerScope;
      _linkedScholarScope = scholarScope;
      _createdSemesterNames.addAll(created);
      installPhysicsLabCourses(semesters, plan, _createdSemesterNames);
      _scholar.refresh();
      status.value = successStatus;
      return true;
    } on Object {
      status.value = '同步失败，已有课表保留。请检查校园网或 ZJU 代理，并确认官网登录状态';
      return false;
    }
  }

  Future<void> _loadCalendars() async {
    for (final id in BundledCalendarConfig.bundledSemesters) {
      final raw = await BundledCalendarConfig.load(id);
      if (raw == null) continue;
      final name = '${id.substring(0, 9)}${id.endsWith('-1') ? '秋冬' : '春夏'}';
      _calendars[name] = Map<String, dynamic>.from(jsonDecode(raw));
    }
  }

  String _projectionStamp() => jsonEncode(_scholar.value.semesters
      .map((s) => [
            s.name,
            s.hasCalendar,
            s.physicsLabPeriods
                .map((p) => [
                      p.uid,
                      p.summary,
                      p.description,
                      p.location,
                      p.startTime.toIso8601String(),
                      p.endTime.toIso8601String()
                    ])
                .toList(),
          ])
      .toList());

  void _attach() {
    if (_attaching) return;
    _attaching = true;
    try {
      final before = _projectionStamp();
      final semesters = _scholar.value.semesters;
      final plan = planPhysicsLabCourses(
          semesters, enabled && _canDisplay ? _lessons : [], _calendars);
      installPhysicsLabCourses(semesters, plan, _createdSemesterNames);
      if (enabled && !_canDisplay) {
        status.value = '教务账号已切换，请重新连接普物实验';
      }
      if (_projectionStamp() != before) _scholar.refresh();
    } on Object {
      status.value = '实验课表转换失败，已有课表保留，请重新同步';
    } finally {
      _attaching = false;
    }
  }
}
