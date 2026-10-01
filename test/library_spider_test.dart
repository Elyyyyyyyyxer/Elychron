import 'dart:io';

import 'package:celechron/http/library_spider.dart';
import 'package:celechron/mod/library_tasks.dart';
import 'package:celechron/mod/library_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// 图书馆空间预约系统（2026-10-01）。
///
/// 只测**纯逻辑**：cookie jar（跨域不串味）与响应解析。
/// 网络与 CAS 登录必须在真机上验（单测不该打真服务）。
void main() {
  group('cookie jar', () {
    test('记住自己域的 cookie，并拼成请求头', () {
      final jar = LibraryCookieJar();
      jar.absorb(Uri.parse('https://booking.lib.zju.edu.cn/api/cas/cas'), <Cookie>[
        Cookie('PHPSESSID', 'abc123'),
      ]);
      expect(jar.length, 1);
      expect(jar.headerFor(Uri.parse('https://booking.lib.zju.edu.cn/api/Member/my')),
          'PHPSESSID=abc123');
    });

    test('别的域的 cookie 不会串进来（zjuam 的 SSO 不该带给业务站）', () {
      final jar = LibraryCookieJar();
      jar.absorb(Uri.parse('https://booking.lib.zju.edu.cn/'), <Cookie>[
        Cookie('PHPSESSID', 'abc'),
      ]);
      jar.absorb(Uri.parse('https://zjuam.zju.edu.cn/cas/login'), <Cookie>[
        Cookie('iPlanetDirectoryPro', 'sso-value'),
      ]);
      // 两份都记着（各自域）
      expect(jar.length, 2);
      // 但发给业务站的头里**不能**出现 zjuam 的 SSO cookie
      expect(
        jar.headerFor(Uri.parse('https://booking.lib.zju.edu.cn/api/Member/my')),
        'PHPSESSID=abc',
      );
      // 反过来，发给 zjuam 的也只有它自己那份
      expect(
        jar.headerFor(Uri.parse('https://zjuam.zju.edu.cn/cas/login')),
        'iPlanetDirectoryPro=sso-value',
      );
    });

    test('父域 cookie（.zju.edu.cn）能被业务站接受', () {
      final jar = LibraryCookieJar();
      final cookie = Cookie('token', 't1')..domain = '.zju.edu.cn';
      jar.absorb(Uri.parse('https://booking.lib.zju.edu.cn/'), <Cookie>[cookie]);
      expect(jar.length, 1);
    });

    test('空值等于删除', () {
      final jar = LibraryCookieJar();
      jar.absorb(Uri.parse('https://booking.lib.zju.edu.cn/'), <Cookie>[Cookie('PHPSESSID', 'x')]);
      jar.absorb(Uri.parse('https://booking.lib.zju.edu.cn/'), <Cookie>[Cookie('PHPSESSID', '')]);
      expect(jar.isEmpty, isTrue);
    });
  });

  group('公告解析（fixture 是实测响应）', () {
    test('notice 响应能解析出标题（用 2026-10-01 实抓的那条）', () {
      // 实测：{"code":1,"data":{"total":13,"per_page":15,"current_page":1,
      //        "last_page":1,"data":[{"id":"49","title":"关于考试周期间主馆启用临时阅览区域的通知",...}]}}
      final body = <String, dynamic>{
        'code': 1,
        'data': <String, dynamic>{
          'total': 13,
          'current_page': 1,
          'data': <dynamic>[
            <String, dynamic>{
              'id': '49',
              'title': '关于考试周期间主馆启用临时阅览区域的通知',
              'create_time': '2026-01-01 10:00:00',
            },
          ],
        },
      };
      // 复用 spider 的解析路径：这里直接调 it（不经过网络）
      final notices = LibrarySpider.noticesFrom(body);
      expect(notices, hasLength(1));
      expect(notices.single.title, contains('考试周'));
      expect(notices.single.id, '49');
    });

    test('结构变了也不炸（拿到意料之外的形状就当空）', () {
      expect(LibrarySpider.noticesFrom(<String, dynamic>{'code': 1, 'data': 'oops'}), isEmpty);
      expect(LibrarySpider.noticesFrom(null), isEmpty);
    });
  });

  group('预约解析（防御式，字段名待真数据确认）', () {
    test('常见的几种键名都认', () {
      final parsed = LibrarySpider.reservationsFrom(<String, dynamic>{
        'code': 1,
        'data': <dynamic>[
          <String, dynamic>{
            'room_name': '三楼研讨间 A',
            'start_time': '2026-10-02 14:00:00',
            'end_time': '2026-10-02 16:00:00',
          },
          <String, dynamic>{'seat_name': '四楼 012 号', 'start_time': '2026-10-03 09:00:00'},
        ],
      });
      expect(parsed, hasLength(2));
      expect(parsed.first.title, '三楼研讨间 A');
      expect(parsed.first.start?.hour, 14);
      expect(parsed.last.title, '四楼 012 号');
    });

    test('认不出的脏数据被丢掉，不影响别的条目', () {
      final parsed = LibrarySpider.reservationsFrom(<String, dynamic>{
        'data': <dynamic>[
          <String, dynamic>{'foo': 'bar'},
          <String, dynamic>{'title': '正常的一条', 'end_time': '2026-10-05 20:00:00'},
        ],
      });
      expect(parsed, hasLength(1));
      expect(parsed.single.title, '正常的一条');
    });
    test('用真数据对过的字段名：beginTime / endTime / nameMerge（2026-10-01 实测）', () {
      final parsed = LibrarySpider.reservationsFrom(<String, dynamic>{
        'code': 1,
        'data': <String, dynamic>{
          'total': 1,
          'data': <dynamic>[
            <String, dynamic>{
              'id': '110004',
              'title': '团队讨论(班团,社团,兴趣小组,项目讨论)',
              'nameMerge': '主馆-二层-207(8人间)',
              'beginTime': '2026-09-27 15:00:00',
              'endTime': '2026-09-27 19:00:00',
              'statusname': '已使用',
            },
          ],
        },
      });
      expect(parsed, hasLength(1));
      final one = parsed.single;
      expect(one.place, '主馆-二层-207(8人间)');
      expect(one.status, '已使用');
      expect(one.start?.hour, 15);
      expect(one.end?.hour, 19);
      // 时段跨了 4 小时 —— 这正是"预约该走 startTime+endTime"而不是只有截止时间的原因
      expect(one.end!.difference(one.start!).inHours, 4);
    });

  group('从 WebView 的 JS 返回值里抠 token', () {
    test('带引号的字符串要脱掉引号', () {
      expect(LibraryConfig.tokenFromJavaScript('"abc.def.ghi"'), 'abc.def.ghi');
    });
    test('没有登录时返回的是 "null" / 空串，都当没有', () {
      expect(LibraryConfig.tokenFromJavaScript('null'), '');
      expect(LibraryConfig.tokenFromJavaScript('""'), '');
      expect(LibraryConfig.tokenFromJavaScript(null), '');
    });
    test('转义引号也处理（token 里带引号的极端情况）', () {
      expect(LibraryConfig.tokenFromJavaScript(r'"a\"b"'), 'a"b');
    });
  });

    test('粘贴进来的 token 很脏也能洗干净（前缀/换行/空白）', () {
      const clean = 'abcdef1234567890abcdef1234567890';
      expect(LibraryConfig.sanitizeToken('  ' + clean + '\n'), clean);
      expect(LibraryConfig.sanitizeToken('token=' + clean), clean);
      expect(LibraryConfig.sanitizeToken('authorization: ' + clean), clean);
      expect(LibraryConfig.sanitizeToken('Bearer ' + clean), clean);
    });

    test('★ 预约里的 timelist 不能算成额外预约（真机显示"7 条"就是这个 bug）', () {
      final parsed = LibrarySpider.reservationsFrom(<String, dynamic>{
        'code': 1,
        'data': <String, dynamic>{
          'total': 1,
          'data': <dynamic>[
            <String, dynamic>{
              'id': '110004',
              'title': '团队讨论',
              'nameMerge': '主馆-二层-207(8人间)',
              'beginTime': '2026-09-27 15:00:00',
              'endTime': '2026-09-27 19:00:00',
              'timelist': <dynamic>[
                <String, dynamic>{'start': '15:00', 'end': '16:00'},
                <String, dynamic>{'start': '16:00', 'end': '17:00'},
                <String, dynamic>{'start': '17:00', 'end': '18:00'},
                <String, dynamic>{'start': '18:00', 'end': '19:00'},
                <String, dynamic>{'start': '19:00', 'end': '20:00'},
                <String, dynamic>{'start': '20:00', 'end': '21:00'},
              ],
            },
          ],
        },
      });
      expect(parsed, hasLength(1), reason: 'timelist 只是这条预约的时间段，不是新预约');
    });

    test('★ 真机 seat 原始 JSON：座位号在 no、状态文案在 statusName（大写 N）', () {
      final parsed = LibrarySpider.reservationsFrom(<String, dynamic>{
        'code': 1,
        'data': <String, dynamic>{
          'total': 1,
          'per_page': 10,
          'current_page': 1,
          'last_page': 1,
          'data': <dynamic>[
            <String, dynamic>{
              'status': '8',
              'id': '2821887',
              'space': '6079',
              'nameMerge': '主馆-二层-二层北',
              'no': 'Z2F034',
              'name': 'Z2F034',
              'beginTime': '2026-10-01 17:44:22',
              'endTime': '2026-10-01 23:58:59',
              'statusName': '已结束',
              'timelist': <dynamic>[
                <String, dynamic>{'id': '10794485'},
              ],
            },
          ],
        },
      }, kind: 'seat');
      expect(parsed, hasLength(1));
      final seat = parsed.single;
      expect(seat.seatNo, 'Z2F034');
      expect(seat.place, '主馆-二层-二层北');
      expect(seat.status, '已结束');
      expect(seat.kind, 'seat');
      expect(libraryTaskTitle(seat), '图书馆座位 · Z2F034');
      expect(libraryPlaceDetail(seat), '主馆-二层-二层北 · Z2F034');
    });

    test('★ 真机 seminar 原始 JSON：statusname 小写也能认出来（已使用 → 不建待办）', () {
      final parsed = LibrarySpider.reservationsFrom(<String, dynamic>{
        'code': 1,
        'data': <String, dynamic>{
          'total': 1,
          'data': <dynamic>[
            <String, dynamic>{
              'id': '110004',
              'status': '4',
              'title': '团队讨论(班团,社团,兴趣小组,项目讨论)',
              'nameMerge': '主馆-二层-207(8人间)',
              'beginTime': '2026-09-27 15:00:00',
              'endTime': '2026-09-27 19:00:00',
              'statusname': '已使用',
            },
          ],
        },
      }, kind: 'seminar');
      expect(parsed, hasLength(1));
      final one = parsed.single;
      expect(one.status, '已使用');
      expect(one.place, '主馆-二层-207(8人间)');
      expect(libraryReservationKind(one), 'room');
      expect(
        libraryReservationWanted(one,
            now: DateTime.parse('2026-10-01 12:00:00')),
        isFalse,
        reason: '已使用 + 时间已过 → 一条待办都不该建',
      );
    });

  });
  /// 预约 → 待办 的纯逻辑（网络与 WebView 那部分只能在真机上验）
  group('预约 → 待办：该不该建、建成什么样', () {
    // 固定一个"现在"，免得测试跟着系统时钟漂（真机 2026-10-01）
    final now = DateTime.parse('2026-10-01 12:00:00');

    LibraryReservation r({
      String id = '110004',
      String title = '团队讨论',
      String place = '主馆-二层-207(8人间)',
      String status = '已预约',
      String? begin = '2026-10-02 15:00:00',
      String? end = '2026-10-02 19:00:00',
      String kind = '',
      String seatNo = '',
      String roomName = '',
    }) =>
        LibraryReservation(
          id: id,
          title: title,
          place: place,
          status: status,
          start: begin == null ? null : DateTime.parse(begin),
          end: end == null ? null : DateTime.parse(end),
          kind: kind,
          seatNo: seatNo,
          roomName: roomName,
        );

    test('正常（还没结束的）预约要变成待办', () {
      expect(libraryReservationWanted(r(), now: now), isTrue);
    });

    test('已取消的不建', () {
      expect(libraryReservationWanted(r(status: '已取消'), now: now), isFalse);
    });

    test('★ 已经过去的预约一条都不建（用户骂过"过期的变成逾期待办"）', () {
      final past = r(begin: '2026-09-27 15:00:00', end: '2026-09-27 19:00:00');
      expect(libraryReservationActive(past, now: now), isFalse);
      expect(libraryReservationWanted(past, now: now), isFalse);
    });

    test('★ 状态是「已使用」的也不建（哪怕时间还没到）', () {
      final used = r(status: '已使用');
      expect(libraryReservationActive(used, now: now), isFalse);
      expect(libraryReservationWanted(used, now: now), isFalse);
    });

    test('结束时间刚好等于"现在"算过期（边界）', () {
      final boundary =
          r(begin: '2026-10-01 11:00:00', end: '2026-10-01 12:00:00');
      expect(libraryReservationActive(boundary, now: now), isFalse);
    });

    test('没有 id 的不建（uid 不稳定会反复长重复待办）', () {
      expect(libraryReservationWanted(r(id: ''), now: now), isFalse);
    });

    test('缺开始或缺结束的不建（提醒说不清什么时候去）', () {
      expect(libraryReservationWanted(r(begin: null), now: now), isFalse);
      expect(libraryReservationWanted(r(end: null), now: now), isFalse);
    });
  });

  group('待办短标题：按类型取前缀 + 长度上限', () {
    LibraryReservation r({
      required String kind,
      String title = '团队讨论',
      String place = '主馆-二层-207(8人间)',
      String seatNo = '',
      String roomName = '',
    }) =>
        LibraryReservation(
          id: 'x',
          title: title,
          place: place,
          status: '已预约',
          start: DateTime.parse('2026-10-02 15:00:00'),
          end: DateTime.parse('2026-10-02 19:00:00'),
          kind: kind,
          seatNo: seatNo,
          roomName: roomName,
        );

    test('座位类：图书馆座位 · 座位号', () {
      expect(
        libraryTaskTitle(r(kind: 'seat', seatNo: 'Z2F034')),
        '图书馆座位 · Z2F034',
      );
    });

    test('座位号缺失时退回地点摘要', () {
      expect(
        libraryTaskTitle(r(kind: 'seat', place: '主馆-二层-二层北')),
        '图书馆座位 · 主馆-二层-二层北',
      );
    });

    test('研讨间：图书馆研讨间 · 房间摘要', () {
      expect(
        libraryTaskTitle(r(kind: 'room', roomName: '207(8人间)')),
        '图书馆研讨间 · 207(8人间)',
      );
    });

    test('活动类：图书馆活动 · 短标题（长标题的括号说明被去掉）', () {
      final long = r(
        kind: 'seminar',
        title: '团队讨论(班团,社团,兴趣小组,项目讨论)',
        roomName: '',
        place: '',
      );
      expect(libraryTaskTitle(long), '图书馆活动 · 团队讨论');
    });

    test('长度上限：超长也绝不越过 kLibraryTaskTitleMax', () {
      final long = r(
        kind: 'room',
        roomName: '主馆-二层-二层北阅览区A排12号研讨间(20人间)',
      );
      final title = libraryTaskTitle(long);
      expect(title.length, lessThanOrEqualTo(kLibraryTaskTitleMax));
      expect(title.endsWith('…'), isTrue);
      expect(title.startsWith('图书馆研讨间'), isTrue);
    });

    test('短标题函数：中英文括号都去掉，没有括号就原样', () {
      expect(libraryShortTitle('团队讨论(班团,社团)'), '团队讨论');
      expect(libraryShortTitle('团队讨论（班团）'), '团队讨论');
      expect(libraryShortTitle('讲座'), '讲座');
      expect(libraryShortTitle('(开头就是括号)'), '(开头就是括号)');
    });

    test('分类：有座位号就是座位；接口给研讨间/研讨间字段就是研讨间', () {
      expect(libraryReservationKind(r(kind: 'seat')), 'seat');
      expect(libraryReservationKind(r(kind: '', seatNo: 'A1')), 'seat');
      // 接口叫 seminar、但条目里是"8人间" → 按研讨间处理（真机数据就是这样）
      expect(libraryReservationKind(r(kind: 'seminar')), 'room');
      expect(libraryReservationKind(r(kind: '', roomName: '207')), 'room');
      // 没有任何房间线索的 → 活动
      expect(
        libraryReservationKind(r(kind: '', title: '讲座', place: '')), 'activity');
    });
  });

  group('设置页那一行 / 待办描述', () {
    test('列表行是"地点 + 座位号"，重复时不写两遍', () {
      const seat = LibraryReservation(
        id: '1',
        title: '主馆-二层-二层北：Z2F034',
        place: '主馆-二层-二层北',
        status: '已预约',
        start: null,
        end: null,
        kind: 'seat',
        seatNo: 'Z2F034',
      );
      expect(libraryPlaceDetail(seat), '主馆-二层-二层北 · Z2F034');

      const room = LibraryReservation(
        id: '2',
        title: '团队讨论',
        place: '主馆-二层-207',
        status: '已预约',
        start: null,
        end: null,
        kind: 'room',
        roomName: '8人间',
      );
      expect(libraryPlaceDetail(room), '主馆-二层-207 · 8人间');
    });

    test('描述里保留原来的长标题（标题放不下的都进 description）', () {
      final reservation = LibraryReservation(
        id: '3',
        title: '团队讨论(班团,社团,兴趣小组,项目讨论)',
        place: '主馆-二层-207(8人间)',
        status: '已预约',
        start: DateTime.parse('2026-10-02 15:00:00'),
        end: DateTime.parse('2026-10-02 19:00:00'),
        kind: 'room',
        roomName: '207(8人间)',
      );
      final description = libraryTaskDescription(reservation);
      expect(description.startsWith(kLibraryDescriptionPrefix), isTrue);
      expect(description, contains('团队讨论(班团,社团,兴趣小组,项目讨论)'));
      expect(description, contains('主馆-二层-207(8人间)'));
    });

    test('纯数字的状态不显示（座位接口给的是编号）', () {
      const numbered = LibraryReservation(
        id: 'x',
        title: 'a',
        place: 'b',
        status: '8',
        start: null,
        end: null,
      );
      const named = LibraryReservation(
        id: 'x',
        title: 'a',
        place: 'b',
        status: '已使用',
        start: null,
        end: null,
      );
      expect(libraryStatusLabel(numbered), '');
      expect(libraryStatusLabel(named), '已使用');
    });
  });

}
