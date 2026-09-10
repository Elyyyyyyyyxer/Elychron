import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'package:celechron/page/scholar/scholar_view.dart';
import 'package:celechron/page/search/search_view.dart';
import 'package:celechron/page/flow/flow_view.dart';
import 'package:celechron/page/task/task_view.dart';
import 'package:celechron/page/calendar/calendar_view.dart';
import 'package:celechron/page/option/option_view.dart';
import 'package:celechron/page/task/task_alarm_page.dart';
import 'package:celechron/page/task/task_create_page.dart';
import 'package:celechron/page/task/task_controller.dart';
import 'package:celechron/model/task.dart';
import 'package:celechron/utils/attachment_helper.dart';
import 'package:celechron/utils/share_receiver.dart';
import 'package:celechron/utils/task_alarm_center.dart';
import 'package:celechron/utils/utils.dart';

import 'package:celechron/worker/fuse.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.title});

  final String title;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _indexNum = 0;
  final CupertinoTabController _controller = CupertinoTabController();
  double _horizontalDragDistance = 0.0; // 跟踪水平拖动距离
  StreamSubscription<List<SharedItem>>? _shareSubscription;
  bool _handlingShare = false;

  @override
  void initState() {
    super.initState();
    _controller.index = 0;
    initFuse();
    _listenShares();
    TaskAlarmCenter.current.addListener(_onAlarm);
  }

  @override
  void dispose() {
    TaskAlarmCenter.current.removeListener(_onAlarm);
    _shareSubscription?.cancel();
    super.dispose();
  }

  /// 闹钟到点：弹出全屏闹钟页
  void _onAlarm() {
    final task = TaskAlarmCenter.current.value;
    if (task == null || !mounted) return;
    Navigator.of(context, rootNavigator: true).push(
      CupertinoPageRoute(
        builder: (BuildContext context) => TaskAlarmPage(task: task),
        fullscreenDialog: true,
      ),
    );
  }

  /// 接收系统分享面板发来的图片/文件/文本 → 直接打开新建待办
  Future<void> _listenShares() async {
    try {
      final initial = await ShareReceiver.getInitial();
      if (initial.isNotEmpty) {
        await _handleShared(initial);
      }
      _shareSubscription = ShareReceiver.stream.listen((items) {
        _handleShared(items);
      });
    } catch (_) {
      // 平台不支持时静默跳过
    }
  }

  Future<void> _handleShared(List<SharedItem> items) async {
    if (items.isEmpty || _handlingShare || !mounted) return;
    _handlingShare = true;
    try {
      // 先把分享过来的文件复制到应用附件目录
      final attachments = <TaskAttachment>[];
      String title = '';
      for (final item in items) {
        if (title.isEmpty && (item.text?.trim().isNotEmpty ?? false)) {
          title = item.text!.trim();
        }
        final path = item.path;
        if (path != null) {
          final copied = await copyToAttachments(path, item.name ?? '分享的文件');
          if (copied != null) attachments.add(copied);
        }
      }

      // 切到「待办」页，再弹出新建窗口
      changeIndex(2);
      await Future.delayed(const Duration(milliseconds: 260));
      if (!mounted) return;

      final now = DateTime.now();
      final draft = Task(
        endTime: DateTime(now.year, now.month, now.day, 23, 59),
        startTime: DateTime(now.year, now.month, now.day, 23, 59),
        repeatEndsTime: dateOnly(now),
      );
      draft.reset();
      final end = DateTime(now.year, now.month, now.day, 23, 59);
      draft.startTime = end;
      draft.endTime = end;
      draft.repeatEndsTime = dateOnly(end);
      draft.summary = title;
      draft.attachments = attachments;

      final res = await showCupertinoModalPopup<Task>(
        context: context,
        builder: (BuildContext context) => TaskCreatePage(draft),
      );
      if (res == null || !mounted) return;
      if (res.status == TaskStatus.deleted) return;

      final taskList = Get.find<RxList<Task>>(tag: 'taskList');
      taskList.add(res);
      final controller = Get.find<TaskController>();
      controller.updateDeadlineList();
      controller.updateDeadlineListTime();
      controller.taskList.refresh();
    } finally {
      _handlingShare = false;
    }
  }

  void changeIndex(int index) {
    if (_indexNum != index) {
      setState(() {
        _indexNum = index;
        _controller.index = index;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoTabScaffold(
      controller: _controller,
      tabBuilder: (context, index) => CupertinoTabView(
        builder: (context) => _getPagesWidget(index),
      ),
      tabBar: CupertinoTabBar(
        iconSize: 26,
        backgroundColor: CupertinoDynamicColor.resolve(
                CupertinoColors.secondarySystemBackground, context)
            .withValues(alpha: 0.5),
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.time),
            label: '接下来',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.calendar),
            label: '日程',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.check_mark),
            label: '待办',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.school_rounded),
            label: '学业',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.settings),
            label: '设置',
          ),
        ],
        currentIndex: _indexNum,
        onTap: (int index) {
          if (index != _indexNum) {
            setState(() {
              _indexNum = index;
            });
          }
        },
      ),
    );
  }

  Widget _getPagesWidget(int index) {
    List<Widget> widgetList = [
      FlowPage(),
      CalendarPage(),
      TaskPage(),
      ScholarPage(),
      OptionPage(),
      SearchPage(), // 缓存一下
    ];

    return Offstage(
      offstage: _indexNum != index,
      child: TickerMode(
        enabled: _indexNum == index,
        child: GestureDetector(
          // 使用 onHorizontalDrag 专门处理水平滑动，不会干扰垂直滚动
          onHorizontalDragStart: (_) {
            // 初始化拖动距离
            _horizontalDragDistance = 0.0;
          },
          onHorizontalDragUpdate: (details) {
            // 累积水平拖动距离
            _horizontalDragDistance += details.delta.dx;
          },
          onHorizontalDragEnd: (details) {
            // 根据滑动速度和距离判断是否切换页面
            final screenWidth = MediaQuery.of(context).size.width;
            final velocity = details.primaryVelocity ?? 0;
            final threshold = screenWidth * 0.15; // 滑动距离阈值（屏幕宽度的15%）

            // 向右滑动（显示左侧页面）- 向右滑动意味着显示前一个页面
            if (velocity > 200 || _horizontalDragDistance > threshold) {
              if (_indexNum > 0) {
                changeIndex(_indexNum - 1);
              }
            }
            // 向左滑动（显示右侧页面）- 向左滑动意味着显示后一个页面
            else if (velocity < -200 || _horizontalDragDistance < -threshold) {
              if (_indexNum < 4) {
                changeIndex(_indexNum + 1);
              }
            }
            // 重置状态
            _horizontalDragDistance = 0.0;
          },
          onHorizontalDragCancel: () {
            // 取消时重置状态
            _horizontalDragDistance = 0.0;
          },
          // 使用 deferToChild 让子组件的垂直滚动优先处理
          behavior: HitTestBehavior.deferToChild,
          child: widgetList[index],
        ),
      ),
    );
  }

  Future<void> initFuse() async {
    await Future.delayed(const Duration(seconds: 1));
    var fuse = Get.find<Rx<Fuse>>(tag: 'fuse');
    var response =
        await fuse.value.checkUpdate().whenComplete(() => fuse.refresh());
    if (response != null) {
      if (!mounted) return;
      showCupertinoDialog(
          context: context,
          builder: (context) {
            return CupertinoAlertDialog(
              title: const Text('更新可用'),
              content: Text(response),
              actions: [
                CupertinoDialogAction(
                  child: const Text('忽略'),
                  onPressed: () async {
                    Navigator.of(context).pop();
                  },
                ),
                CupertinoDialogAction(
                  child: const Text('访问网站'),
                  onPressed: () async {
                    await launchUrlString(
                      'https://celechron.top',
                      mode: LaunchMode.externalApplication,
                    );
                  },
                ),
              ],
            );
          });
    }
  }
}
