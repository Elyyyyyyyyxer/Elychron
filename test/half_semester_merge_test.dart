import 'package:celechron/model/course.dart';
import 'package:celechron/model/session.dart';
import 'package:flutter_test/flutter_test.dart';

/// 半学期（秋/冬）归属与**合并**的回归测试。
///
/// 背景（2026-09-17 用户反馈）：「最近老是有人反馈秋冬半学期课程冲突，
/// 但我去问的时候他们又说好了」。真机诊断日志给出了机制：
///
///   * 教务行的 «xxq»（学期类型）读不出来时，App 只能**按本次查询的季节猜**
///     （«1|秋» → 上半、「1|冬» → 下半，见 «Session.fromZdbk»）；
///   * 两次查询都会返回同一门课，于是 «Course.completeSession» 里那个
///     «currentSession.firstHalf || session.firstHalf» 把"猜出来的秋"
///     和"猜出来的冬"合成了**两半都上** → 用户看到秋冬的课混在一起、还报冲突；
///   * 下次刷新 xxq 又能读了 → 自己就好了，所以"问的时候已经正常"。
///
/// 修法：给 Session 记一个**不落库**的 «halfGuessed»，合并时让"确定的"说了算。
void main() {
  Session session({
    required String name,
    bool first = false,
    bool second = false,
    bool guessed = false,
    int day = 3,
    List<int>? time,
    String location = '东1A-101',
  }) {
    final s = Session.empty()
      ..id = 'sem$name'
      ..name = name
      ..teacher = '老师'
      ..location = location
      ..dayOfWeek = day
      ..oddWeek = true
      ..evenWeek = true
      ..time = time ?? <int>[6, 7, 8]
      ..firstHalf = first
      ..secondHalf = second
      ..halfGuessed = guessed;
    return s;
  }

  group('Session.fromZdbk：行内 xxq 读得出来就用它，读不出来才猜', () {
    Map<String, dynamic> row(Object? xxq) => <String, dynamic>{
          'kcb': '高等数学<br>教学班<br>张三<br>东1A-101zwf',
          'xqj': 3,
          'djj': 6,
          'skcd': 3,
          'sfqd': '1',
          'dsz': 'all',
          'xxq': xxq,
        };

    test('xxq=秋冬 → 两半都上，且**不是**猜的', () {
      final s = Session.fromZdbk(row('秋冬'), requestedSeason: '1|秋');
      expect(s.firstHalf, isTrue);
      expect(s.secondHalf, isTrue);
      expect(s.halfGuessed, isFalse);
    });

    test('xxq=冬 → 只算下半学期，且不是猜的', () {
      final s = Session.fromZdbk(row('冬'), requestedSeason: '1|秋');
      expect(s.firstHalf, isFalse);
      expect(s.secondHalf, isTrue);
      expect(s.halfGuessed, isFalse, reason: '行内说了"冬"，就不该被查询季节带偏');
    });

    test('xxq 缺失 → 按查询季节猜，并打上"猜的"标记', () {
      final autumn = Session.fromZdbk(row(null), requestedSeason: '1|秋');
      expect(autumn.firstHalf, isTrue);
      expect(autumn.secondHalf, isFalse);
      expect(autumn.halfGuessed, isTrue);

      final winter = Session.fromZdbk(row(''), requestedSeason: '1|冬');
      expect(winter.firstHalf, isFalse);
      expect(winter.secondHalf, isTrue);
      expect(winter.halfGuessed, isTrue);
    });
  });

  group('Course.completeSession：半学期合并（这次修的就是它）', () {
    test('确定的 + 猜的 → 以确定的为准（**不再变成两半都上**）', () {
      final known = session(name: '线性代数', first: true, guessed: false);
      final course = Course.fromUgrsSessionWithoutID(known);

      final guessed = session(name: '线性代数', second: true, guessed: true);
      expect(course.completeSession(guessed), isFalse, reason: '同一天同一节同一地点，应当合并');

      // 修复前：true || false = true，secondHalf 也变成 true → 秋冬都显示（用户看到的冲突）
      expect(known.firstHalf, isTrue);
      expect(known.secondHalf, isFalse);
    });

    test('猜的 + 确定的 → 被确定的纠正过来', () {
      final guessed = session(name: '线性代数', first: true, guessed: true);
      final course = Course.fromUgrsSessionWithoutID(guessed);

      final known = session(name: '线性代数', second: true, guessed: false);
      course.completeSession(known);

      expect(guessed.firstHalf, isFalse);
      expect(guessed.secondHalf, isTrue);
      expect(guessed.halfGuessed, isFalse);
    });

    test('两边都确定 → 保持原来的"或"（长学期课拆成秋+冬两条是正常的）', () {
      final a = session(name: '大学物理', first: true, guessed: false);
      final course = Course.fromUgrsSessionWithoutID(a);
      course.completeSession(session(name: '大学物理', second: true, guessed: false));

      expect(a.firstHalf, isTrue);
      expect(a.secondHalf, isTrue);
    });

    test('两边都是猜的 → 退回"或"（宁可多显示，也别把课弄丢）', () {
      final a = session(name: '体育', first: true, guessed: true);
      final course = Course.fromUgrsSessionWithoutID(a);
      course.completeSession(session(name: '体育', second: true, guessed: true));

      expect(a.firstHalf, isTrue);
      expect(a.secondHalf, isTrue);
    });

    test('不同节次/地点不会误合并', () {
      final a = session(name: '英语', first: true);
      final course = Course.fromUgrsSessionWithoutID(a);
      final other = session(name: '英语', second: true, guessed: true, time: [10, 11]);

      expect(course.completeSession(other), isTrue, reason: '不同节次应当作为新的一条加进去');
      expect(a.firstHalf, isTrue);
      expect(a.secondHalf, isFalse);
      expect(other.secondHalf, isTrue);
    });
  });
}
