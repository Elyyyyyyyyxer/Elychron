import 'package:celechron/utils/data_sync.dart';
import 'package:flutter_test/flutter_test.dart';

/// 课程挂载（课程详情里的**资料 / 评论**）的同步合并。
///
/// 背景（用户 2026-09-19）：「课程挂载的文件、评论、待办好像没有同步」——
/// 查下来 indeed：它们存在 DatabaseHelper.courseMountBox 里，
/// 而 DataBundle 从来没带过，所以这门数据一直没参与同步。
///
/// 合并口径是**并集，谁都不丢**（用户要求"直接同步"）：
/// 资料按 path 去重、评论按"内容 + 时间"去重。
void main() {
  Map<String, dynamic> mount(String courseId,
          {List<Map<String, dynamic>> attachments = const [],
          List<Map<String, dynamic>> comments = const []}) =>
      <String, dynamic>{
        'courseId': courseId,
        'attachments': attachments,
        'comments': comments,
      };

  Map<String, dynamic> file(String path) =>
      <String, dynamic>{'name': path.split('/').last, 'path': path, 'size': 1};

  Map<String, dynamic> comment(String content, int time) =>
      <String, dynamic>{'content': content, 'time': time};

  test('两台各有一门课的资料 → 都在（并集）', () {
    final merged = DataMerge.mergeCourseMounts(
      <Map<String, dynamic>>[
        mount('CS101', attachments: <Map<String, dynamic>>[file('/a.pdf')]),
      ],
      <Map<String, dynamic>>[
        mount('CS102', attachments: <Map<String, dynamic>>[file('/b.pdf')]),
      ],
    );
    expect(merged.length, 2);
    expect(
      merged.map((m) => m['courseId']).toSet(),
      <String>{'CS101', 'CS102'},
    );
  });

  test('同一门课两边各加一个文件 → 两个都在', () {
    final merged = DataMerge.mergeCourseMounts(
      <Map<String, dynamic>>[
        mount('CS101', attachments: <Map<String, dynamic>>[file('/a.pdf')]),
      ],
      <Map<String, dynamic>>[
        mount('CS101', attachments: <Map<String, dynamic>>[file('/b.pdf')]),
      ],
    );
    final attachments = merged.single['attachments'] as List<dynamic>;
    expect(attachments.length, 2);
  });

  test('同一个文件（同 path）两边都有 → 只留一条，不重复', () {
    final merged = DataMerge.mergeCourseMounts(
      <Map<String, dynamic>>[
        mount('CS101', attachments: <Map<String, dynamic>>[file('/same.pdf')]),
      ],
      <Map<String, dynamic>>[
        mount('CS101', attachments: <Map<String, dynamic>>[file('/same.pdf')]),
      ],
    );
    expect((merged.single['attachments'] as List<dynamic>).length, 1);
  });

  test('评论按"内容 + 时间"去重：同一条不重复，不同时间算两条', () {
    final merged = DataMerge.mergeCourseMounts(
      <Map<String, dynamic>>[
        mount('CS101', comments: <Map<String, dynamic>>[comment('记一下', 100)]),
      ],
      <Map<String, dynamic>>[
        mount('CS101', comments: <Map<String, dynamic>>[
          comment('记一下', 100),
          comment('记一下', 200),
        ]),
      ],
    );
    expect((merged.single['comments'] as List<dynamic>).length, 2);
  });

  test('没有 courseId 的脏数据被丢掉，不会崩', () {
    final merged = DataMerge.mergeCourseMounts(
      <Map<String, dynamic>>[
        <String, dynamic>{'attachments': <dynamic>[]},
      ],
      <Map<String, dynamic>>[],
    );
    expect(merged, isEmpty);
  });

  test('两边都空 → 空', () {
    expect(
      DataMerge.mergeCourseMounts(
          <Map<String, dynamic>>[], <Map<String, dynamic>>[]),
      isEmpty,
    );
  });
}
