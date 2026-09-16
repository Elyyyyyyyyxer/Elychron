import 'package:celechron/mod/course_mount_store.dart';
import 'package:celechron/model/course_mount.dart';
import 'package:celechron/model/task.dart';
import 'package:flutter_test/flutter_test.dart';

/// 课程挂载（资料 / 评论）的存取口径。
///
/// 这一层没有界面、也不碰 Hive 盒子，所以能纯单测 —— 而这正是它值得测的地方：
/// 序列化一旦写错，用户存进去的评论/资料就会**静默消失**（读回来是空的），
/// 那种 bug 只有在真机上丢数据时才被发现。
void main() {
  group('CourseMount 序列化', () {
    test('附件与评论能原样往返', () {
      final mount = CourseMount(
        courseId: 'CS101',
        attachments: [
          TaskAttachment(name: '课件1.pdf', path: '/data/files/a.pdf', size: 1234),
          TaskAttachment(name: '板书.jpg', path: '/data/files/b.jpg', size: 99),
        ],
        comments: [
          TaskComment(content: '老师说要考第三章', time: DateTime(2026, 9, 15, 8)),
        ],
      );

      final restored = CourseMount.fromMap('CS101', mount.toMap());

      expect(restored.courseId, 'CS101');
      expect(restored.attachments.map((e) => e.name), ['课件1.pdf', '板书.jpg']);
      expect(restored.attachments.map((e) => e.path),
          ['/data/files/a.pdf', '/data/files/b.jpg']);
      expect(restored.attachments.map((e) => e.size), [1234, 99]);
      expect(restored.comments.single.content, '老师说要考第三章');
      expect(restored.comments.single.time, DateTime(2026, 9, 15, 8));
    });

    test('空挂载往返后仍然空（并且 isEmpty 为真，界面据此不渲染这一块）', () {
      final restored = CourseMount.fromMap('CS101', CourseMount(courseId: 'CS101').toMap());
      expect(restored.isEmpty, isTrue);
      expect(restored.attachments, isEmpty);
      expect(restored.comments, isEmpty);
    });

    test('读到脏数据时丢掉坏的那一条，不让整门课崩', () {
      // 真实场景：老版本存的、或者写了一半的数据
      final restored = CourseMount.fromMap('CS101', {
        'attachments': [
          {'name': '好的.pdf', 'path': '/p', 'size': 1},
          '这不是个 Map',
          {'name': '少了 size', 'path': '/q'},
        ],
        'comments': '这不是个 List',
      });

      expect(restored.attachments.length, 2);
      expect(restored.attachments.first.name, '好的.pdf');
      expect(restored.attachments.last.size, 0); // 缺字段按默认值
      expect(restored.comments, isEmpty);
    });

    test('完全没有记录时返回空对象而不是 null', () {
      final restored = CourseMount.fromMap('CS101', null);
      expect(restored.courseId, 'CS101');
      expect(restored.isEmpty, isTrue);
    });
  });

  group('关联待办按 courseId 筛', () {
    Task make(String uid,
            {String? courseId, TaskStatus status = TaskStatus.running}) =>
        Task(
          uid: uid,
          endTime: DateTime(2026, 9, 15),
          startTime: DateTime(2026, 9, 15),
          repeatEndsTime: DateTime(2026, 9, 15),
        )
          ..summary = uid
          ..courseId = courseId
          ..status = status;

    test('只挑这门课的，跳过已删除/已作废，但保留已完成', () {
      final tasks = [
        make('a', courseId: 'CS101'),
        make('b', courseId: 'CS102'),
        make('c', courseId: 'CS101', status: TaskStatus.deleted),
        make('d', courseId: 'CS101', status: TaskStatus.outdated),
        make('e', courseId: 'CS101', status: TaskStatus.completed),
        make('f'),
      ];
      final mine = tasksForCourse(tasks, 'CS101');
      // 已完成**保留**：课程页要能看到"这门课我做完过什么"，
      // 折叠或隐藏是界面的事，不该在数据层替它决定。
      expect(mine.map((t) => t.uid), ['a', 'e']);
    });

    test('课程代码为空时返回空列表（没挂课程的待办永远不该出现在课程页）', () {
      final tasks = [make('a'), make('b', courseId: 'CS101')];
      expect(tasksForCourse(tasks, ''), isEmpty);
    });
  });

  // ===== AI 生成待办：模型只回课程名，我们负责落到课程代码上 =====
  //
  // 为什么不让模型直接回课程代码：那是教务内部的东西，它不知道，硬要只会编造。
  // 所以让它从我们给的课表里挑名字，这里再做匹配；**匹配不上就不挂课**（宁可不挂，
  // 不挂错课），这也是用户明确要求的口径。
  group('课程名 → 课程代码', () {
    final choices = <({String id, String name})>[
      (id: 'MATH101', name: '线性代数I（H）'),
      (id: 'CS201', name: '程序设计与算法基础'),
      (id: 'PHY110', name: '大学物理（甲）II'),
    ];

    test('完全一样 → 命中', () {
      expect(resolveCourseId('程序设计与算法基础', choices), 'CS201');
    });

    test('全角/半角括号、空格差异 → 仍然命中（归一化后比较）', () {
      expect(resolveCourseId('线性代数 I (H)', choices), 'MATH101');
      expect(resolveCourseId('线性代数I(H)', choices), 'MATH101');
    });

    test('一边包含另一边 → 命中（模型爱写简称）', () {
      expect(resolveCourseId('线性代数', choices), 'MATH101');
      expect(resolveCourseId('大学物理', choices), 'PHY110');
    });

    test('课表里没有这门课 → null（不硬套一门课）', () {
      expect(resolveCourseId('量子力学导论', choices), isNull);
    });

    test('模型留空 → null（用户要求：没提到课程就不传这个字段）', () {
      expect(resolveCourseId('', choices), isNull);
      expect(resolveCourseId('   ', choices), isNull);
    });

    test('拿不到课表（候选为空）→ null，不会崩', () {
      expect(resolveCourseId('线性代数', const []), isNull);
    });
  });
}
