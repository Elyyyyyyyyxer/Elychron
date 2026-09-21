import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:celechron/model/task.dart';
import 'package:celechron/worker/fuse.dart';
import 'package:celechron/model/scholar.dart';
import 'package:celechron/model/period.dart';
import 'package:celechron/model/option.dart';
import 'package:celechron/utils/utils.dart';
import 'adapters/duration_adapter.dart';
import 'adapters/scholar_adapter.dart';
import 'package:celechron/model/focus_session.dart';
import 'dart:async';
import 'dart:io';

import 'package:celechron/utils/data_sync.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path_provider/path_provider.dart';
import 'package:celechron/mod/ai/deepseek.dart';
import 'package:uuid/uuid.dart';
import 'adapters/deadline_adapter.dart';
import 'adapters/period_adapter.dart';
import 'adapters/fuse_adapter.dart';
import 'adapters/course_id_map_adapter.dart';
import 'adapters/focus_adapter.dart';
import 'package:celechron/mod/focus_device.dart';
import 'package:celechron/mod/lan_sync_client.dart';

/// 启动路标总开关（和 `main.dart` 里那个是**各自文件私有**的同名开关，互不干扰）。
///
/// `[boot] 4.1…4.5` 只是"开到第几个盒子了"的路标，发布版保持 false。
/// 排查启动问题时改成 true 重新构建；**异常日志（自愈/删锁/留档/抢救）不受它控制**，
/// 那些继续用 `debugPrint` 原样打， 它们只在真出事时出现。
bool _bootProbesEnabled = false;

/// 打一条启动路标（受 [_bootProbesEnabled] 控制）。
void _bootProbe(String message) {
  if (_bootProbesEnabled) debugPrint(message);
}

/// 密钥库（FlutterSecureStorage）调用的**保险丝**：超时就当没有，绝不阻塞启动。
///
/// ===== 为什么要这个 =====
///
/// 用户实测（2026-09-16）：更新之后 Elychron 打不开了，
/// 现象是**进程活着、日志里没有任何异常、first frame 永远不来**，
/// 系统侧记为 `AppBootFail` + 一条 ANR：说明启动路径被某个 await 卡死了。
///
/// 嫌疑最集中的就是密钥库：这台 ROM（华为）在**覆盖安装后**密钥库会"失忆"，
/// 我们之前已经确认过它读回 null（就是"显示已登录但没有学号"那个老毛病），
/// 而 `init()` 里那段迁移写的是 `await secureStorage.readAll(...)`，
/// **一个没有 try、没有超时的 await**，平台侧一旦不返回，`main()` 就永远走不到 `runApp`。
///
/// 所以统一加保险：**最多等 3 秒**，超时或抛错都当"读不到"。
/// 密钥库再怎么坏，也不能让 App 打不开。
Future<T?> secureStorageOrNull<T>(Future<T> future) async {
  try {
    return await future.timeout(const Duration(seconds: 3));
  } catch (_) {
    return null;
  }
}

/// 一次性抢救：从 `.damaged-*` 备份里把待办捞回来。
///
/// 原理：待办盒子**每次保存都写一整份列表**，所以**最后一个能解码的帧里装的就是
/// 完整的待办列表**， 只要从文件尾往前找第一个读得动的帧，把它的值写回新盒子即可。
/// 丢的只是"坏帧之后的那几次保存"，历史数据绝大部分还在。
///
/// 安全前提（三条都满足才动手）：
///   1. 只做一次（optionsBox 里的标记）；
///   2. **当前待办盒子是空的**才恢复， 已经有数据时绝不覆盖；
///   3. 只读备份文件，**绝不修改或删除它**。
///
/// 放在 `runApp` 之后跑（不 await）：抢救可能要扫一会儿，但**不能挡住界面**。
Future<int> salvageTasksFromBackupOnce(
    Directory directory, Box taskBox, Box options) async {
  // 键里带版本号：抢救逻辑每改一次就 +1。否则"上一次那版用掉了标记"会把新版挡住
  //， 这件事已经坑了我三次（盒子非空误判、只扫尾部 200 帧、以及现在这次）。
  const flagKey = 'salvagedTaskBox_v4_20260916';
  try {
    if (options.get(flagKey) == true) return 0;
    // 只在"当前一条待办都没有"时才动手， 有数据就一条都不碰，
    // 而且**不设标记**（万一是别的原因导致空列表，下次还有机会）。
    final current = taskBox.get('deadlineList');
    if (current is List && current.isNotEmpty) return 0;
    final backups = <File>[];
    await for (final entity in directory.list()) {
      if (entity is File && entity.path.contains('.hive.damaged-')) {
        backups.add(entity);
      }
    }
    if (backups.isEmpty) {
      await options.put(flagKey, true);
      debugPrint('[boot] salvage: no backups found');
      return 0;
    }
    // 最新的那个备份（时间戳在文件名里）
    backups.sort((a, b) => a.path.compareTo(b.path));
    final backup = backups.last;
    debugPrint(
        '[boot] salvage: backups=${backups.length} newest=${backup.path}');

    // ===== 让 Hive 自己去读它 =====
    //
    // 前面试过"自己按帧扫描"，但那份备份只有 1 帧（Hive 压缩过），而它恰好是坏帧，
    // 扫不出"好帧"来。其实数据**完好无损**：坏的只是"字段计数写了 23、实际写了 24"，
    // 而这一点已经在 `DeadlineAdapter.read` 里做了兼容（读完字段后偷看一个字节，
    // 是 26 就把多出来的那一对吃回去）。
    //
    // 所以这里不自己解析了：**把备份复制成一个临时盒子，交给 Hive 打开并读出
    // `deadlineList`**， CRC 校验、类型注册、列表还原全由它来做，最不容易错。
    // 原备份一个字都不改；临时盒子用完就删。
    final tempName = 'dbsalvage';
    final tempFile = File(boxFilePath(directory, tempName));
    try {
      await tempFile.writeAsBytes(await backup.readAsBytes(), flush: true);
      final temp = await Hive.openBox(tempName);
      final value = temp.get('deadlineList');
      if (value is List && value.isNotEmpty && value.first is Task) {
        final tasks = <Task>[for (final item in value) item as Task];
        await taskBox.put('deadlineList', tasks);
        await options.put(flagKey, true);
        debugPrint('[boot] salvage: OK tasks=${tasks.length}');
        return tasks.length;
      }
      debugPrint(
          '[boot] salvage: temp box has no usable list (type=${value.runtimeType})');
    } catch (error) {
      debugPrint('[boot] salvage: temp box read failed: $error');
    } finally {
      try {
        await Hive.deleteBoxFromDisk(tempName);
      } catch (_) {}
    }
    // 走到这里说明连"兼容读取"都没捞出来：把标记用掉，别每次启动都重扫
    await options.put(flagKey, true);
    return 0;
  } catch (error) {
    debugPrint('[boot] salvage failed: $error');
    return 0;
  }
}

/// 盒子在磁盘上的文件名。
///
/// ⚠️ Hive 会把盒子名**转成小写**再落盘（`HiveImpl` 内部用 `name.toLowerCase()`），
/// 所以 `dbDeadline` 对应的文件是 **`dbdeadline.hive`**，不是 `dbDeadline.hive`。
/// 我的自救流程第一版就是栽在这里：一直按原样大小写找文件 → 永远"文件不存在" →
/// 静默什么都不做（日志里只看到"留档并挪走"却没有任何实际动作）。
String boxFilePath(Directory directory, String name) =>
    '${directory.path}/${name.toLowerCase()}.hive';

/// 打开一个 Hive 盒子，**带自救**。
///
/// 见 [openBoxResilientImpl] 里的注释：这里只保留一个"optionsBox 是否已就绪"的开关，
/// 因为自我修复要靠 optionsBox 记进度，而它自己要先开起来。
///
/// ===== 为什么需要它（2026-09-16 实测的"App 打不开"）=====
///
/// Hive 用 `<box>.lock` 文件做互斥，而 `openBox` 在拿不到锁时会**无限等待**。
/// 我们的 App 有不止一个 isolate 会开同一批盒子：UI 进程、WorkManager 后台刷新、
/// （之前还有桌面小组件的 Glance 会话）。只要有一个把锁拿着不放，
/// 后台 isolate 卡住、或者上一轮被系统杀掉时留下了死锁，
/// **UI 进程就会永远卡在启动**，用户看到的就是"App 打不开"：
/// 进程活着、日志里没有任何异常、first frame 永远不来（系统记 AppBootFail + ANR）。
///
/// 当时的探针输出停在 `[boot] 4.1 optionsBox` 之后，也就是**卡在
/// `openBox(dbUser)` 上**，前面 optionsBox 一秒不到就开好了， 完美吻合"锁被占"。
///
/// 所以这里：先正常开，最多等 5 秒；**超时就删掉锁文件再试一次**。
/// 理由：启动这一刻我们这一侧没有别的写手，锁本来只是防并发写；
/// 让用户**完全打不开 App** 的代价，远大于极小概率的并发写风险。
/// 删锁会打日志，方便以后回看这件事多久发生一次。
Future<Box> openBoxResilientImpl(
    String name, Directory directory, Box? options, String optionsName) async {
  // ===== 自我修复：上一次启动卡在哪个盒子上，这次就先把它留档挪走 =====
  //
  // 为什么这么做：Hive 会**缓存"打开失败"的结果**，所以"先试开、失败再修"这条路
  // 根本走不通（我第一次修复就是这么白忙的：栈每次都指向同一行）；
  // 而"逐帧扫描"在几十上百 MB 的盒子上会超出系统给的启动时间，进程会被直接掐掉。
  //
  // 于是换成**确定性**的做法：开机时先记一笔"正在开 X"，开成功了再记一笔"X 开好了"。
  //   下次启动只要看到"记了正在开、却没有开好" → 说明上次就是死在 X 上 →
  //   **先把它整份留档（.damaged-<时间戳>）再挪走**，让这次能开起来。
  // 数据一条不删（备份都在），而且只影响真正出事的那个盒子。
  if (options != null && name != optionsName) {
    final intent = options.get('openIntent:$name');
    final done = options.get('openDone:$name');
    if (intent != null && intent != done) {
      debugPrint('[boot] 上次卡在 $name → 留档并挪走');
      await _setBoxAside(name, directory);
    }
    await options.put(
        'openIntent:$name', DateTime.now().millisecondsSinceEpoch);
  }

  try {
    final box = await Hive.openBox(name).timeout(const Duration(seconds: 8));
    if (options != null && name != optionsName) {
      await options.put('openDone:$name', options.get('openIntent:$name'));
    }
    return box;
  } on TimeoutException {
    // 拿不到锁（另一个 isolate 把锁握着不放）→ 删锁重试一次
    debugPrint('[boot] 打开 $name 超时（锁被占）→ 删锁重试');
    try {
      final lock = File('${boxFilePath(directory, name)}.lock');
      if (await lock.exists()) {
        await lock.delete();
        debugPrint('[boot] 已删除 $name.lock');
      }
    } catch (error) {
      debugPrint('[boot] 删锁失败：$error');
    }
    final box = await Hive.openBox(name).timeout(const Duration(seconds: 10));
    if (options != null && name != optionsName) {
      await options.put('openDone:$name', options.get('openIntent:$name'));
    }
    return box;
  } catch (error) {
    // 打开就抛错（典型是坏帧）→ 留档挪走，再开一次（新文件，必然能开）
    debugPrint('[boot] 打开 $name 抛错：$error → 留档挪走后重开');
    await _setBoxAside(name, directory);
    final box = await Hive.openBox(name).timeout(const Duration(seconds: 10));
    if (options != null && name != optionsName) {
      await options.put('openDone:$name', options.get('openIntent:$name'));
    }
    return box;
  }
}

/// 把某个盒子的文件**留档后挪走**：`<name>.hive` → `<name>.hive.damaged-<时间戳>`
/// 再改名成 `<name>.hive.unreadable-<时间戳>`。原文件**永远不删**。
Future<void> _setBoxAside(String name, Directory directory) async {
  try {
    final file = File(boxFilePath(directory, name));
    if (!await file.exists()) {
      debugPrint('[boot] ${file.path} 不存在，无需挪走');
      return;
    }
    final stamp = DateTime.now().millisecondsSinceEpoch;
    await file.copy('${file.path}.damaged-$stamp');
    await file.rename('${file.path}.unreadable-$stamp');
    debugPrint('[boot] $name 已留档并挪走（.damaged-$stamp）');
  } catch (error) {
    debugPrint('[boot] 挪走 $name 失败：$error');
  }
}

/// 一次性把"已知写坏的待办盒子"留档后挪走（只在第一次启动新版时做一次）。
///
/// 为什么用标记位而不是"试开失败再修"：
///   · Hive 会缓存打开失败的 future，先试开就没法再抢救了；
///   · 逐帧扫描在几十上百 MB 的盒子上会超出系统给的启动时间，进程会被掐掉。
/// 所以宁可在打开之前就动手：**App 必须能打开**，数据留在 `.damaged` 备份里随后抢救。
Future<void> rescueDamagedTaskBoxOnce(
    Directory directory, Box options, String boxName) async {
  const flagKey = 'rescuedTaskBox20260916';
  try {
    if (options.get(flagKey) == true) return;
    final file = File(boxFilePath(directory, boxName));
    if (await file.exists()) {
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final backup = File('${file.path}.damaged-$stamp');
      await file.copy(backup.path);
      await file.rename('${file.path}.unreadable-$stamp');
      debugPrint('[boot] 待办盒子已留档并挪走：${backup.path}');
    }
    await options.put(flagKey, true);
  } catch (error) {
    debugPrint('[boot] 挪走待办盒子失败：$error');
  }
}

// ===== 关于"自己按帧扫描修复"这段历史（代码已删，教训留在这里）=====
//
// 2026-09-16 处理App 打不开时，我写过两版"自己扫帧"的修复，都没成功，代码已删。
// 写清楚是为了**以后别再来一遍**：
//
//   · 第一版：`readAsBytes()` 把整个盒子读进内存，再逐帧做"截断 + 试开盒子"二分。
//     待办盒子**每次保存都写一整份列表**，攒一晚上就是几十上百 MB，
//     一次读完直接超出系统给的启动时间，进程被判 `AppBootFail` 掐掉
//     （日志停在"体检"之前，什么都看不到）。**任何时候都别把整个 .hive 读进内存。**
//   · 第二版：只从文件尾往回扫 50 帧，找"最后一个能解码的好帧"。
//     可是那份备份被 Hive 压缩过，**整个文件只有 1 帧**，而它恰好就是坏的，
//     扫不出任何好帧，功能等于没有。
//
// 最后真正管用的是另外两条路：
//   ① `DeadlineAdapter.read` 里的**兼容读取**（把多写出来的那一对字节吃回去）；
//   ② 把备份复制成临时盒子，**交给 Hive 自己 `openBox` 解析**
//      （见 `salvageTasksFromBackupOnce`）。
// 结论：**不要自己实现 Hive 的帧解析**，让 Hive 自己去读。

class DatabaseHelper {
  /// optionsBox 是否已经开好（自我修复靠它记进度，所以它开好之前不能读 optionsBox，
  /// 用普通 bool 而不是去碰 `late` 字段，读未初始化的 late 字段会抛 LateInitializationError）。
  bool _optionsOpen = false;

  /// 打开盒子的实例入口（自我修复要靠 optionsBox 记进度，所以只有它开好之后才启用）。
  Future<Box> openBoxResilient(String name, Directory directory) =>
      openBoxResilientImpl(
        name,
        directory,
        _optionsOpen ? optionsBox : null,
        dbOptions,
      );

  late final Box optionsBox;
  late final Box scholarBox;
  late final Box taskBox;
  late final Box flowBox;
  late final Box originalWebPageBox;
  late final Box fuseBox;
  late final Box customGpaBox;
  late final Box tombstoneBox;
  late final Box focusBox;

  /// ===== MOD: 记住的账号密码的持久化副本 =====
  ///
  /// 用户反馈：更新之后登录页不再预填上次的账号密码。原因是那份副本
  /// （`mod_last_*`）原来只写在**系统密钥库**里，而某些 ROM 在覆盖安装后
  /// 读密钥库会返回 null（不报错），和"显示已登录但没有学号"是同一个坑。
  /// 用户拍板：**另存一份到数据库，永远能预填**。
  ///
  /// 取舍（重要，别以后当惊喜发现）：密钥库那份仍然写、仍然优先读；
  /// 数据库这份是**可解形式的回退**，存在应用私有目录里，只有本机能读，
  /// 但毕竟不如密钥库。安全与便利之间，用户选了"永远能预填"。
  late final Box accountBox;

  /// 课程挂载（资料 / 评论）：**键 = 课程代码**，值是一份 Map（见 `CourseMount`）。
  /// 不新增 typeId、不注册 adapter， 与 `CourseIdMap` 同一套做法。
  late final Box courseMountBox;

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
    // Hive 的目录就是 Hive.initFlutter() 用的那个（应用文档目录）。
    final hiveDirectory = await getApplicationDocumentsDirectory();
    optionsBox = await openBoxResilient(dbOptions, hiveDirectory);
    _optionsOpen = true;
    _bootProbe('[boot] 1 optionsBox');
    // ===== 一次性抢救：先把已知写坏的待办盒子挪走 =====
    //
    // 2026-09-16 事故：`Task` 加了字段 26 却没同步 adapter 的字段计数 →
    // 每次保存待办都写坏帧 → 读的时候抛 `unknown typeId: 26` → `openBox` 失败 →
    // main() 在 runApp 之前就死了 → App 打不开。
    // 计数已经改对（新写入不会再坏），但**已经写坏的那个文件没法在启动预算内修**：
    //   · 逐帧解码太慢（每帧装一整份列表，文件可能上百 MB），会撞上系统的启动看门狗；
    //   · 而 Hive 会缓存"打开失败"的结果，先试开再修这条路走不通。
    // 所以在**第一次打开它之前**就挪走（用户已确认接受"先能打开、数据随后抢救"）。
    //
    // 原文件一律**整份复制**成 `.damaged-<时间戳>` 留档，绝不删， 之后
    // App 里会有一支后台抢救流程去那几个备份里把好帧里的待办捞回来。
    await rescueDamagedTaskBoxOnce(hiveDirectory, optionsBox, dbTask);
    scholarBox = await openBoxResilient(dbScholar, hiveDirectory);
    taskBox = await openBoxResilient(dbTask, hiveDirectory);
    _bootProbe('[boot] 2 taskBox');
    flowBox = await openBoxResilient(dbFlow, hiveDirectory);
    originalWebPageBox =
        await openBoxResilient(dbOriginalWebPage, hiveDirectory);
    fuseBox = await openBoxResilient(dbFuse, hiveDirectory);
    customGpaBox = await openBoxResilient(dbCustomGpa, hiveDirectory);
    tombstoneBox = await openBoxResilient(dbTombstones, hiveDirectory);
    focusBox = await openBoxResilient(dbFocus, hiveDirectory);
    _bootProbe('[boot] 3 focusBox');
    accountBox = await openBoxResilient(dbAccount, hiveDirectory);
    courseMountBox = await openBoxResilient(dbCourseMount, hiveDirectory);
    _bootProbe('[boot] 4 新盒子');
    secureStorage = const FlutterSecureStorage();
    _bootProbe('[boot] 5 密钥库对象建好');

    // ===== P5：清掉时间规划时代留在 optionsBox 里的三个键 =====
    // P1 删功能时只删了访问器，值还躺在盒子里（workTime / restTime / allowTime）。
    // 一次性、幂等：有就删，没有就算了。删掉它们不会影响任何现有功能。
    for (final legacyKey in const ['workTime', 'restTime', 'allowTime']) {
      if (optionsBox.containsKey(legacyKey)) {
        await optionsBox.delete(legacyKey);
      }
    }
    // Migrate all items without groupID
    //
    // ===== MOD：整段加保险，且**绝不阻塞启动** =====
    // 原来这里是裸的 `await secureStorage.readAll(...)`：密钥库一旦不返回
    // （某些 ROM 覆盖安装后就会这样），main() 就永远走不到 runApp，
    // 用户看到的就是"App 打不开"（进程活着、无异常、无首帧，系统记 AppBootFail/ANR）。
    // 现在：最多等 3 秒，拿不到就当没东西要迁移，直接继续启动。
    final legacyIOSOptions = const IOSOptions(
        accessibility: KeychainAccessibility.first_unlock,
        accountName: 'Celechron');
    final secureStorageItems = await secureStorageOrNull(secureStorage.readAll(
          iOptions: legacyIOSOptions,
        )) ??
        const <String, String>{};
    for (final e in secureStorageItems.entries) {
      await secureStorageOrNull(
          secureStorage.delete(key: e.key, iOptions: legacyIOSOptions));
      await secureStorageOrNull(secureStorage.write(
          key: e.key, value: e.value, iOptions: secureStorageIOSOptions));
    }
  }

  // Options
  final String dbOptions = 'dbOptions';

  /// 删除墓碑：同步合并时用来判断"这条是被删掉的"
  final String dbTombstones = 'dbTombstones';

  /// ===== P3：专注会话记录 =====
  final String dbFocus = 'dbFocus';

  /// 记住的账号密码的数据库副本（见 [accountBox] 的注释）
  final String dbAccount = 'dbAccount';

  /// 课程挂载（资料 / 评论），键 = 课程代码
  final String dbCourseMount = 'dbCourseMount';

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
  /// 首次读取时生成一次、之后固定。用途：同步时告诉对方这份数据来自哪台设备，
  /// 面板上显示最后同步来自 X，以后排查谁把我这条改了也有据可依。
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
    final list = focusBox.values.whereType<FocusSession>().toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return list;
  }

  /// 还没正常结束的会话（App 被杀掉时留下的），正常情况最多一条
  List<FocusSession> getUnfinishedFocusSessions() =>
      getFocusSessions().where((s) => s.isRunning).toList();

  Future<void> saveFocusSession(FocusSession session) async {
    await focusBox.put(session.uid, session);
    // 记一笔"这条是本机产生的"（不动 Hive 结构，见 mod/focus_device.dart）
    await FocusDevice.remember(session.uid);
    // 专注记录也是用户数据：存完就让局域网同步推一次
    LanSyncClient.instance.scheduleSync();
  }

  Future<void> deleteFocusSession(String uid) async {
    await focusBox.delete(uid);
    // 记住"这条被删了"，同步时不再被对方带回来（原来删除不参与同步）
    await FocusDevice.rememberDeleted(uid);
    LanSyncClient.instance.scheduleSync();
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
    // ===== MOD：密钥库读取也要有保险（这是启动路径上的第二次密钥库调用）=====
    // 与 init() 里那段同理：平台侧不返回时，裸 await 会让 App 卡在启动画面。
    // 读不到就当没存过，凭据缺失由 main.dart 统一按"需要重新登录"处理。
    final stored = await Future.wait([
      secureStorageOrNull(secureStorage.read(
          key: kUsername, iOptions: secureStorageIOSOptions)),
      secureStorageOrNull(secureStorage.read(
          key: kPassword, iOptions: secureStorageIOSOptions)),
    ]);
    if (stored[0] != null) scholar.username = stored[0];
    if (stored[1] != null) scholar.password = stored[1];
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
