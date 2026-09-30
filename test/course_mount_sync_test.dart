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

  test('删掉的资料带墓碑 → 不会再被对方带回来', () {
    final merged = DataMerge.mergeCourseMounts(
      <Map<String, dynamic>>[
        mount('CS101', attachments: <Map<String, dynamic>>[file('/keep.pdf')]),
      ],
      <Map<String, dynamic>>[
        mount('CS101', attachments: <Map<String, dynamic>>[
          file('/keep.pdf'),
          file('/deleted.pdf'),
        ]),
      ],
      deletedKeys: <String>{'CS101|a|/deleted.pdf'},
    );
    final paths = (merged.single['attachments'] as List<dynamic>)
        .map((item) => (item as Map)['path'])
        .toList();
    expect(paths, <String>['/keep.pdf']);
  });

  test('删掉的评论同样不会回来（键是 内容@时间）', () {
    final merged = DataMerge.mergeCourseMounts(
      <Map<String, dynamic>>[mount('CS101')],
      <Map<String, dynamic>>[
        mount('CS101', comments: <Map<String, dynamic>>[comment('删了它', 100)]),
      ],
      deletedKeys: <String>{'CS101|c|删了它@100'},
    );
    expect((merged.single['comments'] as List<dynamic>), isEmpty);
  });

  test('墓碑只对那一门课那一条生效，不会误伤别的', () {
    final merged = DataMerge.mergeCourseMounts(
      <Map<String, dynamic>>[],
      <Map<String, dynamic>>[
        mount('CS101', attachments: <Map<String, dynamic>>[file('/a.pdf')]),
        mount('CS102', attachments: <Map<String, dynamic>>[file('/a.pdf')]),
      ],
      deletedKeys: <String>{'CS101|a|/a.pdf'},
    );
    final byCourse = <String, int>{
      for (final item in merged)
        item['courseId'] as String: (item['attachments'] as List).length,
    };
    expect(byCourse['CS101'], 0);
    expect(byCourse['CS102'], 1);
  });

  test('两边都空 → 空', () {
    expect(
      DataMerge.mergeCourseMounts(
          <Map<String, dynamic>>[], <Map<String, dynamic>>[]),
      isEmpty,
    );
  });

  // ===== 2026-09-30：真机上发现"同一张图出现 4 次" =====
  //
  // 原因：从网盘取回来的文件落在各自的 task_attachments/ 下、名字里带本机
  // 时间戳，所以两台设备上**同一个文件的 path 必然不同**。按 path 去重的话，
  // 两边一合就是两份，再同步一轮四份；而且"多出来的那份"每次同步还会被当成
  // 缺失再下载一遍（流量和坚果云配额就是这么被吃掉的）。
  test('同一个文件在两端的本地路径不同 → 只留一条（本次修的坑）', () {
    final merged = DataMerge.mergeCourseMounts(
      <Map<String, dynamic>>[
        mount('CS101', attachments: <Map<String, dynamic>>[
          <String, dynamic>{
            'name': '四则规则.jpg',
            'path': '/phone/task_attachments/1789_四则规则.jpg',
            'size': 173900,
          },
        ]),
      ],
      <Map<String, dynamic>>[
        mount('CS101', attachments: <Map<String, dynamic>>[
          <String, dynamic>{
            'name': '四则规则.jpg',
            'path': '/desktop/task_attachments/1790_四则规则.jpg',
            'size': 173900,
          },
        ]),
      ],
    );
    final attachments = merged.single['attachments'] as List<dynamic>;
    expect(attachments.length, 1);
    // 留下的是本机那份（本地路径还有效的那个），不是对方的
    expect((attachments.single as Map)['path'],
        '/phone/task_attachments/1789_四则规则.jpg');
  });

  test('名字相同但大小不同 → 是两个文件，都留着', () {
    final merged = DataMerge.mergeCourseMounts(
      <Map<String, dynamic>>[
        mount('CS101', attachments: <Map<String, dynamic>>[
          <String, dynamic>{'name': 'a.jpg', 'path': '/p/a.jpg', 'size': 1},
        ]),
      ],
      <Map<String, dynamic>>[
        mount('CS101', attachments: <Map<String, dynamic>>[
          <String, dynamic>{'name': 'a.jpg', 'path': '/d/a.jpg', 'size': 2},
        ]),
      ],
    );
    expect((merged.single['attachments'] as List<dynamic>).length, 2);
  });

  test('按身份记的墓碑也认（另一端路径不同也删得掉）', () {
    final merged = DataMerge.mergeCourseMounts(
      <Map<String, dynamic>>[
        mount('CS101', attachments: <Map<String, dynamic>>[file('/keep.pdf')]),
      ],
      <Map<String, dynamic>>[
        mount('CS101', attachments: <Map<String, dynamic>>[
          <String, dynamic>{
            'name': 'x.jpg',
            'path': '/desktop/task_attachments/1790_x.jpg',
            'size': 5,
          },
        ]),
      ],
      deletedKeys: <String>{'CS101|a2|x.jpg@5'},
    );
    final paths = (merged.single['attachments'] as List<dynamic>)
        .map((item) => (item as Map)['path'])
        .toList();
    expect(paths, <String>['/keep.pdf']);
  });

  test('老数据没有 name → 退回按 path 去重，不会把两份不同的文件吞掉', () {
    final merged = DataMerge.mergeCourseMounts(
      <Map<String, dynamic>>[
        mount('CS101', attachments: <Map<String, dynamic>>[
          <String, dynamic>{'path': '/p/a.jpg'},
        ]),
      ],
      <Map<String, dynamic>>[
        mount('CS101', attachments: <Map<String, dynamic>>[
          <String, dynamic>{'path': '/d/a.jpg'},
        ]),
      ],
    );
    expect((merged.single['attachments'] as List<dynamic>).length, 2);
  });
}
