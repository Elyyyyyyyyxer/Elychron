import 'package:celechron/database/database_helper.dart';
import 'package:celechron/http/pta_spider.dart';
import 'package:celechron/http/zjuServices/exceptions.dart';
import 'package:celechron/model/scholar.dart';
import 'package:celechron/model/todo.dart';
import 'package:celechron/mod/pta_homework.dart';
import 'package:celechron/services/diagnostic_log_service.dart';
import 'package:celechron/services/refresh_coordinator.dart';
import 'package:celechron/utils/platform_features.dart';
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../utils/utils.dart';
import 'notification_dedup.dart';

/// 成绩变动通知的 channel（"有新课程出分"那条真消息走这里）
const NotificationDetails _gradeNotificationDetails = NotificationDetails(
  android: AndroidNotificationDetails(
    'top.celechron.celechron.gradeChange',
    '成绩变动提醒',
    importance: Importance.max,
    priority: Priority.high,
    showWhen: false,
  ),
  iOS: DarwinNotificationDetails(
    presentSound: true,
    presentBadge: true,
    presentBanner: true,
    presentList: true,
    sound: 'default',
    badgeNumber: 0,
  ),
);

/// 「成绩推送」这句开场白**单独一条通道**：它只是告知，不该像成绩变动那样
/// 用 Importance.max 顶一个横幅出来（用户反馈的就是"时不时给我推"）。
/// 默认重要度 = 有声但不出横幅；成绩本身那条仍然走 _gradeNotificationDetails。
const NotificationDetails _gradeIntroNotificationDetails = NotificationDetails(
  android: AndroidNotificationDetails(
    'top.celechron.celechron.tips',
    'Elychron 提示',
    channelDescription: '一次性的说明（比如"成绩推送已开启"），不弹横幅',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
    showWhen: false,
  ),
  iOS: DarwinNotificationDetails(
    presentSound: false,
    presentBadge: false,
    presentBanner: false,
    presentList: true,
    badgeNumber: 0,
  ),
);

/// 「成绩推送」的那句开场白 —— **只能在有界面的地方调**（见 main.dart 启动钩子）。
///
/// 用户反馈：「一天会给我推送很多次那个通知」。那句开场白原来就挂在
/// 15 分钟一次的后台任务里，后台 isolate 读不到"说过了"的记录时就会一直弹。
/// 现在：前台才说、而且用**文件**记着"说过了"，所以一辈子只会出现一次。
/// 顺带它也是唯一一条带具体数字的说明（已经查到几门出分、当前均绩多少）。
///
/// 2026-10-01 第二次修：用户说「始终时不时给我推"成绩推送已开启"」。
/// 复盘这条通知的"说过了"记在哪：Hive / 文件 / 密钥库三处，之前**只看后两处**，
/// 而后两处恰恰都可能丢 —— 密钥库在覆盖安装后会读空（某些 ROM，database_helper
/// 里那个 readAll 超时兜底就是为它加的），临时目录会被清。实测证据：手机在
/// 08:32 覆盖安装，08:39 又发了这条，而且正文里**连"已经查到 N 门出分"都没有**
/// （说明当时密钥库确实读空了）。现在正式记录写 Hive（和 pushOnGradeChange
/// 同一个盒子，覆盖安装、清缓存都带不走），另两处退化成"多一道保险"。
/// 开场白要不要说？纯判断，方便用测试钉住（三道闸任意一道说"说过了"就不说）。
///
/// 三道闸的目的不一样：Hive 是**权威**（覆盖安装带不走），文件和密钥库是
/// 保险（覆盖安装会丢、缓存会被清）。三个都可能丢一个，丢一个不该让这条
/// 一辈子只说一次的通知复活。
bool shouldShowGradePushIntro({
  required String fingerprint,
  required String hiveMark,
  required bool saidInFile,
  required bool saidInStorage,
}) {
  if (hiveMark == fingerprint) return false;
  if (saidInFile) return false;
  if (saidInStorage) return false;
  return true;
}

Future<void> showGradePushIntroOnce(DatabaseHelper db) async {
  if (!PlatformFeatures.hasBackgroundRefresh) return;
  const fingerprint = 'grade-push-intro-v1';

  // ===== 第一道闸（正式记录）：Hive =====
  final hiveMark = db.getGradePushIntroShown();
  if (hiveMark == fingerprint) return;

  final storage = const FlutterSecureStorage();
  // 两句"说过了"还是都查（文件跨 isolate 同一份、密钥库在前台通常读得到），
  // 但只要有一处丢了就当没说过 —— 所以它们是保险，不是权威（权威是上面那个
  // Hive 标记）。这条通知本来就该一辈子只出现一次。
  final saidInFile =
      await NotificationDedup.everSent('grade_intro', fingerprint);
  final saidInStorage = await storage.read(
          key: 'gradePushIntroShown', iOptions: secureStorageIOSOptions) ==
      '1';
  final shouldShow = shouldShowGradePushIntro(
    fingerprint: fingerprint,
    hiveMark: hiveMark,
    saidInFile: saidInFile,
    saidInStorage: saidInStorage,
  );
  if (!shouldShow) {
    // 老记录（文件或密钥库）说过了：把 Hive 这条正式记录补上，
    // 以后就不用再问那两个不靠谱的地方。不补的话，等它们哪天丢，这条又会复活。
    await db.setGradePushIntroShown(fingerprint);
    return;
  }

  final plugin = FlutterLocalNotificationsPlugin();
  const initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const initializationSettingsDarwin = DarwinInitializationSettings(
    requestSoundPermission: true,
    requestBadgePermission: true,
    requestAlertPermission: true,
  );
  const initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin);
  await plugin.initialize(initializationSettings);

  // 数字取后台已经查好的那一份（前台的学业页这时可能还没刷新完）
  final count = int.tryParse(await storage.read(
          key: 'gradedCourseCount', iOptions: secureStorageIOSOptions) ??
      '') ??
      0;
  final gpa = double.tryParse(await storage.read(
          key: 'gpa', iOptions: secureStorageIOSOptions) ?? '') ??
      0;

  final facts = <String>[];
  if (count > 0) facts.add('已经查到 ' + count.toString() + ' 门出分');
  if (gpa.isFinite && gpa > 0) {
    facts.add('当前均绩 ' + gpa.toStringAsFixed(2));
  }
  final head = facts.isEmpty ? '' : facts.join('，') + '。';
  final body = head +
      '以后有新课程出分，Elychron 会把课程名和成绩直接告诉你。'
          '不想收的话：设置 → 推送成绩变动 关掉即可。';

  // id 用 90001 而不是 0：0 是任何人都可能顺手用的默认 id，
  // 历史上它和别的通知互相顶掉过（用户反馈"通知全是成绩推送那一条"）。
  await plugin.show(
      90001, '成绩推送已开启', body, _gradeIntroNotificationDetails);
  // 三处一起记：Hive 是正式记录，另两处是保险。
  await db.setGradePushIntroShown(fingerprint);
  await NotificationDedup.markSent('grade_intro', fingerprint);
  await storage.write(
      key: 'gradePushIntroShown',
      value: '1',
      iOptions: secureStorageIOSOptions);
  DiagnosticLogService.instance.record(
    module: 'notify',
    operation: 'gradeIntro',
    message: '成绩推送开场白已发出（这是唯一一次；'
        '文件标记=$saidInFile，密钥库标记=$saidInStorage）',
  );
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  // 桌面端没有 WorkManager 这个概念（应用常驻前台，刷新走普通定时器），
  // 这里直接返回，不用把插件拉进来。
  if (!PlatformFeatures.hasBackgroundRefresh) return;
  Workmanager().executeTask((task, inputData) async {
    switch (task) {
      case 'top.celechron.celechron.backgroundScholarFetch':
        await refreshScholar();
        break;
      default:
        break;
    }
    return Future.value(true);
  });
}

Future<void> refreshScholar() async {
  if (await RefreshCoordinator.shouldYieldBackground()) {
    DiagnosticLogService.instance.record(
      module: 'refresh',
      operation: 'backgroundYield',
      message: '后台任务启动时检测到活跃前台，已正常让行',
      origin: RefreshOrigin.background,
    );
    return;
  }

  FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  const initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const initializationSettingsDarwin = DarwinInitializationSettings(
    requestSoundPermission: true,
    requestBadgePermission: true,
    requestAlertPermission: true,
  );
  const initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin);
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  // DDL 截止提醒 channel
  const ddlNotificationDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'top.celechron.celechron.ddlReminder',
      '作业截止提醒',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: false,
    ),
    iOS: DarwinNotificationDetails(
      presentSound: true,
      presentBadge: true,
      presentBanner: true,
      presentList: true,
      sound: 'default',
      badgeNumber: 0,
    ),
  );

  var scholar = Scholar();
  var secureStorage = const FlutterSecureStorage();
  scholar.username = await secureStorage.read(
      key: 'username', iOptions: secureStorageIOSOptions);
  scholar.password = await secureStorage.read(
      key: 'password', iOptions: secureStorageIOSOptions);
  var oldGpa =
      await secureStorage.read(key: 'gpa', iOptions: secureStorageIOSOptions) ??
          '0.0';
  var gradedCourseCount = await secureStorage.read(
          key: 'gradedCourseCount', iOptions: secureStorageIOSOptions) ??
      '0';
  var pushOnGradeChangeFuse = await secureStorage.read(
      key: 'pushOnGradeChangeFuse', iOptions: secureStorageIOSOptions);
  var pushOnGradeChange = await secureStorage.read(
      key: 'pushOnGradeChange', iOptions: secureStorageIOSOptions);
  var pushOnDdlReminder = await secureStorage.read(
      key: 'pushOnDdlReminder', iOptions: secureStorageIOSOptions);

  try {
    var backgroundYielded = false;
    final refreshErrors = await scholar.refresh(
      origin: RefreshOrigin.background,
      onBackgroundYield: () => backgroundYielded = true,
    );
    if (backgroundYielded) return;
    // 后台刷新拿到整体降级结果时不发通知，避免把旧缓存误判为新成绩或新作业。
    if (refreshErrors.whereType<String>().any((error) =>
        isDegradedRefreshText(error) && shortErrorText(error).contains('刷新'))) {
      return;
    }
    bool failed(String interfaceName) => refreshErrors
        .whereType<String>()
        .any((error) => shortErrorText(error).contains(interfaceName));

    // ===== 成绩变动通知 =====
    //
    // 2026-09-29 改：**把「首次成绩推送已开启」那条从这里删掉了**。
    //
    // 用户反馈：「一天会给我推送很多次那个通知」。那句开场白原来就挂在这个
    // 后台任务里（每 15 分钟一次），只要那次读不到"说过了"的记录就会再弹一遍；
    // 而后台 isolate 里读加密存储本来就不是一定成功（见
    // worker/notification_dedup.dart 的注释）。一条"提个醒"的通知放错地方，
    // 就成了骚扰。现在它只在有界面的地方说一次（main.dart 启动时调
    // showGradePushIntroOnce）。
    //
    // 这里因此只发**真正的新消息**，而且有两道闸：
    //   1. 分数或门数确实和上次记下来的不一样；
    //   2. 同样的内容 6 小时内不重复发（文件记账，不看加密存储的脸色）。
    if (pushOnGradeChange != 'false' && !failed('成绩')) {
      final gpa = scholar.gpa.isNotEmpty ? scholar.gpa[0] : 0.0;
      final count = scholar.gradedCourseCount;
      final fingerprint =
          'gpa=' + gpa.toStringAsFixed(2) + '|count=' + count.toString();
      // fuse 为 null = 这个后台任务还没成功跑过一轮，第一次只记数不说话
      final changed = pushOnGradeChangeFuse != null &&
          (gpa != double.tryParse(oldGpa) ||
              count != int.tryParse(gradedCourseCount));
      if (changed &&
          !await NotificationDedup.sentRecently(
              'grade', fingerprint, const Duration(hours: 6))) {
        await flutterLocalNotificationsPlugin.show(
            0,
            '成绩变动提醒',
            '有新出分的课程，可在 Elychron 的学业页面中刷新查看。',
            _gradeNotificationDetails);
        await NotificationDedup.markSent('grade', fingerprint);
      }
      await secureStorage.write(
          key: 'pushOnGradeChangeFuse',
          value: '1',
          iOptions: secureStorageIOSOptions);
      await secureStorage.write(
          key: 'gpa',
          value: gpa.toString(),
          iOptions: secureStorageIOSOptions);
      await secureStorage.write(
          key: 'gradedCourseCount',
          value: count.toString(),
          iOptions: secureStorageIOSOptions);
    }

    // ===== PTA 作业（2026-10-01）=====
    //
    // 后台 isolate 碰不到 Hive，所以开关 / cookie / 当堂开关是前台保存时**镜像**
    // 进密钥库的（见 mod/pta_homework.dart）。这里照着它自己拉一遍，目的是让下面
    // 那段「作业截止提醒」也能覆盖 PTA 作业；顺手把结果写进文件缓存，
    // 前台下次打开直接用（文件是两个 isolate 之间唯一稳的通道）。
    // PTA 是可选来源：没配、拿不到 cookie、拉失败都不该影响别的提醒。
    try {
      final ptaCookie =
          await secureStorage.read(key: 'ptaCookie', iOptions: secureStorageIOSOptions) ??
              '';
      final ptaEnabled =
          await secureStorage.read(key: 'ptaEnabled', iOptions: secureStorageIOSOptions) ==
              'true';
      if (ptaEnabled && ptaCookie.isNotEmpty) {
        final ptaIncludeInClass = await secureStorage.read(
                key: 'ptaIncludeInClass', iOptions: secureStorageIOSOptions) ==
            'true';
        final spider = PtaSpider(cookie: ptaCookie);
        try {
          final parsed =
              await spider.fetchActive(includeInClass: ptaIncludeInClass);
          if (parsed.todos.isNotEmpty) {
            scholar.todos = <Todo>[...scholar.todos, ...parsed.todos];
            await PtaHomework.cacheFromBackground(parsed.todos);
          }
        } finally {
          spider.close();
        }
      }
    } on Object catch (error) {
      DiagnosticLogService.instance.record(
        level: CelechronLogLevel.warning,
        module: 'PTA',
        operation: 'backgroundRefresh',
        message: '后台拉 PTA 作业失败：' + error.toString(),
      );
    }

    // DDL 截止提醒
    if (pushOnDdlReminder != 'false' && !failed('作业')) {
      // 存哪改过：原来存在加密存储里，后台 isolate 读不到就会把"提醒过了"
      // 的记录丢掉，于是同一个作业每 15 分钟提醒一次（见 notification_dedup.dart）。
      Set<String> notifiedDdlIds = {};
      {
        final record = await NotificationDedup.read('ddl_ids');
        final rawIds = record == null ? null : record['ids'];
        if (rawIds is List) {
          notifiedDdlIds = rawIds.map((item) => item.toString()).toSet();
        }
      }

      var now = DateTime.now();
      var upcomingTodos = scholar.todos.where((todo) {
        if (todo.endTime == null) return false;
        var timeLeft = todo.endTime!.difference(now);
        // 24 小时内到期且尚未通知过
        return timeLeft.inHours >= 0 &&
            timeLeft.inHours <= 24 &&
            !notifiedDdlIds.contains(todo.id);
      }).toList();

      if (upcomingTodos.isNotEmpty) {
        var notificationId = 1000; // DDL 通知从 1000 开始
        for (var todo in upcomingTodos) {
          var hoursLeft = todo.endTime!.difference(now).inHours;
          var timeDesc = hoursLeft > 0 ? '$hoursLeft 小时后' : '即将';
          await flutterLocalNotificationsPlugin.show(
              notificationId++,
              '作业截止提醒',
              '${todo.course}的作业${todo.name}将于$timeDesc截止',
              ddlNotificationDetails);
          notifiedDdlIds.add(todo.id);
        }
      }

      // 清理已过期的通知记录，避免无限增长
      notifiedDdlIds.removeWhere((id) {
        var todo = scholar.todos.where((t) => t.id == id);
        if (todo.isEmpty) return true;
        return todo.first.endTime != null && todo.first.endTime!.isBefore(now);
      });

      await NotificationDedup.write(
          'ddl_ids', <String, dynamic>{'ids': notifiedDdlIds.toList()});
    }
  } on Object catch (error, stackTrace) {
    if (kDebugMode) {
      debugPrint('后台学业刷新失败：${error.runtimeType}: $error\n$stackTrace');
    }
    return;
  }
}
