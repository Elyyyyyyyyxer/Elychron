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
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:celechron/utils/data_sync.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path_provider/path_provider.dart';
import 'package:hive/src/binary/binary_reader_impl.dart';
import 'package:hive/src/registry/type_registry_impl.dart';
import 'package:celechron/mod/ai/deepseek.dart';
import 'package:uuid/uuid.dart';
import 'adapters/deadline_adapter.dart';
import 'adapters/period_adapter.dart';
import 'adapters/fuse_adapter.dart';
import 'adapters/course_id_map_adapter.dart';
import 'adapters/focus_adapter.dart';

/// 密钥库（FlutterSecureStorage）调用的**保险丝**：超时就当没有，绝不阻塞启动。
///
/// ===== 为什么要这个 =====
///
/// 用户实测（2026-09-16）：「更新之后 Elychron 打不开了」——
/// 现象是**进程活着、日志里没有任何异常、first frame 永远不来**，
/// 系统侧记为 `AppBootFail` + 一条 ANR：说明启动路径被某个 await 卡死了。
///
/// 嫌疑最集中的就是密钥库：这台 ROM（华为）在**覆盖安装后**密钥库会"失忆"，
/// 我们之前已经确认过它读回 null（就是"显示已登录但没有学号"那个老毛病），
/// 而 `init()` 里那段迁移写的是 `await secureStorage.readAll(...)` ——
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
/// 完整的待办列表** —— 只要从文件尾往前找第一个读得动的帧，把它的值写回新盒子即可。
/// 丢的只是"坏帧之后的那几次保存"，历史数据绝大部分还在。
///
/// 安全前提（三条都满足才动手）：
///   1. 只做一次（optionsBox 里的标记）；
///   2. **当前待办盒子是空的**才恢复 —— 已经有数据时绝不覆盖；
///   3. 只读备份文件，**绝不修改或删除它**。
///
/// 放在 `runApp` 之后跑（不 await）：抢救可能要扫一会儿，但**不能挡住界面**。
Future<int> salvageTasksFromBackupOnce(
    Directory directory, Box taskBox, Box options) async {
  // 键里带版本号：抢救逻辑每改一次就 +1。否则"上一次那版用掉了标记"会把新版挡住
  // —— 这件事已经坑了我三次（盒子非空误判、只扫尾部 200 帧、以及现在这次）。
  const flagKey = 'salvagedTaskBox_v4_20260916';
  try {
    if (options.get(flagKey) == true) return 0;
    // 只在"当前一条待办都没有"时才动手 —— 有数据就一条都不碰，
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
    debugPrint('[boot] salvage: backups=${backups.length} newest=${backup.path}');

    // ===== 让 Hive 自己去读它 =====
    //
    // 前面试过"自己按帧扫描"，但那份备份只有 1 帧（Hive 压缩过），而它恰好是坏帧 ——
    // 扫不出"好帧"来。其实数据**完好无损**：坏的只是"字段计数写了 23、实际写了 24"，
    // 而这一点已经在 `DeadlineAdapter.read` 里做了兼容（读完字段后偷看一个字节，
    // 是 26 就把多出来的那一对吃回去）。
    //
    // 所以这里不自己解析了：**把备份复制成一个临时盒子，交给 Hive 打开并读出
    // `deadlineList`** —— CRC 校验、类型注册、列表还原全由它来做，最不容易错。
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
      debugPrint('[boot] salvage: temp box has no usable list (type=${value.runtimeType})');
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
/// （之前还有桌面小组件的 Glance 会话）。只要有一个把锁拿着不放 ——
/// 后台 isolate 卡住、或者上一轮被系统杀掉时留下了死锁 ——
/// **UI 进程就会永远卡在启动**，用户看到的就是"App 打不开"：
/// 进程活着、日志里没有任何异常、first frame 永远不来（系统记 AppBootFail + ANR）。
///
/// 当时的探针输出停在 `[boot] 4.1 optionsBox` 之后，也就是**卡在
/// `openBox(dbUser)` 上**，前面 optionsBox 一秒不到就开好了 —— 完美吻合"锁被占"。
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
    await options.put('openIntent:$name', DateTime.now().millisecondsSinceEpoch);
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

/// 打开前体检：帧扫一遍，发现坏帧就**就地截断**（原文件先备份）。
///
/// 2026-09-16 真实事故：给 `Task` 加了字段（26）却忘了同步 adapter 的**字段计数**
/// （声明 23 个、实际写 24 个）→ 每次保存待办都写下一个"多一对字节"的坏帧 →
/// 读取时列表读取器把多出来的那个 `26` 当成下一个元素的 typeId →
/// `HiveError: Cannot read, unknown typeId: 26` → `openBox` 抛错 →
/// `main()` 在 `runApp` 之前就死了 → 用户看到的就是「App 打不开」。
///
/// 截断的依据是：坏帧都产生于**同一个版本**，所以它们**连续地待在文件末尾**；
/// 而每次保存写的都是整份列表，因此**最后一个好帧里已经有完整数据**，
/// 截断只会丢掉坏帧之后的那几次写入，不会丢历史。
///
/// 备份文件名带时间戳（`<name>.hive.damaged-<ts>`），**绝不直接删原文件**。
/// 整个过程包在 try 里：体检本身出任何问题都不该阻止 App 启动。
Future<void> repairBoxFileIfNeeded(String name, Directory directory) async {
  final file = File(boxFilePath(directory, name));
  try {
    if (!await file.exists()) return;
    final raf = await file.open();
    try {
      final total = await raf.length();
      if (total <= 0) return;

      // 第一步：**流式**走一遍帧边界 —— 只 seek + 读 4 字节。
      //
      // 这里绝不能用 `readAsBytes()` 把整个文件读进内存：待办盒子每次保存都追加
      // 一整份列表，攒一晚上就能到几十上百 MB，一次读完会让启动直接卡死
      // （我前两版就是这么被系统的启动看门狗掐掉的：日志停在"体检"之前）。
      final starts = <int>[];
      var position = 0;
      while (position + 4 <= total && starts.length < 200000) {
        await raf.setPosition(position);
        final head = await raf.read(4);
        if (head.length < 4) break;
        final length =
            ByteData.sublistView(Uint8List.fromList(head)).getUint32(0, Endian.little);
        if (length < 8 || position + 4 + length > total) break;
        starts.add(position);
        position += 4 + length;
      }
      final stamp = DateTime.now().millisecondsSinceEpoch;
      if (starts.isEmpty) {
        await raf.close();
        await file.copy('${file.path}.damaged-$stamp');
        await file.rename('${file.path}.unreadable-$stamp');
        debugPrint('[boot] $name 没有完整帧 → 已挪走（原文件留在 .damaged）');
        return;
      }

      // 第二步：**从最后一帧往前**找第一个能解码的。
      // 坏帧产自同一个版本，必然连续待在末尾 —— 通常试一两次就命中。
      final registry = _repairRegistry();
      for (var i = starts.length - 1; i >= 0 && i >= starts.length - 50; i--) {
        final start = starts[i];
        final end = i + 1 < starts.length ? starts[i + 1] : total;
        if (end - start > 32 * 1024 * 1024) return; // 单帧异常大：不碰
        await raf.setPosition(start);
        final frameBytes = await raf.read(end - start);
        if (_frameDecodes(Uint8List.fromList(frameBytes), 0, frameBytes.length, registry)) {
          if (end >= total) return; // 最后一帧就是好的：文件没问题
          await raf.close();
          await file.copy('${file.path}.damaged-$stamp');
          // 截断到这一帧的结尾
          final keep = await file.open(mode: FileMode.append);
          await keep.truncate(end);
          await keep.close();
          debugPrint(
              '[boot] $name 有坏帧：已截断到 $end/$total 字节'
              '（丢了末尾 ${starts.length - 1 - i} 帧，备份 .damaged-$stamp）');
          return;
        }
      }
      await raf.close();
      await file.copy('${file.path}.damaged-$stamp');
      await file.rename('${file.path}.unreadable-$stamp');
      debugPrint('[boot] $name 末尾 50 帧都读不动 → 已挪走（备份 .damaged-$stamp）');
    } finally {
      // raf 可能已经被上面关掉了，重复 close 是安全的
      try {
        await raf.close();
      } catch (_) {}
    }
  } catch (error) {
    debugPrint('[boot] $name 体检失败（继续启动）：$error');
  }
}

/// 体检用的类型注册表（与 `init()` 里注册的同一批 adapter）
TypeRegistryImpl _repairRegistry() => TypeRegistryImpl()
  ..registerAdapter(DurationAdapter())
  ..registerAdapter(ScholarAdapter())
  ..registerAdapter(DeadlineStatusAdapter())
  ..registerAdapter(DeadlineTypeAdapter())
  ..registerAdapter(DeadlineRepeatTypeAdapter())
  ..registerAdapter(TaskPriorityAdapter())
  ..registerAdapter(SubTaskAdapter())
  ..registerAdapter(TaskAttachmentAdapter())
  ..registerAdapter(TaskCommentAdapter())
  ..registerAdapter(DeadlineAdapter())
  ..registerAdapter(PeriodTypeAdapter())
  ..registerAdapter(PeriodAdapter())
  ..registerAdapter(FuseAdapter())
  ..registerAdapter(CourseIdMapAdapter())
  ..registerAdapter(FocusSessionAdapter());

/// 单独解一帧，能解开就是好的（坏帧会抛 unknown typeId）。
bool _frameDecodes(Uint8List bytes, int start, int end, TypeRegistryImpl registry) {
  try {
    final reader = BinaryReaderImpl(Uint8List.sublistView(bytes, start, end), registry);
    return reader.readFrame() != null;
  } catch (_) {
    return false;
  }
}

/// 找出"还能读的最长前缀"：**从头逐帧解码**，遇到第一个读不动的帧就停。
///
/// 为什么不用"截断 + 试开盒子"那种二分：每次试开都要把整个前缀重新解码一遍，
/// 文件一大就是十几秒，而**系统会因为启动太久直接把进程判成 AppBootFail**
/// （我第一版就是这么被掐掉的：日志走到"尝试截断修复"就没了）。
///
/// 这里改成一遍扫描：读帧长 → 只解码这一帧 → 好就前进，坏就返回当前位置。
/// 帧长是帧本身的前 4 字节（小端），所以哪怕不解码也能安全地按帧步进。
///
/// 返回的偏移量就是"最后一个好帧的结尾"，也可能落在坏帧内部 —— 都无所谓：
/// 写回去之后，Hive 会把残缺的尾帧按"上次崩溃"处理并自动裁掉。
Future<int?> _largestReadablePrefix(String name, Uint8List bytes) async {
  // 与 init() 里注册的同一批 adapter（解码时要用它们认 typeId）
  final registry = TypeRegistryImpl()
    ..registerAdapter(DurationAdapter())
    ..registerAdapter(ScholarAdapter())
    ..registerAdapter(DeadlineStatusAdapter())
    ..registerAdapter(DeadlineTypeAdapter())
    ..registerAdapter(DeadlineRepeatTypeAdapter())
    ..registerAdapter(TaskPriorityAdapter())
    ..registerAdapter(SubTaskAdapter())
    ..registerAdapter(TaskAttachmentAdapter())
    ..registerAdapter(TaskCommentAdapter())
    ..registerAdapter(DeadlineAdapter())
    ..registerAdapter(PeriodTypeAdapter())
    ..registerAdapter(PeriodAdapter())
    ..registerAdapter(FuseAdapter())
    ..registerAdapter(CourseIdMapAdapter())
    ..registerAdapter(FocusSessionAdapter());

  var position = 0;
  while (position + 4 <= bytes.length) {
    final frameLength =
        ByteData.sublistView(bytes, position, position + 4).getUint32(0, Endian.little);
    // 帧长不合理（残缺尾帧 / 已经错位）→ 就停在这里
    if (frameLength < 8 || position + 4 + frameLength > bytes.length) break;
    try {
      final reader = BinaryReaderImpl(
        Uint8List.sublistView(bytes, position, position + 4 + frameLength),
        registry,
      );
      if (reader.readFrame() == null) break;
    } catch (_) {
      // 第一个读不动的帧 —— 正是我们要截断的位置
      break;
    }
    position += 4 + frameLength;
  }
  debugPrint('[boot] $name 扫描结果：可读到 $position / ${bytes.length} 字节');
  return position;
}

class DatabaseHelper {
  /// optionsBox 是否已经开好（自我修复靠它记进度，所以它开好之前不能读 optionsBox ——
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

  /// ===== MOD: 「记住的账号密码」的持久化副本 =====
  ///
  /// 用户反馈：更新之后登录页不再预填上次的账号密码。原因是那份副本
  /// （`mod_last_*`）原来只写在**系统密钥库**里，而某些 ROM 在覆盖安装后
  /// 读密钥库会返回 null（不报错）——和"显示已登录但没有学号"是同一个坑。
  /// 用户拍板：**另存一份到数据库，永远能预填**。
  ///
  /// 取舍（重要，别以后当惊喜发现）：密钥库那份仍然写、仍然优先读；
  /// 数据库这份是**可解形式的回退**，存在应用私有目录里，只有本机能读，
  /// 但毕竟不如密钥库。安全与便利之间，用户选了"永远能预填"。
  late final Box accountBox;

  /// 课程挂载（资料 / 评论）：**键 = 课程代码**，值是一份 Map（见 `CourseMount`）。
  /// 不新增 typeId、不注册 adapter —— 与 `CourseIdMap` 同一套做法。
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
    debugPrint('[boot] 4.1 optionsBox');
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
    // 原文件一律**整份复制**成 `.damaged-<时间戳>` 留档，绝不删 —— 之后
    // App 里会有一支后台抢救流程去那几个备份里把好帧里的待办捞回来。
    await rescueDamagedTaskBoxOnce(hiveDirectory, optionsBox, dbTask);
    scholarBox = await openBoxResilient(dbScholar, hiveDirectory);
    taskBox = await openBoxResilient(dbTask, hiveDirectory);
    debugPrint('[boot] 4.2 taskBox');
    flowBox = await openBoxResilient(dbFlow, hiveDirectory);
    originalWebPageBox = await openBoxResilient(dbOriginalWebPage, hiveDirectory);
    fuseBox = await openBoxResilient(dbFuse, hiveDirectory);
    customGpaBox = await openBoxResilient(dbCustomGpa, hiveDirectory);
    tombstoneBox = await openBoxResilient(dbTombstones, hiveDirectory);
    focusBox = await openBoxResilient(dbFocus, hiveDirectory);
    debugPrint('[boot] 4.3 focusBox');
    accountBox = await openBoxResilient(dbAccount, hiveDirectory);
    courseMountBox = await openBoxResilient(dbCourseMount, hiveDirectory);
    debugPrint('[boot] 4.4 新盒子');
    secureStorage = const FlutterSecureStorage();
    debugPrint('[boot] 4.5 密钥库对象建好');

    // ===== P5：清掉「时间规划」时代留在 optionsBox 里的三个键 =====
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
    // （某些 ROM 覆盖安装后就会这样），main() 就永远走不到 runApp ——
    // 用户看到的就是"App 打不开"（进程活着、无异常、无首帧，系统记 AppBootFail/ANR）。
    // 现在：最多等 3 秒，拿不到就当没东西要迁移，直接继续启动。
    final legacyIOSOptions = const IOSOptions(
        accessibility: KeychainAccessibility.first_unlock,
        accountName: 'Celechron');
    final secureStorageItems =
        await secureStorageOrNull(secureStorage.readAll(
              iOptions: legacyIOSOptions,
            )) ??
            const <String, String>{};
    for (final e in secureStorageItems.entries) {
      await secureStorageOrNull(secureStorage.delete(
          key: e.key, iOptions: legacyIOSOptions));
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

  /// 「记住的账号密码」的数据库副本（见 [accountBox] 的注释）
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
    // ===== MOD：密钥库读取也要有保险（这是启动路径上的第二次密钥库调用）=====
    // 与 init() 里那段同理：平台侧不返回时，裸 await 会让 App 卡在启动画面。
    // 读不到就当没存过，凭据缺失由 main.dart 统一按"需要重新登录"处理。
    final stored = await Future.wait([
      secureStorageOrNull(
          secureStorage.read(key: kUsername, iOptions: secureStorageIOSOptions)),
      secureStorageOrNull(
          secureStorage.read(key: kPassword, iOptions: secureStorageIOSOptions)),
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
