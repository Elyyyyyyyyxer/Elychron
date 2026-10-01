import 'dart:io';

import 'package:celechron/http/library_spider.dart';
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

  });
}
