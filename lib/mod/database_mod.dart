import 'package:celechron/database/database_helper.dart';
import 'package:celechron/model/tombstone.dart';
import 'package:celechron/model/option.dart';
import 'package:get/get.dart';

/// ============ 魔改在数据库层新增的读写（墓碑 / 标签库 / 配色 / 提醒方式）============
///
/// 上游的 `lib/database/database_helper.dart` 也被持续维护，所以这些成员不再写在
/// 那个类里，而是用 extension 挂在它上面——`optionsBox` / `tombstoneBox` 都是
/// public 字段，extension 能直接访问。
/// 上游文件里只留 4 行 adapter 注册与 1 行开箱。
/// 删除墓碑的 Hive key
const String kTombstones = 'tombstones';
const String kReminderModeKey = 'reminderMode';
const String kAlarmThemeKey = 'alarmTheme';
const String kTagLibraryKey = 'tagLibrary';
const String kTagColorsKey = 'tagColors';

/// 专注时自动免打扰：开关本身（默认开）
const String kFocusDndKey = 'focusDndEnabled';

/// 专注是否自动归属到课程（默认开，见 [DatabaseModExt.getFocusAttributeToCourse]）
const String kFocusAttributeToCourseKey = 'focusAttributeToCourse';

/// 开启免打扰**之前**的系统档位。
///
/// 落盘是为了防「App 被杀导致手机永久静音」：下次启动时如果发现这个键还在，
/// 说明我们改过却没来得及还原，就立刻还原（见 `DoNotDisturb.restoreIfStale`）。
const String kDndSavedFilterKey = 'dndSavedFilter';

/// 一次性迁移的标记：避免每次启动都强行打开「异步刷新」
const String kAsyncRefreshMigratedKey = 'asyncRefreshDefaultOnMigrated';

/// 「上次登录用的账号密码」——**故意与 username/password 分开存**。
///
/// 为什么：退出登录走的是 `removeScholar()`，它会把 `username`/`password`
/// 两个键从系统密钥库删掉，于是退出后登录页是空的、每次都得重打一遍。
/// 用户要求「主动退出之后依然能预填账号密码」，所以这里另存一份：
/// **退出登录不删它**，只有「忘记账号」时才清。
///
/// 存的是同一套系统密钥库（Keystore / Keychain），不落明文数据库。
const String kLastUsernameKey = 'mod_last_username';
const String kLastPasswordKey = 'mod_last_password';

extension DatabaseModExt on DatabaseHelper {
  // ===== 记住上次登录的账号密码（退出后仍可预填）=====

  /// 数据库副本的键（与密钥库那份同名，方便对照）
  static const String kLastUsernameDbKey = 'lastUsername';
  static const String kLastPasswordDbKey = 'lastPassword';

  /// 登录成功时调用：把这次用的账号密码另存一份，供以后预填。
  ///
  /// **两处都写**：系统密钥库（首选，加密）+ 数据库（回退副本）。
  /// 为什么要有数据库那份：某些 ROM 在**覆盖安装后读密钥库会返回 null**
  /// （用户反馈的"更新后预填失效"就是这么来的，见 WHATS_NEW 11.11）。
  /// 用户拍板要"永远能预填"，所以接受这份可解形式的副本落在应用私有目录里。
  Future<void> rememberAccount(String username, String password) async {
    if (username.isEmpty && password.isEmpty) return;
    try {
      await secureStorage.write(key: kLastUsernameKey, value: username);
      await secureStorage.write(key: kLastPasswordKey, value: password);
    } catch (_) {
      // 密钥库不可用时不影响登录本身，下面那份副本仍然会写成功
    }
    try {
      await accountBox.put(kLastUsernameDbKey, username);
      await accountBox.put(kLastPasswordDbKey, password);
    } catch (_) {
      // 数据库也写不进去就算了，至少不阻塞登录
    }
  }

  /// 读回上次登录的账号密码（拿不到就返回空串）。
  ///
  /// 顺序：**先密钥库，读不到再退回数据库副本**。
  /// 这样正常情况下用的仍是加密存储，只有在密钥库"失忆"时才会用到副本。
  Future<({String username, String password})> rememberedAccount() async {
    var username = '';
    var password = '';
    try {
      username = await secureStorage.read(key: kLastUsernameKey) ?? '';
      password = await secureStorage.read(key: kLastPasswordKey) ?? '';
    } catch (_) {
      // 密钥库读挂了（正是我们要兜住的情况）→ 下面走副本
    }
    if (username.isEmpty || password.isEmpty) {
      try {
        final fallbackUsername =
            accountBox.get(kLastUsernameDbKey) as String? ?? '';
        final fallbackPassword =
            accountBox.get(kLastPasswordDbKey) as String? ?? '';
        if (username.isEmpty) username = fallbackUsername;
        if (password.isEmpty) password = fallbackPassword;
      } catch (_) {
        // 副本也读不到就只能让用户手打了
      }
    }
    return (username: username, password: password);
  }

  /// 用户主动「忘记账号」时清掉（退出登录**不**调用它）——两处一起清。
  Future<void> forgetAccount() async {
    try {
      await secureStorage.delete(key: kLastUsernameKey);
      await secureStorage.delete(key: kLastPasswordKey);
    } catch (_) {}
    try {
      await accountBox.delete(kLastUsernameDbKey);
      await accountBox.delete(kLastPasswordDbKey);
    } catch (_) {}
  }

  // ===== 一次性迁移：把「异步刷新」改成默认开启 =====

  /// 用户反馈：「刷新的时候很卡，都是退出重进才能刷新好，网络请求容易超时」。
  ///
  /// 排查结论：抓取本身是**并行**的（`Future.wait`），单请求超时 8 秒、
  /// 最多重试一次 —— 架构没问题。真正的原因是**异步刷新默认关闭**：
  /// 界面要等所有模块全部刷完（最坏接近 20 秒）才一次性更新，看着就像卡死。
  ///
  /// 所以改为默认开启（数据边刷出来边显示），设置里的开关保留，
  /// 用户自己关掉之后不会再被这个迁移打开（靠 [kAsyncRefreshMigratedKey] 记一次）。
  Future<void> migrateAsyncRefreshDefault() async {
    if (optionsBox.get(kAsyncRefreshMigratedKey) == true) return;
    await optionsBox.put(kAsyncRefreshMigratedKey, true);
    if (!getAsyncRefresh()) {
      await setAsyncRefresh(true);
    }
    // ⚠️ 只改数据库还不够：界面上的开关读的是 `Option` 里那个 Rx
    // （它在数据库打开时就创建好了，早于这次迁移），不同步的话
    // 设置页会一直显示"关着"，用户以为没生效。
    try {
      if (Get.isRegistered<Option>(tag: 'option')) {
        Get.find<Option>(tag: 'option').asyncRefresh.value = true;
      }
    } catch (_) {
      // 极早期启动时 Option 还没注册，下一次启动也会读到新值
    }
  }

  // 专注时自动免打扰

  bool getFocusDndEnabled() {
    final value = optionsBox.get(kFocusDndKey);
    if (value is bool) return value;
    return true; // 默认开：这正是这个功能的意义
  }

  Future<void> setFocusDndEnabled(bool enabled) async {
    await optionsBox.put(kFocusDndKey, enabled);
  }

  // ===== 专注归属到课程（默认开）=====
  //
  // 用户 2026-09-14 拍板：自由专注若**开始时间**落在某节课里，就算那门课的专注，
  // 并且做成开关。口径与实现在 `course_mount_store.dart` 的 [courseIdForFocusStart]。

  bool getFocusAttributeToCourse() {
    final value = optionsBox.get(kFocusAttributeToCourseKey);
    if (value is bool) return value;
    return true; // 默认开：这个功能的全部意义就是"自动记上"，还得手动开就没意义了
  }

  Future<void> setFocusAttributeToCourse(bool enabled) async {
    await optionsBox.put(kFocusAttributeToCourseKey, enabled);
  }

  int? getDndSavedFilter() {
    final value = optionsBox.get(kDndSavedFilterKey);
    return value is int ? value : null;
  }

  Future<void> setDndSavedFilter(int filter) async {
    await optionsBox.put(kDndSavedFilterKey, filter);
  }

  Future<void> clearDndSavedFilter() async {
    await optionsBox.delete(kDndSavedFilterKey);
  }

  // 提醒方式：0 = 通知（横幅+响铃），1 = 闹钟模式

  int getReminderMode() {
    final value = optionsBox.get(kReminderModeKey);
    if (value is int) return value;
    return 0;
  }

  Future<void> setReminderMode(int mode) async {
    await optionsBox.put(kReminderModeKey, mode);
  }

  // 闹钟配色

  String getAlarmTheme() {
    final value = optionsBox.get(kAlarmThemeKey);
    if (value is String && value.isNotEmpty) return value;
    return 'tianyi';
  }

  Future<void> setAlarmTheme(String id) async {
    await optionsBox.put(kAlarmThemeKey, id);
  }

  // 标签库：用户用过的标签，下次可以一键复用

  List<String> getTagLibrary() {
    if (optionsBox.get(kTagLibraryKey) == null) {
      optionsBox.put(kTagLibraryKey, <String>[]);
    }
    return List<String>.from(optionsBox.get(kTagLibraryKey));
  }

  /// 写入标签库；默认拒绝空列表（防止意外清空），只有用户在标签管理里
  /// 主动删光时才传 allowEmpty: true。
  Future<void> setTagLibrary(List<String> tags,
      {bool allowEmpty = false}) async {
    if (tags.isEmpty && !allowEmpty) return;
    await optionsBox.put(kTagLibraryKey, tags);
  }

  // 标签颜色：标签名 -> 颜色值（ARGB int）

  Map<String, int> getTagColors() {
    final raw = optionsBox.get(kTagColorsKey);
    if (raw == null) return <String, int>{};
    return Map<String, int>.from(raw as Map);
  }

  Future<void> setTagColors(Map<String, int> colors) async {
    await optionsBox.put(kTagColorsKey, colors);
  }

  /// 标签颜色（没设过返回 null，由界面决定默认色）
  int? getTagColor(String tag) => getTagColors()[tag];

  Future<void> setTagColor(String tag, int? color) async {
    final colors = getTagColors();
    if (color == null) {
      colors.remove(tag);
    } else {
      colors[tag] = color;
    }
    await setTagColors(colors);
  }

  // 删除墓碑
  List<TaskTombstone> getTombstones() {
    final raw = tombstoneBox.get(kTombstones);
    if (raw is! List) return <TaskTombstone>[];
    final result = <TaskTombstone>[];
    for (final item in raw) {
      if (item is Map) {
        final tombstone =
            TaskTombstone.fromJson(Map<String, dynamic>.from(item));
        if (tombstone != null) result.add(tombstone);
      }
    }
    return result;
  }

  Future<void> setTombstones(List<TaskTombstone> tombstones) async {
    await tombstoneBox.put(
        kTombstones, tombstones.map((t) => t.toJson()).toList());
  }

  /// 记录一批待办被删除（同 uid 只保留最新时间）
  Future<void> addTombstones(Iterable<String> uids, {DateTime? at}) async {
    if (uids.isEmpty) return;
    final now = at ?? DateTime.now();
    final map = <String, TaskTombstone>{
      for (final tombstone in getTombstones()) tombstone.uid: tombstone,
    };
    for (final uid in uids) {
      map[uid] = TaskTombstone(uid: uid, deletedAt: now);
    }
    await setTombstones(map.values.toList());
  }

  // Scholar
}
