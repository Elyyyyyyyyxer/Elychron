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
import 'package:celechron/utils/utils.dart';

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

void main() async {
  // ===== 临时启动探针（排查"App 打不开"）=====
  // 现象：进程活着、无异常、first frame 永远不来。要定位卡在哪个 await，
  // 只能一步一步打点。定位完就删。
  debugPrint('[boot] 1 进入 main');
  // 全局错误组件：只设一次，且必须早于任何 widget 构建。
  // 绝不放在 widget 构造函数里 —— 那样每次重建都会改全局状态，且已证明会引发卡死。
  ErrorWidget.builder = (FlutterErrorDetails details) =>
      ScholarErrorHandler(errorDetails: details);
  // 尽可能早地声明前台活跃，Workmanager isolate 会据此安全让行。
  await RefreshCoordinator.setForegroundActive(true);
  debugPrint('[boot] 2 前台活跃已声明');

  // 初始化数据库
  await Hive.initFlutter();
  debugPrint('[boot] 3 Hive 就绪');
  var db = Get.put(DatabaseHelper(), tag: 'db');
  await db.init();
  debugPrint('[boot] 4 db.init 完成');

  final taskList = db.getTaskList();
  debugPrint('[boot] 5 任务列表读到 ${taskList.length} 条');
  await _applyPendingTodoWidgetCompletions(db, taskList);
  debugPrint('[boot] 6 小组件队列处理完');

  // 注入数据观察项（相当于事件总线，更新这些变量将导致Widget重绘
  final restoredScholar = await db.getScholar();
  debugPrint('[boot] 7 scholar 读到');

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
  final credentialsMissing = restoredUsername.isEmpty || restoredPassword.isEmpty;
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
  debugPrint('[boot] 8 runApp 已调用');
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

Future<void> _refreshRestoredScholar(Rx<Scholar> scholar) async {
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
                data:
                    MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
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

    void apply() =>
        SystemChrome.setSystemUIOverlayStyle(systemOverlayStyleFor(effectiveBrightness()));

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
