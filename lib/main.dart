import 'package:celechron/design/app_accent.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:celechron/page/scholar/scholar_view.dart';
import 'package:get/get.dart';
import 'package:celechron/model/task.dart';

import 'package:path_provider/path_provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:app_links/app_links.dart';

import 'package:celechron/model/scholar.dart';
import 'package:celechron/model/option.dart';
import 'package:celechron/page/home_page.dart';
import 'package:celechron/page/option/ecard_pay_page.dart';
import 'package:celechron/services/diagnostic_log_service.dart';
import 'package:celechron/services/refresh_coordinator.dart';
import 'package:celechron/worker/ecard_widget_messenger.dart';
import 'package:celechron/worker/todo_widget_messenger.dart';
import 'package:celechron/database/database_helper.dart';
import 'package:celechron/utils/global.dart';

/// 启动路标总开关。**发布版保持 false。**
///
/// `[boot] 1…8`（main.dart）和 `[boot] 4.1…4.5`（database_helper.dart）是"走到哪一步了"
/// 的路标 —— 2026-09-16 的「App 打不开」就是靠它们定位到"卡在开某个盒子上"的，
/// 所以**代码留着**；但正常用户不需要每次开机都往 logcat 里灌十几行。
/// 排查启动问题时：把这里改成 `true` 重新构建（这种诊断包不要发出去）。
///
/// ⚠️ **只关路标，不关异常日志** —— 自愈、删锁、留档、抢救那些 `[boot]` 只在真出事时
/// 才打，继续用 `debugPrint` 原样保留（那才是现场最有用的东西）。
bool _bootProbesEnabled = false;

/// 打一条启动路标（受 [_bootProbesEnabled] 控制）。
void _bootProbe(String message) {
  if (_bootProbesEnabled) debugPrint(message);
}

void main() async {
  _bootProbe('[boot] 1 进入 main');
  // 全局错误组件：只设一次，且必须早于任何 widget 构建。
  // 绝不放在 widget 构造函数里 —— 那样每次重建都会改全局状态，且已证明会引发卡死。
  ErrorWidget.builder = (FlutterErrorDetails details) =>
      ScholarErrorHandler(errorDetails: details);

  // ===== MOD: GetX 的「中毒」解毒剂（2026-09-16）=====
  //
  // 背景：用户报「点击成绩卡片任意位置会卡死」。真机复现出来，这是一条**框架级**的
  // 放大链路 —— 跟"具体哪一行写错了"无关，所以值得在这里堵死：
  //
  //   ① 某个 `Obx` 的 builder 抛异常（那次是成绩页在**空列表**上取下标 → RangeError）；
  //   ② GetX 4.7.3 `rx_interface.dart` 的 `notifyChildren` 长这样：
  //        RxInterface.proxy = observer;      // 先设全局代理
  //        final result = builder();          // ← 在这里抛
  //        ...
  //        RxInterface.proxy = oldObserver;   // 夭折：永远不会执行
  //      ⇒ `RxInterface.proxy` 被**永久留在一个已经构建失败的 Obx 上**；
  //   ③ 此后全 App 任何一次 Rx 读取都会挂到这个"死观察者"上 → 反复触发它 setState
  //      → 它每次重建都再抛一次 → **主线程 100% CPU 空转**；
  //   ④ 5 秒后系统判「Elychron 无响应」，弹 ANR 对话框 —— 用户看到的就是"卡死"。
  //      （真机 ANR 报告佐证：主线程 state=R、utm=23.5s、全程跑在 libapp.so 里，不是死锁。）
  //
  // 我们改不了 GetX，但 `RxInterface.proxy` 是**公开静态字段** —— 在"构建已经出错"的
  // 这一刻清掉它，就能断掉第 ③ 步。Flutter 捕获构建异常后会调 `FlutterError.onError`，
  // 时机正好在 builder 抛错之后、重建循环开始之前。
  //
  // ⚠️ 这只是**兜底**：真正的修法永远是"别让 builder 抛错"（成绩页那次已单独修，见
  // `lib/page/scholar/grade_detail/grade_detail_view.dart` 的 build）。
  FlutterError.onError = (FlutterErrorDetails details) {
    try {
      RxInterface.proxy = null;
    } catch (_) {
      // 解毒本身绝不能抛
    }
    FlutterError.presentError(details);
  };
  // 尽可能早地声明前台活跃，Workmanager isolate 会据此安全让行。
  await RefreshCoordinator.setForegroundActive(true);
  _bootProbe('[boot] 前台活跃已声明');

  // 初始化数据库
  await Hive.initFlutter();
  _bootProbe('[boot] Hive 就绪');
  var db = Get.put(DatabaseHelper(), tag: 'db');
  await db.init();
  _bootProbe('[boot] db.init 完成');

  final taskList = db.getTaskList();
  _bootProbe('[boot] 任务列表读到 ${taskList.length} 条');
  await _applyPendingTodoWidgetCompletions(db, taskList);
  _bootProbe('[boot] 小组件队列处理完');

  // 注入数据观察项（相当于事件总线，更新这些变量将导致Widget重绘
  final restoredScholar = await db.getScholar();
  _bootProbe('[boot] scholar 读到');

  // ===== MOD: 「已登录但没有学号」= 半坏状态，必须当没登录 =====
  //
  // 用户反复反馈（原话：「基本上每次推送更新的时候登录态会变成一种诡异的样子，
  // 显示"已登录"但是没有学号，同时学业页面刷新不出来。退出登录后再次重新登陆时
  // 不会保存上次的账号密码，重新登陆之后一切恢复正常」）。
  //
  // 成因：**两套存储的存活期不一样** ——
  //   · `isLogan`（以及课程/成绩等）跟着 Scholar 存进 Hive 数据库，覆盖安装后还在；
  //   · `username`/`password` 存在**系统密钥库**（FlutterSecureStorage），
  //     某些 ROM / 机型在覆盖安装后读不出来（读回 null，不报错）。
  // 于是 App 认为自己登录着 → 不做重新登录、但每次刷新都失败 →
  // 用户看到的就是那个"诡异的样子"。顺带一提，学业页曾因此**每 20 秒崩一次**
  // （`Scholar.isGrs` 里的 `username!`，已修，见 WHATS_NEW 11.8）。
  //
  // 这里在**注入之前**纠正：凭据不全就当没登录。这样：
  //   ① `if (scholar.value.isLogan)` 不会再去跑注定失败的自动刷新；
  //   ② `sessionInvalid = true` 会让设置页给出"重新登录"入口（option_view 已有该 UI）；
  //   ③ 登录页会读我们另存的 `mod_last_*` 去预填账号密码（数据库里那份，不依赖密钥库
  //      读得到——但如果连它也读不出来，用户至少知道要重新登录，而不是干瞪眼）。
  final restoredUsername = restoredScholar.username ?? '';
  final restoredPassword = restoredScholar.password ?? '';
  final credentialsMissing =
      restoredUsername.isEmpty || restoredPassword.isEmpty;
  if (restoredScholar.isLogan && credentialsMissing) {
    debugPrint(
        '[Elychron] 恢复的登录状态缺少凭据（学号=${restoredUsername.isEmpty ? "空" : "有"}、'
        '密码=${restoredPassword.isEmpty ? "空" : "有"}）→ 按需要重新登录处理');
    restoredScholar.isLogan = false;
    restoredScholar.sessionInvalid = true;
  }

  Get.put(restoredScholar.obs, tag: 'scholar');
  Get.put(taskList.obs, tag: 'taskList');
  Get.put(db.getTaskListUpdateTime().obs, tag: 'taskListLastUpdate');
  Get.put(db.getFlowList().obs, tag: 'flowList');
  Get.put(db.getFlowListUpdateTime().obs, tag: 'flowListLastUpdate');
  Get.put(db.getOption(), tag: 'option');
  Get.put(db.getFuse().obs, tag: 'fuse');

  runApp(const CelechronApp());
  _bootProbe('[boot] runApp 已调用');

  // ===== 一次性抢救：从被打坏的待办盒子备份里把数据捞回来 =====
  //
  // 放在 runApp **之后**且不 await：抢救要扫备份文件，可能几十秒，
  // 但绝不能因为它在启动路径上而拖住界面（这正是今晚"打不开"的教训）。
  // 只在"当前待办盒子是空的"时才恢复，已经有数据就一条都不碰。
  unawaited(() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final restored = await salvageTasksFromBackupOnce(
        directory,
        db.taskBox,
        db.optionsBox,
      );
      if (restored > 0) {
        final tasks = db.getTaskList();
        final live = Get.find<RxList<Task>>(tag: 'taskList');
        live
          ..clear()
          ..addAll(tasks);
        live.refresh();
        debugPrint('[boot] 已把抢救到的 ${tasks.length} 条待办推给界面');
      }
    } catch (error) {
      debugPrint('[boot] 抢救流程出错（不影响使用）：$error');
    }
  }());
  unawaited(TodoWidgetMessenger.update(
    Get.find<RxList<Task>>(tag: 'taskList'),
  ));

  var scholar = Get.find<Rx<Scholar>>(tag: 'scholar');
  if (scholar.value.isLogan) {
    // 启动恢复只有一个自动刷新入口；会话重建由 Scholar.refresh 内部完成。
    // 用户此时手动刷新会复用并等待这一个 refresh Future。
    // 校园卡使用不同 HttpClient/User-Agent，等 Scholar 认证和抓取
    // 完成后再启动，避免两套 CAS 链路在启动瞬间互相干扰。
    unawaited(
      _refreshRestoredScholar(scholar)
          .whenComplete(ECardWidgetMessenger.update),
    );
  } else {
    unawaited(ECardWidgetMessenger.update());
  }
}

Future<DateTime?> _applyPendingTodoWidgetCompletions(
  DatabaseHelper db,
  List<Task> tasks,
) async {
  final ids = await TodoWidgetMessenger.pendingCompletionIds();
  if (ids.isEmpty) return null;

  final completedAt = DateTime.now();
  final changed = TodoWidgetMessenger.markCompleted(
    tasks,
    ids,
    now: completedAt,
  );
  if (changed) {
    await db.setTaskList(tasks);
    await db.setTaskListUpdateTime(completedAt);
  }
  await TodoWidgetMessenger.acknowledgeCompletions(ids);
  return changed ? completedAt : null;
}

/// 三个模块里最近的一次更新时间（都是占位值 2001 表示"从没成功过"，跳过）
DateTime? _latestModuleUpdate(Scholar scholar) {
  DateTime? latest;
  for (final time in [
    scholar.lastUpdateTimeGrade,
    scholar.lastUpdateTimeCourse,
    scholar.lastUpdateTimeHomework,
  ]) {
    if (time.year <= 2001) continue;
    if (latest == null || time.isAfter(latest)) latest = time;
  }
  return latest;
}

Future<void> _refreshRestoredScholar(Rx<Scholar> scholar) async {
  // ===== MOD 2026-09-17：**刚刷新过就别再刷一次** =====
  //
  // 用户问「为什么校历和课表总是难以连接上」，其中一条原因就是：
  // 后台刷新（WorkManager）和"打开 App 自动刷新"以前各打一整套请求 ——
  // 7 个模块并发、光课表就要按 4 个学期分别查，叠起来极易被教务限流（HTTP 921）。
  //
  // 这里加一道"最小间隔"：最近 5 分钟内成功更新过，就跳过启动自动刷新。
  // 数据反正是新的；想立刻要最新的，下拉刷新随时可以手动来一次。
  final lastUpdated = _latestModuleUpdate(scholar.value);
  if (lastUpdated != null &&
      DateTime.now().difference(lastUpdated) < const Duration(minutes: 5)) {
    DiagnosticLogService.instance.record(
      module: 'refresh',
      operation: 'startupRefreshSkipped',
      message: '最近一次更新在 ${DateTime.now().difference(lastUpdated).inMinutes} 分钟前'
          '（不足 5 分钟），跳过启动自动刷新 —— 避免和后台刷新叠在一起被教务限流',
    );
    return;
  }
  GlobalStatus.isFirstScreenReq = true;
  try {
    await scholar.value.refresh(onPartialUpdate: scholar.refresh);
  } on Object catch (error, stackTrace) {
    // 启动刷新不阻断缓存数据展示，但异常仍进入诊断日志。
    DiagnosticLogService.instance.record(
      level: CelechronLogLevel.error,
      module: 'refresh',
      operation: 'startupRefresh',
      message: '启动自动刷新异常结束',
      error: error,
      stackTrace: stackTrace,
    );
  } finally {
    GlobalStatus.isFirstScreenReq = false;
    scholar.refresh();
  }
}

/// 系统栏（状态栏 + 导航栏）的样式。
///
/// 关键点是那个外观位：光设 `systemNavigationBarColor` 不够 ——
/// 系统（尤其 EMUI）会忽略它，仍按自己的默认画成黑的。
/// 必须同时声明「导航栏用浅色外观」（`systemNavigationBarIconBrightness: dark`
/// 对应 Android 的 `LIGHT_NAVIGATION_BAR`），底下那三条才会变白底深色。
/// 参考实测：钉钉的窗口 `vsysui` 里就带着 `LIGHT_NAVIGATION_BAR`。
SystemUiOverlayStyle systemOverlayStyleFor(Brightness brightness) {
  final light = brightness == Brightness.light;
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: light ? Brightness.dark : Brightness.light,
    // 与 CupertinoColors.systemGroupedBackground 的浅/深两版对齐
    systemNavigationBarColor:
        light ? const Color(0xFFF2F2F7) : const Color(0xFF1C1C1E),
    systemNavigationBarDividerColor: Colors.transparent,
    // 关掉系统「为了对比度」自动加的半透明黑底
    systemNavigationBarContrastEnforced: false,
    systemNavigationBarIconBrightness:
        light ? Brightness.dark : Brightness.light,
  );
}

class CelechronApp extends StatefulWidget {
  const CelechronApp({super.key});

  @override
  State<CelechronApp> createState() => _CelechronAppState();
}

class _CelechronAppState extends State<CelechronApp>
    with WidgetsBindingObserver {
  Timer? _foregroundLeaseHeartbeat;
  StreamSubscription<Uri>? _appLinkSubscription;
  bool _applyingWidgetCompletions = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startForegroundLease();

    // 监听AppLinks，用于跳转至付款码页面
    _initAppLinks();
    // 初始化通知
    _initNotification();
    // 设置Android状态栏和导航栏样式
    if (Platform.isAndroid) {
      _initStatusBar();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _appLinkSubscription?.cancel();
    _stopForegroundLease();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startForegroundLease();
      unawaited(_consumeTodoWidgetCompletions());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _stopForegroundLease();
    }
    if (state == AppLifecycleState.paused) {
      ECardWidgetMessenger.update();
      unawaited(TodoWidgetMessenger.update(
        Get.find<RxList<Task>>(tag: 'taskList'),
      ));
    }
  }

  Future<void> _consumeTodoWidgetCompletions() async {
    if (_applyingWidgetCompletions) return;
    _applyingWidgetCompletions = true;
    try {
      final tasks = Get.find<RxList<Task>>(tag: 'taskList');
      final completedAt = await _applyPendingTodoWidgetCompletions(
        Get.find<DatabaseHelper>(tag: 'db'),
        tasks,
      );
      if (completedAt == null) return;

      Get.find<Rx<DateTime>>(tag: 'taskListLastUpdate').value = completedAt;
      tasks.refresh();
      await TodoWidgetMessenger.update(tasks);
    } finally {
      _applyingWidgetCompletions = false;
    }
  }

  void _startForegroundLease() {
    unawaited(RefreshCoordinator.setForegroundActive(true));
    _foregroundLeaseHeartbeat ??= Timer.periodic(
      RefreshCoordinator.foregroundHeartbeatInterval,
      (_) => unawaited(RefreshCoordinator.setForegroundActive(true)),
    );
  }

  void _stopForegroundLease() {
    _foregroundLeaseHeartbeat?.cancel();
    _foregroundLeaseHeartbeat = null;
    unawaited(RefreshCoordinator.setForegroundActive(false));
  }

  @override
  Widget build(BuildContext context) {
    var brightnessMode = Get.find<Option>(tag: 'option').brightnessMode;
    return Obx(() => GetCupertinoApp(
          theme: CupertinoThemeData(
            brightness: brightnessMode.value == BrightnessMode.system
                ? null
                : brightnessMode.value == BrightnessMode.dark
                    ? Brightness.dark
                    : Brightness.light,
            primaryColor: AppAccent.primary, // 爱莉希雅粉
            primaryContrastingColor: CupertinoColors.white,
            scaffoldBackgroundColor: CupertinoColors.systemBackground,
            barBackgroundColor: CupertinoColors.systemBackground,
          ),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('zh'),
            Locale('en'),
          ],
          locale: const Locale('zh'),
          // ===== MOD：系统栏（状态栏 + 导航栏）外观 =====
          // 用 AnnotatedRegion 而不是只调一次 SystemChrome：
          // 它是**每帧**按当前主题亮度生效的，能可靠地带上
          // `LIGHT_NAVIGATION_BAR`（浅底 + 深色图标）—— 实测对比过钉钉的窗口属性，
          // 它正是靠这个外观位让底下那三条变白的。
          builder: (context, child) {
            // CupertinoTheme 的亮度已经反映了用户「浅色 / 深色 / 跟随系统」的设置
            final brightness = CupertinoTheme.brightnessOf(context);
            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: systemOverlayStyleFor(brightness),
              child: MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(alwaysUse24HourFormat: true),
                child: child!,
              ),
            );
          },
          title: 'Elychron',
          home: const HomePage(title: 'Elychron'),
          initialRoute: '/',
          routes: {
            '/ecardpaypage': (context) => ECardPayPage(),
          },
          debugShowCheckedModeBanner: false,
          navigatorKey: navigatorKey,
        ));
  }

  void _initAppLinks() {
    final appLinks = AppLinks();
    _appLinkSubscription = appLinks.uriLinkStream.listen((uri) {
      if (uri.toString() == 'celechron://ecardpaypage') {
        navigator?.popUntil((route) =>
            !(route.settings.name?.endsWith('ecardpaypage') ?? false));
        navigator?.pushNamed('/ecardpaypage');
      } else if (uri.scheme == 'celechron' && uri.host == 'todo') {
        TodoWidgetActionCenter.dispatch(
          uri.path == '/create'
              ? TodoWidgetAction.create
              : TodoWidgetAction.openList,
        );
      }
    });
  }

  void _initStatusBar() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    var brightnessMode = Get.find<Option>(tag: 'option').brightnessMode;
    var dispatcher = SchedulerBinding.instance.platformDispatcher;

    Brightness effectiveBrightness() {
      switch (brightnessMode.value) {
        case BrightnessMode.dark:
          return Brightness.dark;
        case BrightnessMode.light:
          return Brightness.light;
        default:
          return dispatcher.platformBrightness;
      }
    }

    void apply() => SystemChrome.setSystemUIOverlayStyle(
        systemOverlayStyleFor(effectiveBrightness()));

    ever(brightnessMode, (mode) {
      dispatcher.onPlatformBrightnessChanged =
          mode == BrightnessMode.system ? apply : null;
      apply();
    });
    brightnessMode.refresh();
  }

  void _initNotification() {
    FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();
    const initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    const initializationSettingsDarwin = DarwinInitializationSettings(
      requestSoundPermission: true,
      requestBadgePermission: true,
      requestAlertPermission: true,
    );
    // const initializationSettingsWindows = WindowsInitializationSettings(
    //     appName: 'Celechron',
    //     appUserModelId: 'top.celechron.app',
    //     guid: '7c85e25b-fa7d-489e-9b10-b4c22a3458f0');
    const initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
      macOS: initializationSettingsDarwin,
      // windows: initializationSettingsWindows);
    );
    flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }
}
