import 'package:celechron/page/scholar/course_detail/course_detail_view.dart';
import 'package:celechron/design/app_route.dart';
import 'package:celechron/design/custom_colors.dart';
import 'package:flutter/cupertino.dart';

import 'package:celechron/model/session.dart';

/// ===== 课表卡片「只留颜色、不留字」的全局状态（2026-10-01）=====
///
/// 用户要求：「长按课程卡片的空白处，把所有课程卡片上的文字都藏起来」。
///
/// 为什么做成全局而不是某个页面里的局部状态：同一个学期有**两处**课表
/// （日程标签页里的课表、学业标签页里的课表）。长按藏起来之后换一处看，
/// 文字当然也该是藏着的 —— 否则用户得藏两遍。
/// 学业页那个开关现在也是这一个状态（开关和长按完全等价）。
final ValueNotifier<bool> courseCardHideText = ValueNotifier<bool>(false);

void toggleCourseCardHideText() {
  courseCardHideText.value = !courseCardHideText.value;
}

class SessionCard extends StatefulWidget {
  final List<Session> sessionList;

  /// 卡片底色。不传就按课程 id 从粉色板里取一个
  /// （同一门课永远是同一个颜色，见 CoursePalette）。
  final Color? backgroundColor;

  const SessionCard({
    super.key,
    required this.sessionList,
    this.backgroundColor,
  });

  @override
  State<SessionCard> createState() => _SessionCardState();
}

class _SessionCardState extends State<SessionCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      reverseDuration: const Duration(milliseconds: 400),
    );
    _scaleAnimation = Tween<double>(begin: 1, end: 0.95).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 长按切换"藏不藏字"只重建这一层：卡片自己的按压缩放动画状态不受影响。
    return ValueListenableBuilder<bool>(
      valueListenable: courseCardHideText,
      builder: (BuildContext context, bool hideText, Widget? _) =>
          _buildCard(context, hideText),
    );
  }

  Widget _buildCard(BuildContext context, bool hideText) {
    var isDown = false;
    var isCancel = false;

    String sessionName = "";
    String sessionLocation = "";
    if (!hideText) {
      if (widget.sessionList.length == 1) {
        sessionName = widget.sessionList[0].name;
        sessionLocation = widget.sessionList[0].location ?? '未知地点';
      } else {
        sessionName = "冲突课程\n";
        for (var i in widget.sessionList) {
          sessionName =
              '$sessionName\n${i.time.first}-${i.time.last}: ${i.name}';
        }
      }
    }

    return GestureDetector(
      // 长按卡片（空白处也算）= 把字藏起来 / 放出来
      onLongPress: toggleCourseCardHideText,
      onTapDown: (_) async {
        isDown = true;
        isCancel = false;
        _animationController.forward();
        await Future.delayed(const Duration(milliseconds: 125));
        isDown = false;
        if (isCancel) {
          _animationController.reverse();
          isCancel = false;
        }
      },
      onTapUp: (_) async {
        isCancel = true;
        if (!isDown) _animationController.reverse();
      },
      onTapCancel: () => _animationController.reverse(),
      onTap: () async {
        if (widget.sessionList.length == 1) {
          Navigator.of(context).push(
            appPageRoute(
              builder: (context) =>
                  CourseDetailPage(courseId: widget.sessionList[0].id),
              title: widget.sessionList[0].name,
            ),
          );
        } else {
          await showCupertinoDialog(
            context: context,
            builder: (BuildContext context) {
              return CupertinoAlertDialog(
                title: const Text(
                  '要查看哪一个？',
                ),
                content: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var s in widget.sessionList)
                      CupertinoButton(
                        minimumSize: const Size(22.0, 22.0),
                        padding:
                            const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 0.0),
                        child: Text(
                          s.name,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onPressed: () {
                          Navigator.of(context).push(
                            appPageRoute(
                              builder: (context) =>
                                  CourseDetailPage(courseId: s.id),
                              title: s.name,
                            ),
                          );
                        },
                      ),
                  ],
                ),
                actions: [
                  CupertinoDialogAction(
                    child: const Text('返回'),
                    onPressed: () async {
                      Navigator.of(context).pop();
                    },
                  )
                ],
              );
            },
          );
        }
      },
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Container(
          padding: const EdgeInsets.only(
            top: 1.4,
            bottom: 1.4,
            left: 1.4,
            right: 1.4,
          ),
          child: Container(
            alignment: Alignment.topCenter,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              color: CupertinoDynamicColor.resolve(
                  widget.backgroundColor ??
                      CoursePalette.of(widget.sessionList.isEmpty
                          ? null
                          : widget.sessionList.first.id),
                  context),
            ),
            child: ClipRect(
              child: Padding(
                padding: const EdgeInsets.only(
                    left: 2.0, right: 2.0, top: 2.0, bottom: 2.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Flexible(
                      fit: FlexFit.loose,
                      child: Text(
                        sessionName,
                        textAlign: TextAlign.center,
                        maxLines: widget.sessionList.length == 1
                            ? 3 // 单课程最多3行
                            : (widget.sessionList.length * 2)
                                .clamp(2, 6), // 冲突课程最多6行
                        overflow: TextOverflow.ellipsis,
                        style: CupertinoTheme.of(context)
                            .textTheme
                            .textStyle
                            .copyWith(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: const Color.fromRGBO(255, 255, 255, 1.0),
                            ),
                      ),
                    ),
                    if (!hideText && sessionLocation.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Flexible(
                        fit: FlexFit.loose,
                        child: Text(
                          sessionLocation,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: CupertinoTheme.of(context)
                              .textTheme
                              .textStyle
                              .copyWith(
                                fontSize: 9,
                                color: const Color.fromRGBO(255, 255, 255, 0.9),
                              ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
