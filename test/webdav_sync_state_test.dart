import 'dart:convert';

import 'package:celechron/mod/webdav_client.dart';
import 'package:celechron/mod/webdav_sync_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// 跨设备同步的**省流量决策**（W1）。
///
/// 用户要求（2026-09-21）：「有没有办法做一个数据校验？能够做到不下载全部文件
/// 但也可以确认数据是否更新，更新过的再进行同步操作，节约流量」。
///
/// 这一条测试的核心就一句话：**没变就一个字节都别传**。
void main() {
  test('两端都没变 → 什么都不传（省流量的目标状态）', () {
    expect(
      decideSyncAction(
          localRevision: 'r1', remoteRevision: 'r1', lastSyncedRevision: 'r1'),
      SyncAction.upToDate,
    );
  });

  test('只有远端变了 → 拉', () {
    expect(
      decideSyncAction(
          localRevision: 'r1', remoteRevision: 'r2', lastSyncedRevision: 'r1'),
      SyncAction.pull,
    );
  });

  test('只有本机变了 → 推', () {
    expect(
      decideSyncAction(
          localRevision: 'r2', remoteRevision: 'r1', lastSyncedRevision: 'r1'),
      SyncAction.push,
    );
  });

  test('两边都变了 → 合并（两边都不能丢）', () {
    expect(
      decideSyncAction(
          localRevision: 'r2', remoteRevision: 'r3', lastSyncedRevision: 'r1'),
      SyncAction.merge,
    );
  });

  test('远端还没有数据：本机有改动就推，没改动就闲着', () {
    expect(
      decideSyncAction(
          localRevision: 'r1', remoteRevision: null, lastSyncedRevision: null),
      SyncAction.push,
    );
    expect(
      decideSyncAction(
          localRevision: 'r1', remoteRevision: null, lastSyncedRevision: 'r1'),
      SyncAction.upToDate,
    );
  });

  test('revision 对内容敏感：内容一变就变，内容一样就一样', () {
    final a = contentRevision(utf8.encode('hello'));
    final b = contentRevision(utf8.encode('hello'));
    final c = contentRevision(utf8.encode('hellp'));
    expect(a, b);
    expect(a, isNot(c));
  });

  test('清单编解码往返（远端那个几百字节的小文件）', () {
    final manifest = RemoteManifest(
      revision: 'abc123',
      updatedAt: DateTime(2026, 9, 21, 20, 0),
      deviceId: 'dev-pc',
      bytes: 12345,
      devices: <DeviceStamp>[
        DeviceStamp(
          deviceId: 'dev-phone',
          name: '手机',
          updatedAt: DateTime(2026, 9, 21, 19, 0),
          revision: 'aaa',
        ),
      ],
    );
    final back = RemoteManifest.decode(manifest.encode());
    expect(back, isNotNull);
    expect(back!.revision, 'abc123');
    expect(back.bytes, 12345);
    expect(back.devices.single.name, '手机');
    expect(back.devices.single.revision, 'aaa');
  });

  test('清单坏了当没有（不能让一次坏数据卡死同步）', () {
    expect(RemoteManifest.decode(utf8.encode('not json')), isNull);
    expect(RemoteManifest.decode(utf8.encode('{}')), isNull);
  });

  test('WebDAV 的 207 响应能解析出来（各家 XML 前缀不一样）', () {
    const xml = '<?xml version="1.0"?>'
        '<d:multistatus xmlns:d="DAV:">'
        '<d:response><d:href>/dav/Elychron/bundle.json</d:href>'
        '<d:propstat><d:prop><d:getetag>"abc"</d:getetag>'
        '<d:getcontentlength>4096</d:getcontentlength>'
        '<d:getlastmodified>Wed, 21 Oct 2026 07:28:00 GMT</d:getlastmodified>'
        '</d:prop></d:propstat></d:response>'
        '<d:response><d:href>/dav/Elychron/</d:href>'
        '<d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype>'
        '</d:prop></d:propstat></d:response>'
        '</d:multistatus>';
    final entries =
        parseMultiStatusForTest(xml, 'https://dav.jianguoyun.com/dav/');
    expect(entries.length, 2);
    final file = entries.firstWhere((e) => !e.isDirectory);
    expect(file.path, 'Elychron/bundle.json');
    expect(file.etag, 'abc');
    expect(file.size, 4096);
    expect(file.fingerprint, 'abc');
    final dir = entries.firstWhere((e) => e.isDirectory);
    expect(dir.isDirectory, isTrue);
  });
}
