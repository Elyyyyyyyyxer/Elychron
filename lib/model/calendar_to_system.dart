import 'dart:io';

import 'package:device_calendar/device_calendar.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:celechron/database/database_helper.dart';
import 'package:celechron/model/location_mapper.dart';
import 'package:celechron/utils/platform_features.dart';
import 'package:celechron/model/scholar.dart';
import 'package:celechron/model/period.dart';
import 'package:celechron/model/semester.dart';
import 'package:celechron/design/dingtalk_sheet.dart';
import 'package:celechron/services/diagnostic_log_service.dart';

/// 系统日历同步管理器
/// 负责创建和管理Celechron课表在系统日历中的同步
///
/// 主要功能:
/// - 日历权限管理: [requestPermissions], [hasCalendarPermission]
/// - 日历创建与管理: [getOrCreateCelechronCalendar], [deleteCelechronCalendar]
/// - 课程同步: [syncScholarToSystemCalendar], [resyncCalendarEvents]
/// - 学期管理: [syncSpecificSemester], [syncAllSemesters], [getAvailableSemesters]
/// - 同步状态: [calendarSyncEnabled], [checkInitialCalendarSyncStatus], [toggleCalendarSync]
/// - 事件管理: [clearSyncedEvents], [getSyncStats]
/// - UI交互: [showCalendarSyncDialog], [_showSemesterSelectionDialog]
///
/// 注意事项:
/// - 需要系统日历权限才能使用
/// - 支持单个学期或全部学期同步
/// - 可以自动处理重复事件
/// - 提供同步状态和统计信息

class CalendarToSystemManager {
  /// 系统日历里显示的名字。
  ///
  /// 历史版本叫Celechron课表， 那个名字会出现在用户的日历 App 里，
  /// 让人以为装的是官方 Celechron，所以改成本应用的品牌名。
  static const String elychronCalendarName = 'Elychron课表';

  /// 老名字：升级上来的用户日历里已经存在这一份。
  ///
  /// 查找时**必须认领它**（而不是另建一个新日历），否则用户手机上会出现
  /// 两份课表日历；认领后把它删掉再用新名字重建，事件由同步逻辑重新写入。
  static const List<String> legacyCalendarNames = ['Celechron课表'];

  static const String calendarDescription = '由Elychron自动同步的浙大课程表';

  final DeviceCalendarPlugin _deviceCalendarPlugin = DeviceCalendarPlugin();

  // 本次同步里已经处理过的稳定键（防止同一批数据里出现两条一模一样的事件）
  final Set<String> _syncedEventIds = <String>{};

  /// ===== 持久化「稳定键 → 系统日历事件 ID」（2026-09-18 修「同步会重复添加」）=====
  ///
  /// 用户反馈：「日程打开同步到系统日历，同步课表会重复添加而不是覆盖，需要手动删除」。
  ///
  /// 根因：原来只有一个**内存里**的 Set（[_syncedEventIds]），它只能防止"同一次同步里
  /// 重复"；而每次同步都新建 [Event]（不带 eventId），插件一律**新建**。
  /// 于是每同步一次就多出一整套课表，越堆越多，只能手动删。
  ///
  /// 现在把「稳定键 → 系统日历 eventId」落进 optionsBox：
  /// - 同一个键下一次同步是**更新那一件**（把 eventId 交给 createOrUpdateEvent）；
  /// - 这次课程列表里不再出现的键，连同它在系统日历里的事件一起删掉。
  /// 这才叫"覆盖"。
  static const String _kSyncedIndexKey = 'calendarSync.eventIndex';

  final Map<String, String> _syncedIndex = <String, String>{};

  DatabaseHelper? get _db {
    try {
      return Get.find<DatabaseHelper>(tag: 'db');
    } catch (_) {
      return null;
    }
  }

  /// 范围的键前缀。用 `::` 分隔，学期名里不会出现它。
  static String scopePrefixOf(String scope) => scope + '::';

  /// 带范围的稳定键
  static String scopedKey(String scope, Period period) =>
      scopePrefixOf(scope) + periodKey(period, scope: scope);

  /// 事件的**稳定**键（内容哈希）。
  ///
  /// ⚠️ 不能用 `String.hashCode`：Dart 只保证同一次运行内一致，跨版本/跨运行不保证；
  /// 拿它当持久化键的话，某次升级之后所有键都变了，课表又会被整套重建一遍。
  /// 所以这里自己算一个 FNV-1a，纯内容决定。
  static String periodKey(Period period, {String scope = ''}) {
    final mapped = CalendarLocationMapper.mapForCalendar(period.location);
    final raw = scope +
        '|' +
        period.summary +
        '|' +
        period.startTime.toIso8601String() +
        '|' +
        period.endTime.toIso8601String() +
        '|' +
        mapped +
        '|' +
        period.type.toString();
    var hash = 0xcbf29ce484222325;
    for (final unit in raw.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  /// 从库里读回上次的事件索引（读不出来就当没有）
  void _loadSyncedIndex() {
    _syncedIndex.clear();
    try {
      final raw = _db?.optionsBox.get(_kSyncedIndexKey);
      if (raw is Map) {
        for (final entry in raw.entries) {
          _syncedIndex[entry.key.toString()] = entry.value.toString();
        }
      }
    } catch (_) {
      // 读不出来最多是"这一次按新建处理"，不影响功能
    }
  }

  Future<void> _saveSyncedIndex() async {
    try {
      await _db?.optionsBox
          .put(_kSyncedIndexKey, Map<String, String>.from(_syncedIndex));
    } catch (_) {
      // 落盘失败只影响下次能不能"更新而不是新建"，不该让同步整体失败
    }
  }

  // 同步统计信息
  int _syncedCourseCount = 0; // 同步的课程数量
  int _syncedEventCount = 0; // 同步的日程数量

  // Celechron课表日历的ID
  String? _celechronCalendarId;

  final Scholar scholar;

  // 日历同步状态
  final RxBool _calendarSyncEnabled = false.obs;
  final RxBool _hasCalendarPermission = false.obs;

  bool get calendarSyncEnabled => _calendarSyncEnabled.value;
  bool get hasCalendarPermission => _hasCalendarPermission.value;

  CalendarToSystemManager(this.scholar);

  /// 桌面端说明（界面上要显示"这个功能在这儿换了个做法"）
  static String get desktopNote => PlatformFeatures.usesDeviceCalendarPlugin
      ? ''
      : '桌面端不直接写系统日历，改用导出 .ics（Outlook / 谷歌日历都能导入）';

  /// 获取设备日历权限
  Future<bool> checkPermissions() async {
    if (!PlatformFeatures.usesDeviceCalendarPlugin) return false;
    // device_calendar plugin doesn't support macOS
    if (Platform.isMacOS) {
      _hasCalendarPermission.value = false;
      return false;
    }
    try {
      var permissionsGranted = await _deviceCalendarPlugin.hasPermissions();
      if (permissionsGranted.isSuccess && permissionsGranted.data!) {
        _hasCalendarPermission.value = true;
        return true;
      } else {
        _hasCalendarPermission.value = false;
        return false;
      }
    } catch (e) {
      _hasCalendarPermission.value = false;
      return false;
    }
  }

  /// 获取设备日历权限
  Future<bool> requestPermissions() async {
    // device_calendar plugin doesn't support macOS
    if (Platform.isMacOS) {
      _hasCalendarPermission.value = false;
      return false;
    }
    try {
      var permissionsGranted = await _deviceCalendarPlugin.hasPermissions();
      if (permissionsGranted.isSuccess && permissionsGranted.data!) {
        _hasCalendarPermission.value = true;
        return true;
      } else {
        var permissionsRequested =
            await _deviceCalendarPlugin.requestPermissions();
        _hasCalendarPermission.value =
            permissionsRequested.isSuccess && permissionsRequested.data!;
        return _hasCalendarPermission.value;
      }
    } catch (e) {
      _hasCalendarPermission.value = false;
      return false;
    }
  }

  /// 获取或创建Celechron专用日历
  Future<String?> getOrCreateCelechronCalendar() async {
    try {
      // 如果已有缓存的日历ID，先验证是否仍然存在
      if (_celechronCalendarId != null) {
        var calendarsResult = await _deviceCalendarPlugin.retrieveCalendars();
        if (calendarsResult.isSuccess) {
          var existingCalendar = calendarsResult.data!
              .firstWhereOrNull((cal) => cal.id == _celechronCalendarId);
          if (existingCalendar != null) {
            return _celechronCalendarId;
          }
        }
      }

      // 查找是否已存在同名日历（新名字优先）
      var calendarsResult = await _deviceCalendarPlugin.retrieveCalendars();
      if (calendarsResult.isSuccess) {
        final calendars = calendarsResult.data!;
        var existingCalendar = calendars
            .firstWhereOrNull((cal) => cal.name == elychronCalendarName);

        if (existingCalendar != null) {
          _celechronCalendarId = existingCalendar.id;
          return existingCalendar.id;
        }

        // 认领老版本留下的Celechron课表：删掉它（事件由同步逻辑重写），
        // 再用新名字重建。不认领的话用户手机上会并排出现两份课表日历。
        final legacy = calendars
            .firstWhereOrNull((cal) => legacyCalendarNames.contains(cal.name));
        if (legacy != null && legacy.id != null) {
          await _deviceCalendarPlugin.deleteCalendar(legacy.id!);
        }
      }

      // 创建新的 Elychron 课表日历
      var createResult =
          await _deviceCalendarPlugin.createCalendar(elychronCalendarName);
      if (createResult.isSuccess && createResult.data != null) {
        _celechronCalendarId = createResult.data;
        return _celechronCalendarId;
      } else {
        return null;
      }
    } catch (e) {
      return null;
    }
  }

  /// 同步Scholar中的课程到系统日历
  /// [semester] 指定要同步的学期，如果为null则同步当前学期
  /// [syncAllSemesters] 是否同步所有学期，默认false
  Future<bool> syncScholarToSystemCalendar({
    Semester? semester,
    bool syncAllSemesters = false,
  }) async {
    // 桌面端没有 device_calendar（也没有"系统日历"这一说）：
    // 这里安静返回 false，界面会引导用户用"导出 .ics"那条路。
    if (!PlatformFeatures.usesDeviceCalendarPlugin) return false;
    try {
      // 检查权限
      if (!await requestPermissions()) {
        return false;
      }

      // 获取或创建Celechron日历
      var calendarId = await getOrCreateCelechronCalendar();
      if (calendarId == null) {
        return false;
      }

      // 清空本次的内存缓存，并把上次的事件索引读回来（见 _kSyncedIndexKey）
      _syncedEventIds.clear();
      _loadSyncedIndex();
      _syncedCourseCount = 0;
      _syncedEventCount = 0;

      // 本次同步的"范围"：只同步某个学期时，别去动别的学期已经同步好的事件
      final scope =
          syncAllSemesters ? 'all' : (semester ?? scholar.thisSemester).name;
      final scopePrefix = scopePrefixOf(scope);

      // 获取要同步的课程期间
      List<Period> allPeriods;

      if (syncAllSemesters) {
        // 同步所有学期
        allPeriods = scholar.periods;
      } else {
        // 同步指定学期或当前学期
        var targetSemester = semester ?? scholar.thisSemester;
        allPeriods = targetSemester.periods;
      }

      // 只同步课程和考试，不同步用户日程
      var coursePeriods = allPeriods
          .where((period) =>
              period.type == PeriodType.classes ||
              period.type == PeriodType.test)
          .toList();

      int syncedCount = 0;
      Set<String> syncedCourseNames = <String>{}; // 用于统计不重复的课程名

      // 本次要保留的稳定键（同步结束后，范围里没出现在这里的旧事件会被删掉）
      final keepKeys = <String>{};

      for (var period in coursePeriods) {
        try {
          // 生成唯一标识符，基于期间的内容
          var eventId = _generateEventId(period);
          // 键带上范围前缀，这样清理时能判断"这条属于哪个范围"
          final stableKey = scopedKey(scope, period);

          // 检查是否已经同步过（同一批数据里的重复条目）
          if (_syncedEventIds.contains(eventId)) {
            keepKeys.add(stableKey);
            continue;
          }

          // 创建日历事件
          var event = _createEventFromPeriod(period);
          event.calendarId = calendarId;
          // ★ 关键：把上一次这个键对应的事件 ID 带上 →
          //   插件走的是「更新那一件」而不是再新建一件（这才是"覆盖"）。
          final knownDeviceId = _syncedIndex[stableKey];
          if (knownDeviceId != null && knownDeviceId.isNotEmpty) {
            event.eventId = knownDeviceId;
          }

          // 添加到系统日历
          var createResult =
              await _deviceCalendarPlugin.createOrUpdateEvent(event);

          if (createResult != null && createResult.isSuccess) {
            _syncedEventIds.add(eventId);
            keepKeys.add(stableKey);
            // 记住系统给的事件 ID（更新时插件通常回同一个，返回空就沿用旧的）
            final returnedId = createResult.data;
            if (returnedId != null && returnedId.isNotEmpty) {
              _syncedIndex[stableKey] = returnedId;
            } else if (knownDeviceId != null) {
              _syncedIndex[stableKey] = knownDeviceId;
            }
            syncedCount++;
            // 统计课程名称（去重）
            syncedCourseNames.add(period.summary);
          }
        } catch (e) {
          // 忽略单个事件的错误，继续同步其他事件
        }
      }

      // ===== 覆盖语义的另一半：这次没再用到的旧事件要删掉 =====
      //
      // 只在**同一个范围**里清理（只同步本学期时，不去动别的学期的事件），
      // 免得用户只想更新本学期，结果把别的学期全删了。
      final unusedInScope = <String>[];
      for (final key in _syncedIndex.keys) {
        if (!key.startsWith(scopePrefix)) continue;
        if (keepKeys.contains(key)) continue;
        unusedInScope.add(key);
      }
      var removedCount = 0;
      for (final key in unusedInScope) {
        final deviceEventId = _syncedIndex.remove(key);
        if (deviceEventId == null || deviceEventId.isEmpty) continue;
        try {
          final deleted = await _deviceCalendarPlugin.deleteEvent(
              calendarId, deviceEventId);
          if (deleted.isSuccess) removedCount++;
        } catch (_) {
          // 事件可能已经被用户手动删掉了，忽略
        }
      }

      await _saveSyncedIndex();

      if (removedCount > 0) {
        // 删掉了几条过期的旧事件（课程没了 / 时间变了），写进诊断便于排查
        DiagnosticLogService.instance.record(
          module: '系统日历同步',
          operation: 'prune',
          message:
              '本次清掉 ' + removedCount.toString() + ' 条过期事件（范围：' + scope + '）',
        );
      }

      // 更新统计信息
      _syncedCourseCount = syncedCourseNames.length;
      _syncedEventCount = syncedCount;

      return syncedCount > 0;
    } catch (e) {
      return false;
    }
  }

  /// 从Period创建日历事件
  Event _createEventFromPeriod(Period period) {
    var event = Event(period.summary);

    // 设置基本信息
    event.title = period.summary;
    event.description = period.description;
    event.start =
        tz.TZDateTime.from(period.startTime, tz.getLocation('Asia/Shanghai'));
    event.end =
        tz.TZDateTime.from(period.endTime, tz.getLocation('Asia/Shanghai'));

    // 设置地点
    final mappedLocation =
        CalendarLocationMapper.mapForCalendar(period.location);
    if (mappedLocation.isNotEmpty) {
      event.location = mappedLocation;
    }

    // 根据类型设置不同的属性
    switch (period.type) {
      case PeriodType.classes:
        // 课程 - 设置为忙碌状态
        event.availability = Availability.Busy;
        break;
      case PeriodType.test:
        // 考试 - 设置为忙碌状态，并在标题前加标识
        event.availability = Availability.Busy;
        event.title = '💯 ${period.summary}';
        break;
      default:
        event.availability = Availability.Free;
    }

    return event;
  }

  /// 生成事件的唯一标识符
  /// 基于期间的关键信息生成，确保相同的课程不会重复添加
  String _generateEventId(Period period) {
    final mappedLocation =
        CalendarLocationMapper.mapForCalendar(period.location);
    // 使用摘要、开始时间、结束时间和地点生成唯一ID
    var key =
        '${period.summary}_${period.startTime.toIso8601String()}_${period.endTime.toIso8601String()}_$mappedLocation';
    return key.hashCode.toString();
  }

  /// 清除所有已同步的事件（可选功能）
  Future<bool> clearSyncedEvents() async {
    try {
      if (_celechronCalendarId == null) {
        return true;
      }

      // 获取日历中的所有事件
      var eventsResult = await _deviceCalendarPlugin.retrieveEvents(
        _celechronCalendarId!,
        RetrieveEventsParams(
          startDate: DateTime.now().subtract(const Duration(days: 365)),
          endDate: DateTime.now().add(const Duration(days: 365)),
        ),
      );

      if (eventsResult.isSuccess) {
        var events = eventsResult.data ?? [];
        for (var event in events) {
          try {
            await _deviceCalendarPlugin.deleteEvent(
              _celechronCalendarId!,
              event.eventId!,
            );
          } catch (e) {
            // 忽略单个事件删除失败
          }
        }

        _syncedEventIds.clear();
        _syncedCourseCount = 0;
        _syncedEventCount = 0;
        return true;
      }

      return false;
    } catch (e) {
      return false;
    }
  }

  /// 获取可用学期列表（供UI使用）
  List<String> getAvailableSemesters() {
    return scholar.semesters.map((semester) => semester.name).toList();
  }

  /// 根据学期名称获取学期对象
  Semester? getSemesterByName(String semesterName) {
    return scholar.semesters.firstWhereOrNull((s) => s.name == semesterName);
  }

  /// 删除整个Celechron日历
  /// 这将完全删除Celechron日历及其所有事件
  Future<bool> deleteCelechronCalendar() async {
    try {
      // 如果没有缓存的日历ID，先尝试查找
      if (_celechronCalendarId == null) {
        var calendarsResult = await _deviceCalendarPlugin.retrieveCalendars();
        if (calendarsResult.isSuccess) {
          var existingCalendar = calendarsResult.data!.firstWhereOrNull((cal) =>
              cal.name == elychronCalendarName ||
              legacyCalendarNames.contains(cal.name));
          if (existingCalendar != null) {
            _celechronCalendarId = existingCalendar.id;
          }
        }
      }

      // 如果还是没有找到日历，说明日历不存在
      if (_celechronCalendarId == null) {
        return true;
      }

      // 删除整个日历
      var deleteResult =
          await _deviceCalendarPlugin.deleteCalendar(_celechronCalendarId!);

      if (deleteResult.isSuccess && deleteResult.data!) {
        // 清空所有缓存信息（日历都没了，事件索引也要一起清）
        _celechronCalendarId = null;
        _syncedEventIds.clear();
        _syncedIndex.clear();
        try {
          await _db?.optionsBox.delete(_kSyncedIndexKey);
        } catch (_) {}
        _syncedCourseCount = 0;
        _syncedEventCount = 0;
        _calendarSyncEnabled.value = false;
        return true;
      } else {
        return false;
      }
    } catch (e) {
      return false;
    }
  }

  /// 获取同步统计信息
  Map<String, dynamic> getSyncStats() {
    return {
      'syncedCourseCount': _syncedCourseCount, // 课程数量
      'syncedEventCount': _syncedEventCount, // 日程数量
      'calendarId': _celechronCalendarId,
      'calendarName': elychronCalendarName,
    };
  }

  /// 显示提示弹窗
  void _showAlert(BuildContext context, String title, String message,
      {bool isError = false}) {
    if (context.mounted) {
      showCupertinoDialog(
        context: context,
        builder: (BuildContext context) => CupertinoAlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            CupertinoDialogAction(
              child: const Text('确定'),
              onPressed: () => Get.back(),
            ),
          ],
        ),
        barrierDismissible: true,
      );
    }
  }

  /// 强制重新同步课程（先清除后同步）
  Future<void> resyncCalendarEvents(BuildContext context) async {
    try {
      if (!await requestPermissions()) {
        _showAlert(context, '权限获取失败', '请在系统设置中手动开启日历权限');
        return;
      }

      // 先清除已有事件
      await clearSyncedEvents();

      // 重新同步
      bool syncSuccess = await syncScholarToSystemCalendar();

      if (syncSuccess) {
        var stats = getSyncStats();
        _showAlert(context, '重新同步成功',
            '已重新同步 ${stats['syncedCourseCount']} 门课程，共计 ${stats['syncedEventCount']} 个日程');
      } else {
        _showAlert(context, '重新同步失败', '无法重新同步课程到系统日历');
      }
    } catch (e) {
      _showAlert(context, '错误', '重新同步时出错: $e', isError: true);
    }
  }

  /// 同步指定学期的课程
  Future<void> syncSpecificSemester(
      BuildContext context, String semesterName) async {
    try {
      if (!await requestPermissions()) {
        _showAlert(context, '权限获取失败', '请在系统设置中手动开启日历权限');
        return;
      }

      var semester = getSemesterByName(semesterName);
      if (semester == null) {
        _showAlert(context, '错误', '未找到指定的学期');
        return;
      }

      // 先清除已有事件
      await clearSyncedEvents();

      // 同步指定学期
      bool syncSuccess = await syncScholarToSystemCalendar(
        semester: semester,
      );

      if (syncSuccess) {
        var stats = getSyncStats();
        _showAlert(context, '同步成功',
            '已同步 $semesterName 的 ${stats['syncedCourseCount']} 门课程，共计 ${stats['syncedEventCount']} 个日程');
      } else {
        _showAlert(context, '同步失败', '无法同步 $semesterName 的课程');
      }
    } catch (e) {
      _showAlert(context, '错误', '同步时出错: $e', isError: true);
    }
  }

  /// 同步所有学期的课程
  Future<void> syncAllSemesters(BuildContext context) async {
    try {
      if (!await requestPermissions()) {
        _showAlert(context, '权限获取失败', '请在系统设置中手动开启日历权限');
        return;
      }

      // 先清除已有事件
      await clearSyncedEvents();

      // 同步所有学期
      bool syncSuccess = await syncScholarToSystemCalendar(
        syncAllSemesters: true,
      );

      if (syncSuccess) {
        var stats = getSyncStats();
        _showAlert(context, '同步成功',
            '已同步所有学期的 ${stats['syncedCourseCount']} 门课程，共计 ${stats['syncedEventCount']} 个日程');
      } else {
        _showAlert(context, '同步失败', '无法同步所有学期的课程');
      }
    } catch (e) {
      _showAlert(context, '错误', '同步时出错: $e', isError: true);
    }
  }

  /// 显示日历同步选项对话框
  void showCalendarSyncDialog(BuildContext context) {
    // ===== MOD: 换成全 App 统一的钉钉风格弹层 =====
    showCupertinoModalPopup(
      context: context,
      builder: (BuildContext actionSheetContext) {
        return DingTalkSheetShell(
          title: '同步日历选项',
          subtitle: '把课表写进系统日历，或指定学期同步',
          children: [
            DingTalkSheetRow(
              label: '更新当前课表',
              subtitle: '按当前学期重新写入，已同步的事件会更新',
              onTap: () {
                Navigator.pop(actionSheetContext);
                resyncCalendarEvents(context);
              },
            ),
            DingTalkSheetRow(
              label: '选择学期同步',
              subtitle: '可以只同步某一学期，或所有学期一起',
              onTap: () {
                Navigator.pop(actionSheetContext);
                _showSemesterSelectionDialog(context);
              },
            ),
            DingTalkSheetCancel(
              label: '取消',
              onTap: () => Navigator.pop(actionSheetContext),
            ),
          ],
        );
      },
    );
  }

  /// 显示学期选择对话框
  void _showSemesterSelectionDialog(BuildContext context) {
    final semesters = getAvailableSemesters();

    if (semesters.isEmpty) {
      _showAlert(context, '提示', '没有可同步的学期数据，请先登录');
      return;
    }

    showCupertinoModalPopup(
      context: context,
      builder: (BuildContext actionSheetContext) {
        // ===== MOD: 换成钉钉风格弹层 =====
        return DingTalkSheetShell(
          title: '选择学期',
          subtitle: '选一个学期单独同步，或把所有学期一起同步',
          children: [
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final semester in semesters)
                      DingTalkSheetRow(
                        label: semester,
                        onTap: () {
                          Navigator.pop(actionSheetContext);
                          syncSpecificSemester(context, semester);
                        },
                      ),
                    DingTalkSheetRow(
                      label: '同步所有学期',
                      onTap: () {
                        Navigator.pop(actionSheetContext);
                        syncAllSemesters(context);
                      },
                    ),
                  ],
                ),
              ),
            ),
            DingTalkSheetCancel(
              label: '取消',
              onTap: () => Navigator.pop(actionSheetContext),
            ),
          ],
        );
      },
    );
  }

  /// 检查初始日历同步状态
  Future<void> checkInitialCalendarSyncStatus() async {
    // device_calendar plugin doesn't support macOS
    if (Platform.isMacOS) {
      _calendarSyncEnabled.value = false;
      _hasCalendarPermission.value = false;
      return;
    }
    try {
      // 先检查权限
      await checkPermissions();

      // 如果没有权限，直接返回
      if (!_hasCalendarPermission.value) {
        _calendarSyncEnabled.value = false;
        return;
      }

      var calendarsResult = await _deviceCalendarPlugin.retrieveCalendars();
      if (calendarsResult.isSuccess) {
        var existingCalendar = calendarsResult.data!.firstWhereOrNull((cal) =>
            cal.name == elychronCalendarName ||
            legacyCalendarNames.contains(cal.name));

        if (existingCalendar != null) {
          // 如果找到了Celechron日历，说明之前可能开启过同步
          // 但为了保险起见，我们检查日历中是否有事件
          var eventsResult = await _deviceCalendarPlugin.retrieveEvents(
            existingCalendar.id!,
            RetrieveEventsParams(
              startDate: DateTime.now().subtract(const Duration(days: 30)),
              endDate: DateTime.now().add(const Duration(days: 30)),
            ),
          );

          if (eventsResult.isSuccess &&
              (eventsResult.data?.isNotEmpty ?? false)) {
            // 如果有事件，说明确实在使用，设置为已开启状态
            _calendarSyncEnabled.value = true;
          }
        }
      }
    } catch (e) {
      // 忽略错误
    }
  }

  /// 切换日历同步功能
  Future<void> toggleCalendarSync(BuildContext context, bool enabled) async {
    // macOS 暂不支持系统日历同步功能
    if (Platform.isMacOS) {
      _showAlert(context, '暂不支持', 'macOS 系统暂不支持日历同步功能');
      return;
    }

    if (enabled) {
      // 如果要开启同步，先检查权限
      if (!await requestPermissions()) {
        _showAlert(context, '权限获取失败', '请在系统设置中手动开启日历权限');
        return;
      }

      // 检查是否已登录
      if (!scholar.isLogan) {
        _showAlert(context, '提示', '请先登录后再开启日历同步功能');
        return;
      }

      // 开始同步当前学期课程到系统日历
      bool syncSuccess = await syncScholarToSystemCalendar();

      if (syncSuccess) {
        _calendarSyncEnabled.value = true;
        var stats = getSyncStats();
        _showAlert(context, '同步成功',
            '已同步 ${stats['syncedCourseCount']} 门课程，共计 ${stats['syncedEventCount']} 个日程');
      } else {
        // For iOS, show different message
        if (Platform.isIOS) {
          _showAlert(context, '同步失败', '无法同步课程到系统日历，从日历中移除Google账户后重试');
        } else {
          _showAlert(context, '同步失败', '无法同步课程到系统日历，请检查权限和网络连接');
        }
      }
    } else {
      // 关闭同步功能
      _calendarSyncEnabled.value = false;

      // 删除课表数据和Celechron日历
      try {
        bool deleteSuccess = await deleteCelechronCalendar();
        if (deleteSuccess) {
          _showAlert(context, '成功', '日历同步功能已关闭，已删除课表数据和Celechron日历');
        } else {
          _showAlert(context, '成功', '日历同步功能已关闭，但删除日历时遇到问题');
        }
      } catch (e) {
        _showAlert(context, '成功', '日历同步功能已关闭，但删除日历时出错: $e');
      }
    }
  }
}
