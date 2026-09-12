import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:celechron/model/task.dart';
import 'package:celechron/model/tombstone.dart';
import 'package:celechron/worker/fuse.dart';
import 'package:celechron/model/scholar.dart';
import 'package:celechron/model/period.dart';
import 'package:celechron/model/option.dart';
import 'package:celechron/utils/utils.dart';
import 'adapters/duration_adapter.dart';
import 'adapters/scholar_adapter.dart';
import 'package:celechron/model/focus_session.dart';
import 'package:celechron/utils/data_sync.dart';
import 'package:celechron/mod/ai/deepseek.dart';
import 'package:uuid/uuid.dart';
import 'adapters/deadline_adapter.dart';
import 'adapters/period_adapter.dart';
import 'adapters/fuse_adapter.dart';
import 'adapters/course_id_map_adapter.dart';
import 'adapters/focus_adapter.dart';

class DatabaseHelper {
  late final Box optionsBox;
  late final Box scholarBox;
  late final Box taskBox;
  late final Box flowBox;
  late final Box originalWebPageBox;
  late final Box fuseBox;
  late final Box customGpaBox;
  late final Box tombstoneBox;
  late final Box focusBox;
  late final FlutterSecureStorage secureStorage;

  Future<void> init() async {
    Hive.registerAdapter(DurationAdapter());
    Hive.registerAdapter(ScholarAdapter());
    Hive.registerAdapter(DeadlineStatusAdapter());
    Hive.registerAdapter(DeadlineTypeAdapter());
    Hive.registerAdapter(DeadlineRepeatTypeAdapter());
    Hive.registerAdapter(TaskPriorityAdapter());
    Hive.registerAdapter(SubTaskAdapter());
    Hive.registerAdapter(TaskAttachmentAdapter());
    Hive.registerAdapter(TaskCommentAdapter());
    Hive.registerAdapter(DeadlineAdapter());
    Hive.registerAdapter(PeriodTypeAdapter());
    Hive.registerAdapter(PeriodAdapter());
    Hive.registerAdapter(FuseAdapter());
    Hive.registerAdapter(CourseIdMapAdapter());
    Hive.registerAdapter(FocusSessionAdapter());
    optionsBox = await Hive.openBox(dbOptions);
    scholarBox = await Hive.openBox(dbScholar);
    taskBox = await Hive.openBox(dbTask);
    flowBox = await Hive.openBox(dbFlow);
    originalWebPageBox = await Hive.openBox(dbOriginalWebPage);
    fuseBox = await Hive.openBox(dbFuse);
    customGpaBox = await Hive.openBox(dbCustomGpa);
    tombstoneBox = await Hive.openBox(dbTombstones);
    focusBox = await Hive.openBox(dbFocus);
    secureStorage = const FlutterSecureStorage();

    // ===== P5：清掉「时间规划」时代留在 optionsBox 里的三个键 =====
    // P1 删功能时只删了访问器，值还躺在盒子里（workTime / restTime / allowTime）。
    // 一次性、幂等：有就删，没有就算了。删掉它们不会影响任何现有功能。
    for (final legacyKey in const ['workTime', 'restTime', 'allowTime']) {
      if (optionsBox.containsKey(legacyKey)) {
        await optionsBox.delete(legacyKey);
      }
    }
    // Migrate all items without groupID
    var secureStorageItems = await secureStorage.readAll(
        iOptions: const IOSOptions(
            accessibility: KeychainAccessibility.first_unlock,
            accountName: 'Celechron'));
    await Future.forEach(secureStorageItems.entries, (e) async {
      await secureStorage.delete(
          key: e.key,
          iOptions: const IOSOptions(
              accessibility: KeychainAccessibility.first_unlock,
              accountName: 'Celechron'));
      await secureStorage.write(
          key: e.key, value: e.value, iOptions: secureStorageIOSOptions);
    });
  }

  // Options
  final String dbOptions = 'dbOptions';

  /// 删除墓碑：同步合并时用来判断"这条是被删掉的"
  final String dbTombstones = 'dbTombstones';

  /// ===== P3：专注会话记录 =====
  final String dbFocus = 'dbFocus';

  /// 专注参数：工作 / 休息分钟数 + 休息时是否提醒（用户拍板默认 60 / 15）
  final String kFocusWorkMinutes = 'focusWorkMinutes';
  final String kFocusRestMinutes = 'focusRestMinutes';
  final String kFocusRestNotify = 'focusRestNotify';
  final String kGpaStrategy = 'gpaStrategy';
  final String kPushOnGradeChange = 'pushOnGradeChange';
  final String kPushOnDdlReminder = 'pushOnDdlReminder';
  // P1：默认提醒提前量（分钟）。活动与截止用它；提醒型就是那一刻本身。
  final String kReminderLeadMinutes = 'reminderLeadMinutes';
  final String kBrightnessMode = 'brightnessMode';
  /// S1：设备身份（首次读取时生成一次，之后固定）
  final String kDeviceId = 'deviceId';
  final String kCourseIdMappingList = 'courseIdMappingList';
  final String kHideHomeGpa = 'hideHomeGpa';
  final String kAsyncRefresh = 'asyncRefresh';

  Option getOption() {
    return Option(
      gpaStrategy: getGpaStrategy().obs,
      pushOnGradeChange: getPushOnGradeChange().obs,
      pushOnDdlReminder: getPushOnDdlReminder().obs,
      brightnessMode: getBrightnessMode().obs,
      courseIdMappingList: getCourseIdMappingList().obs,
      hideHomeGpa: getHideHomeGpa().obs,
      asyncRefresh: getAsyncRefresh().obs,
    );
  }

  /// 默认提醒提前量（分钟）：活动锚开始时间、截止锚截止时间，各自再提前这么多。
  /// 提醒型不受影响（就是那一刻）；备忘型不调度。
  int getReminderLeadMinutes() {
    if (optionsBox.get(kReminderLeadMinutes) == null) {
      optionsBox.put(kReminderLeadMinutes, 30);
    }
    return optionsBox.get(kReminderLeadMinutes);
  }

  void setReminderLeadMinutes(int minutes) {
    optionsBox.put(kReminderLeadMinutes, minutes);
  }

  // ============================================== S1：多端同步要用的东西

  /// ===== 设备身份 =====
  ///
  /// 首次读取时生成一次、之后固定。用途：同步时告诉对方「这份数据来自哪台设备」，
  /// 面板上显示「最后同步来自 X」，以后排查「谁把我这条改了」也有据可依。
  /// 只存本地，**不会**被对方的 deviceId 覆盖（见 DataMerge 的调用方）。
  String getDeviceId() {
    final existing = optionsBox.get(kDeviceId);
    if (existing is String && existing.isNotEmpty) return existing;
    final generated = const Uuid().v4();
    optionsBox.put(kDeviceId, generated);
    return generated;
  }

  /// ===== 密钥（只走白名单，见 data_sync.dart 的 SyncSecrets）=====
  ///
  /// 存系统密钥库（`FlutterSecureStorage`），与 AI key 同一套设施。
  /// 命名空间前缀 `sync:` 避免与别的键撞车。
  static const String _syncSecretPrefix = 'sync:';

  Future<String> getSyncSecret(String key) async {
    if (!SyncSecrets.allowed.contains(key)) return '';
    try {
      return await secureStorage.read(key: '$_syncSecretPrefix$key') ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<void> setSyncSecret(String key, String value) async {
    if (!SyncSecrets.allowed.contains(key)) return; // 机制上挡住非白名单键
    try {
      if (value.isEmpty) {
        await secureStorage.delete(key: '$_syncSecretPrefix$key');
      } else {
        await secureStorage.write(key: '$_syncSecretPrefix$key', value: value);
      }
    } catch (_) {}
  }

  /// 收集要同步出去的密钥（AI key 从 AiConfig 读，其余从密钥库读）
  Future<Map<String, String>> getSyncSecrets() async {
    final result = <String, String>{};
    try {
      if (AiConfig.apiKey.isNotEmpty) {
        result[SyncSecrets.aiApiKey] = AiConfig.apiKey;
      }
    } catch (_) {}
    for (final key in SyncSecrets.allowed) {
      if (key == SyncSecrets.aiApiKey) continue;
      final value = await getSyncSecret(key);
      if (value.isNotEmpty) result[key] = value;
    }
    return SyncSecrets.filter(result);
  }

  /// 应用对方同步过来的密钥（只认白名单 ✓）
  Future<void> applySyncSecrets(Map<String, String> secrets) async {
    final allowed = SyncSecrets.filter(secrets);
    for (final entry in allowed.entries) {
      if (entry.key == SyncSecrets.aiApiKey) {
        // AI key 写进 AiConfig 自己的存储，这样 AI 功能立刻能用
        try {
          await AiConfig.setApiKey(entry.value);
        } catch (_) {}
      } else {
        await setSyncSecret(entry.key, entry.value);
      }
    }
  }

  // ------------------------------------------------------------ P3：专注

  /// 工作时长（分钟），默认 60
  int getFocusWorkMinutes() {
    if (optionsBox.get(kFocusWorkMinutes) == null) {
      optionsBox.put(kFocusWorkMinutes, 60);
    }
    return optionsBox.get(kFocusWorkMinutes);
  }

  void setFocusWorkMinutes(int minutes) {
    optionsBox.put(kFocusWorkMinutes, minutes);
  }

  /// 休息时长（分钟），默认 15
  int getFocusRestMinutes() {
    if (optionsBox.get(kFocusRestMinutes) == null) {
      optionsBox.put(kFocusRestMinutes, 15);
    }
    return optionsBox.get(kFocusRestMinutes);
  }

  void setFocusRestMinutes(int minutes) {
    optionsBox.put(kFocusRestMinutes, minutes);
  }

  /// 休息开始时是否弹一条通知提醒你起来走走（默认开）
  bool getFocusRestNotify() {
    if (optionsBox.get(kFocusRestNotify) == null) {
      optionsBox.put(kFocusRestNotify, true);
    }
    return optionsBox.get(kFocusRestNotify);
  }

  void setFocusRestNotify(bool value) {
    optionsBox.put(kFocusRestNotify, value);
  }

  /// 全部专注会话（按开始时间倒序）
  List<FocusSession> getFocusSessions() {
    final list = focusBox.values
        .whereType<FocusSession>()
        .toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return list;
  }

  /// 还没正常结束的会话（App 被杀掉时留下的），正常情况最多一条
  List<FocusSession> getUnfinishedFocusSessions() =>
      getFocusSessions().where((s) => s.isRunning).toList();

  Future<void> saveFocusSession(FocusSession session) async {
    await focusBox.put(session.uid, session);
  }

  Future<void> deleteFocusSession(String uid) async {
    await focusBox.delete(uid);
  }

  GpaStrategy getGpaStrategy() {
    if (optionsBox.get(kGpaStrategy) == null) {
      optionsBox.put(kGpaStrategy, 0);
    }
    return GpaStrategy.values[optionsBox.get(kGpaStrategy)];
  }

  Future<void> setGpaStrategy(GpaStrategy gpaStrategy) async {
    await optionsBox.put(kGpaStrategy, gpaStrategy.index);
  }

  bool getPushOnGradeChange() {
    if (optionsBox.get(kPushOnGradeChange) == null) {
      optionsBox.put(kPushOnGradeChange, true);
    }
    return optionsBox.get(kPushOnGradeChange);
  }

  Future<void> setPushOnGradeChange(bool pushOnGradeChange) async {
    await optionsBox.put(kPushOnGradeChange, pushOnGradeChange);
  }

  bool getPushOnDdlReminder() {
    if (optionsBox.get(kPushOnDdlReminder) == null) {
      optionsBox.put(kPushOnDdlReminder, true);
    }
    return optionsBox.get(kPushOnDdlReminder);
  }

  Future<void> setPushOnDdlReminder(bool pushOnDdlReminder) async {
    await optionsBox.put(kPushOnDdlReminder, pushOnDdlReminder);
  }

  Future<void> setBrightnessMode(BrightnessMode brightness) async {
    await optionsBox.put(kBrightnessMode, brightness.index);
  }

  BrightnessMode getBrightnessMode() {
    if (optionsBox.get(kBrightnessMode) == null) {
      optionsBox.put(kBrightnessMode, BrightnessMode.system.index);
    }
    return BrightnessMode.values[optionsBox.get(kBrightnessMode)];
  }

  bool getHideHomeGpa() {
    if (optionsBox.get(kHideHomeGpa) == null) {
      optionsBox.put(kHideHomeGpa, false);
    }
    return optionsBox.get(kHideHomeGpa);
  }

  Future<void> setHideHomeGpa(bool hideHomeGpa) async {
    await optionsBox.put(kHideHomeGpa, hideHomeGpa);
  }

  // 异步刷新：数据边刷出边显示。默认关闭，即等全部刷完后一次性更新
  bool getAsyncRefresh() {
    if (optionsBox.get(kAsyncRefresh) == null) {
      optionsBox.put(kAsyncRefresh, false);
    }
    return optionsBox.get(kAsyncRefresh);
  }

  Future<void> setAsyncRefresh(bool asyncRefresh) async {
    await optionsBox.put(kAsyncRefresh, asyncRefresh);
  }

  List<CourseIdMap> getCourseIdMappingList() {
    if (optionsBox.get(kCourseIdMappingList) == null) {
      optionsBox.put(kCourseIdMappingList, <CourseIdMap>[]);
    }
    return List<CourseIdMap>.from(optionsBox.get(kCourseIdMappingList));
  }

  Future<void> setCourseIdMappingList(
      List<CourseIdMap> courseIdMappingList) async {
    await optionsBox.put(kCourseIdMappingList, courseIdMappingList);
  }

  // Flow
  final String dbFlow = 'dbFlow';
  final String kFlowList = 'flowList';
  final String kFlowListUpdateTime = 'flowListUpdateTime';

  List<Period> getFlowList() {
    return List<Period>.from(flowBox.get(kFlowList) ?? <Period>[]);
  }

  Future<void> setFlowList(List<Period> flowList) async {
    await flowBox.put(kFlowList, flowList);
  }

  DateTime getFlowListUpdateTime() {
    return flowBox.get(kFlowListUpdateTime) ??
        DateTime.fromMicrosecondsSinceEpoch(0);
  }

  Future<void> setFlowListUpdateTime(DateTime flowListUpdateTime) async {
    await flowBox.put(kFlowListUpdateTime, flowListUpdateTime);
  }

  // Task
  final String dbTask = 'dbDeadline';
  final String kTaskList = 'deadlineList';
  final String kTaskListUpdateTime = 'deadlineListUpdateTime';

  List<Task> getTaskList() {
    return List<Task>.from(taskBox.get(kTaskList) ?? <Task>[]);
  }

  Future<void> setTaskList(List<Task> deadlineList) async {
    await taskBox.put(kTaskList, deadlineList);
  }

  DateTime getTaskListUpdateTime() {
    return taskBox.get(kTaskListUpdateTime) ??
        DateTime.fromMicrosecondsSinceEpoch(0);
  }

  Future<void> setTaskListUpdateTime(DateTime deadlineListUpdateTime) async {
    await taskBox.put(kTaskListUpdateTime, deadlineListUpdateTime);
  }

  // Scholar
  final String dbScholar = 'dbUser';
  final String kUsername = 'username';
  final String kPassword = 'password';

  Future<Scholar> getScholar() async {
    var scholar = scholarBox.get('user', defaultValue: Scholar());
    await Future.wait([
      secureStorage
          .read(key: kUsername, iOptions: secureStorageIOSOptions)
          .then((value) {
        if (value != null) scholar.username = value;
      }),
      secureStorage
          .read(key: kPassword, iOptions: secureStorageIOSOptions)
          .then((value) {
        if (value != null) scholar.password = value;
      })
    ]);
    scholar.db = this;
    return scholar;
  }

  Future<void> setScholar(Scholar scholar) async {
    await Future.wait([
      scholarBox.put('user', scholar),
      secureStorage.write(
          key: kUsername,
          value: scholar.username,
          iOptions: secureStorageIOSOptions),
      secureStorage.write(
          key: kPassword,
          value: scholar.password,
          iOptions: secureStorageIOSOptions)
    ]);
  }

  Future<void> removeScholar() async {
    await Future.wait([
      scholarBox.delete('user'),
      secureStorage.delete(key: kUsername, iOptions: secureStorageIOSOptions),
      secureStorage.delete(key: kPassword, iOptions: secureStorageIOSOptions)
    ]);
  }

  // Original Web Page
  final String dbOriginalWebPage = 'dbOriginalWebPage';

  String? getCachedWebPage(String key) {
    return originalWebPageBox.get(key);
  }

  Future<void> setCachedWebPage(String key, String value) async {
    await originalWebPageBox.put(key, value);
  }

  Future<void> removeCachedWebPage(String key) async {
    await originalWebPageBox.delete(key);
  }

  Future<void> removeAllCachedWebPage() async {
    await originalWebPageBox.clear();
  }

  // Fuse
  final String dbFuse = 'dbFuse';

  Fuse getFuse() {
    return fuseBox.get('fuse') ?? Fuse();
  }

  Future<void> setFuse(Fuse fuse) async {
    await fuseBox.put('fuse', fuse);
  }

  final String dbCustomGpa = 'dbCustomGpa';
  final String dbWeightedGpa = 'dbWeightedGpa';

  Map<String, bool> getCustomGpa() {
    return Map<String, bool>.from(customGpaBox.get('selectList') ?? {});
  }

  Future<void> setCustomGpa(Map<String, bool> selectList) async {
    await customGpaBox.put('selectList', selectList);
  }

  /// 获取加权绩点的加权比例数据
  ///
  /// 返回值：
  /// - Map<String, double>: key为grade.id，value为加权比例（默认1.0）
  Map<String, double> getWeightedGpa() {
    final data = customGpaBox.get('weightedGpa') as Map?;
    if (data == null) {
      return {};
    }
    return Map<String, double>.from(data.map(
        (key, value) => MapEntry(key.toString(), (value as num).toDouble())));
  }

  /// 保存加权绩点的加权比例数据
  Future<void> setWeightedGpa(Map<String, double> weightedMap) async {
    await customGpaBox.put('weightedGpa', weightedMap);
  }
}
