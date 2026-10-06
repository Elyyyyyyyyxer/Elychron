import 'dart:io';
import 'dart:async';

import 'package:celechron/database/database_helper.dart';
import 'package:celechron/design/task_time_panel.dart';
import 'package:celechron/mod/ios_task_reminder_preferences.dart';
import 'package:celechron/model/task.dart';
import 'package:celechron/page/task/task_create_page.dart';
import 'package:celechron/page/task/task_edit_page.dart';
import 'package:celechron/utils/task_reminder.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

class _DelayedOptions implements Box<dynamic> {
  final Box<dynamic> box;
  final started = Completer<void>();
  final allow = Completer<void>();
  final _storedValues = <dynamic, dynamic>{};
  _DelayedOptions(this.box);

  @override
  dynamic get(dynamic key, {dynamic defaultValue}) =>
      _storedValues.containsKey(key)
          ? _storedValues[key]
          : box.get(key, defaultValue: defaultValue);

  @override
  bool containsKey(dynamic key) =>
      _storedValues.containsKey(key) || box.containsKey(key);

  @override
  Future<void> put(dynamic key, dynamic value) async {
    started.complete();
    await allow.future;
    _storedValues[key] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const notifications =
      MethodChannel('dexterous.com/flutter/local_notifications');
  const alarms = MethodChannel('celechron/alarm');
  final notificationCalls = <MethodCall>[];
  final alarmCalls = <MethodCall>[];
  late Directory dir;
  late DatabaseHelper db;
  var nativeAvailable = true;

  Task task(String uid) {
    final at = DateTime.now().add(const Duration(hours: 1));
    return Task(
      uid: uid,
      summary: '测试提醒',
      type: TaskType.remind,
      reminderEnabled: true,
      reminderTime: at,
      startTime: at,
      endTime: at,
      repeatEndsTime: at,
    );
  }

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    TaskReminder.mode = TaskReminder.modeNotification;
    dir = await Directory.systemTemp.createTemp('elychron-mode-test-');
    Hive.init(dir.path);
    db = DatabaseHelper();
    db.optionsBox = await Hive.openBox('options');
    Get.put(db, tag: 'db');
    notificationCalls.clear();
    alarmCalls.clear();
    nativeAvailable = true;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(notifications, (call) async {
      notificationCalls.add(call);
      if (call.method == 'getNotificationAppLaunchDetails') {
        return {'notificationLaunchedApp': false};
      }
      return true;
    });
    messenger.setMockMethodCallHandler(alarms, (call) async {
      alarmCalls.add(call);
      return nativeAvailable;
    });
  });

  tearDown(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await TaskReminder.syncAll([]);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      ..setMockMethodCallHandler(notifications, null)
      ..setMockMethodCallHandler(alarms, null);
    Get.reset();
    await Hive.close();
    await dir.delete(recursive: true);
    debugDefaultTargetPlatformOverride = null;
    TaskReminder.mode = TaskReminder.modeNotification;
  });

  test('每条待办选择独立存储，重开设置箱后仍保留', () async {
    expect(IosTaskReminderPreferences.modeFor('first'), 0);
    await IosTaskReminderPreferences.save('first', 1);
    await IosTaskReminderPreferences.save('second', 0);
    await db.optionsBox.close();
    Get.delete<DatabaseHelper>(tag: 'db');
    db = DatabaseHelper();
    db.optionsBox = await Hive.openBox('options');
    Get.put(db, tag: 'db');
    expect(IosTaskReminderPreferences.modeFor('first'), 1);
    expect(IosTaskReminderPreferences.modeFor('second'), 0);
    expect(IosTaskReminderPreferences.modeFor('third'), 0);
  });

  test('同一批任务分别调度通知和原生闹钟，修改时间与完成会撤销', () async {
    final native = task('native-schedule');
    final normal = task('notification-schedule');
    await IosTaskReminderPreferences.save(native.uid, 1);
    await TaskReminder.syncAll([native, normal]);
    expect(
        alarmCalls.where((c) => c.method == 'scheduleTaskAlarm'), hasLength(1));
    expect(notificationCalls.where((c) => c.method == 'zonedSchedule'),
        hasLength(1));
    final first = alarmCalls.firstWhere((c) => c.method == 'scheduleTaskAlarm');
    expect(first.arguments['uid'], native.uid);
    expect(first.arguments['atMillis'],
        native.reminderTargetTime.millisecondsSinceEpoch);

    alarmCalls.clear();
    native.reminderTime =
        native.reminderTargetTime.add(const Duration(minutes: 5));
    await TaskReminder.syncAll([native, normal]);
    expect(alarmCalls.map((c) => c.method),
        ['cancelTaskAlarm', 'scheduleTaskAlarm']);
    native.status = TaskStatus.completed;
    alarmCalls.clear();
    await TaskReminder.syncAll([native, normal]);
    expect(alarmCalls.map((c) => c.method), ['cancelTaskAlarm']);
    alarmCalls.clear();
    await TaskReminder.syncAll([normal]);
    expect(alarmCalls.map((c) => c.method), ['cancelTaskAlarm']);
  });

  test('原生闹钟不可用时回退通知，切回通知会取消原生闹钟', () async {
    final native = task('fallback');
    await IosTaskReminderPreferences.save(native.uid, 1);
    nativeAvailable = false;
    await TaskReminder.syncAll([native]);
    expect(notificationCalls.where((c) => c.method == 'zonedSchedule'),
        hasLength(1));
    await IosTaskReminderPreferences.save(native.uid, 0);
    alarmCalls.clear();
    notificationCalls.clear();
    await TaskReminder.syncAll([native]);
    expect(alarmCalls.map((c) => c.method), ['cancelTaskAlarm']);
    expect(notificationCalls.where((c) => c.method == 'zonedSchedule'),
        hasLength(1));
  });

  test('权限等待期间切回通知，旧闹钟完成后仍会被取消', () async {
    final native = task('pending-authorization');
    await IosTaskReminderPreferences.save(native.uid, 1);
    final started = Completer<void>();
    final authorized = Completer<bool>();
    final events = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(alarms, (call) async {
      events.add(call.method);
      if (call.method == 'scheduleTaskAlarm') {
        started.complete();
        final result = await authorized.future;
        events.add('scheduleFinished');
        return result;
      }
      return true;
    });
    final first = TaskReminder.syncAll([native]);
    await started.future;
    await IosTaskReminderPreferences.save(native.uid, 0);
    final updated = TaskReminder.syncAll([native]);
    await Future<void>.delayed(Duration.zero);
    authorized.complete(true);
    await Future.wait([first, updated]);
    expect(events.last, 'cancelTaskAlarm');
    expect(notificationCalls.where((c) => c.method == 'zonedSchedule'),
        hasLength(1));
  });

  test('下一次重复任务继承原生方式并保留独立设置', () async {
    final parent = task('repeat-parent')..status = TaskStatus.completed;
    await IosTaskReminderPreferences.save(parent.uid, 1);
    final next = task('repeat-next')..fromUid = parent.uid;
    await TaskReminder.syncAll([parent, next]);
    expect(IosTaskReminderPreferences.modeFor(next.uid), 1);
    final later = task('repeat-later')..fromUid = next.uid;
    await TaskReminder.syncAll([later]);
    expect(IosTaskReminderPreferences.modeFor(later.uid), 1);
    expect(
        alarmCalls.where((c) => c.method == 'scheduleTaskAlarm'), hasLength(2));
  });

  for (final deleting in [false, true]) {
    test('延迟排程等待期间${deleting ? '删除' : '完成'}不会留下旧闹钟', () async {
      final native = task(deleting ? 'snooze-delete' : 'snooze-complete');
      final tasks = <Task>[native].obs;
      Get.put(tasks, tag: 'taskList');
      await IosTaskReminderPreferences.save(native.uid, 1);
      final started = Completer<void>();
      final authorized = Completer<bool>();
      final events = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(alarms, (call) async {
        events.add(call.method);
        if (call.method == 'scheduleTaskAlarm') {
          started.complete();
          final result = await authorized.future;
          events.add('scheduleFinished');
          return result;
        }
        return true;
      });
      final delayed = TaskReminder.snooze(native, const Duration(minutes: 10));
      await started.future;
      if (deleting) {
        tasks.clear();
      } else {
        native.status = TaskStatus.completed;
      }
      final updated = TaskReminder.syncAll(tasks);
      await Future<void>.delayed(Duration.zero);
      authorized.complete(true);
      await Future.wait([delayed, updated]);
      expect(events.last, 'cancelTaskAlarm');
    });
  }

  testWidgets('新建页能选择原生闹钟，取消编辑不持久化', (tester) async {
    final draft = task('canceled-draft');
    await tester.pumpWidget(CupertinoApp(
      home: Builder(
          builder: (context) => CupertinoButton(
                child: const Text('打开'),
                onPressed: () => showCupertinoModalPopup<void>(
                  context: context,
                  builder: (_) => TaskCreatePage(draft),
                ),
              )),
    ));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('原生闹钟'));
    await tester.tap(find.text('原生闹钟'));
    await tester.pumpAndSettle();
    expect(IosTaskReminderPreferences.modeFor(draft.uid), 0);
    await tester.tap(find.byIcon(CupertinoIcons.xmark).first);
    await tester.pumpAndSettle();
    expect(IosTaskReminderPreferences.modeFor(draft.uid), 0);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('iPad 新建页在宽屏和窄窗口保留方式选择，保存后生效', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    final draft = task('saved-ipad-draft');
    Task? saved;
    await tester.pumpWidget(CupertinoApp(
      home: Builder(
          builder: (context) => CupertinoButton(
                child: const Text('打开'),
                onPressed: () async {
                  saved = await showCupertinoModalPopup<Task>(
                    context: context,
                    builder: (_) => TaskCreatePage(draft),
                  );
                },
              )),
    ));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('原生闹钟'));
    await tester.tap(find.text('原生闹钟'));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(430, 600);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(
        tester
            .widget<CupertinoSlidingSegmentedControl<int>>(
                find.byType(CupertinoSlidingSegmentedControl<int>))
            .groupValue,
        1);
    await tester.runAsync(() async {
      await tester.tap(find.text('新建').last);
      await db.optionsBox.flush();
    });
    await tester.pumpAndSettle();
    expect(saved?.uid, draft.uid);
    expect(IosTaskReminderPreferences.modeFor(draft.uid), 1);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('iPad 紧凑窗口时间面板可以滚动而不溢出', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(500, 400);
    tester.view.devicePixelRatio = 1;
    final draft = task('compact-panel')..type = TaskType.fixed;
    await tester.pumpWidget(CupertinoApp(
      home: Builder(
          builder: (context) => CupertinoButton(
                child: const Text('打开'),
                onPressed: () => showTaskTimePanel(
                  context,
                  task: draft,
                  onChanged: () {},
                  onReminderModeChanged: (_) {},
                ),
              )),
    ));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('完成'));
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });

  for (final editing in [false, true]) {
    testWidgets('保存写入等待期间不能退出：${editing ? '编辑' : '新建'}', (tester) async {
      final delayed = _DelayedOptions(db.optionsBox);
      Get.delete<DatabaseHelper>(tag: 'db');
      db = DatabaseHelper()..optionsBox = delayed;
      Get.put(db, tag: 'db');
      final draft = task(editing ? 'pending-edit' : 'pending-create');
      final navigator = GlobalKey<NavigatorState>();
      Task? saved;
      await tester.pumpWidget(CupertinoApp(
        navigatorKey: navigator,
        home: Builder(
            builder: (context) => CupertinoButton(
                  child: const Text('打开'),
                  onPressed: () async {
                    saved = await Navigator.of(context)
                        .push<Task>(CupertinoPageRoute(
                      builder: (_) =>
                          editing ? TaskEditPage(draft) : TaskCreatePage(draft),
                    ));
                  },
                )),
      ));
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      if (editing) {
        await tester.tap(find.byIcon(CupertinoIcons.check_mark).first);
      } else {
        await tester.tap(find.text('新建').last);
      }
      await delayed.started.future;
      await tester.pump();
      await navigator.currentState!.maybePop();
      await tester.pumpAndSettle();
      final keptEditing = find
          .byType(editing ? TaskEditPage : TaskCreatePage)
          .evaluate()
          .isNotEmpty;
      delayed.allow.complete();
      await tester.pumpAndSettle();
      expect(keptEditing, isTrue);
      expect(saved?.uid, draft.uid);
      expect(find.text('打开'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
