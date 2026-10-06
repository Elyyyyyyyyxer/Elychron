import 'package:celechron/database/database_helper.dart';
import 'package:celechron/utils/utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'dart:io';

// Model the plugin's unscoped query: group=null can see/delete all accessible groups.
class _Storage extends FlutterSecureStorage {
  final source = <String, String>{'username': 'synthetic-user'};
  final target = <String, String>{};
  bool rejectWrite = false;
  int writes = 0;

  @override
  Future<Map<String, String>> readAll(
          {IOSOptions? iOptions,
          AndroidOptions? aOptions,
          LinuxOptions? lOptions,
          WebOptions? webOptions,
          MacOsOptions? mOptions,
          WindowsOptions? wOptions}) async =>
      {...source, ...target};

  @override
  Future<String?> read(
          {required String key,
          IOSOptions? iOptions,
          AndroidOptions? aOptions,
          LinuxOptions? lOptions,
          WebOptions? webOptions,
          MacOsOptions? mOptions,
          WindowsOptions? wOptions}) async =>
      target[key];

  @override
  Future<void> write(
      {required String key,
      required String? value,
      IOSOptions? iOptions,
      AndroidOptions? aOptions,
      LinuxOptions? lOptions,
      WebOptions? webOptions,
      MacOsOptions? mOptions,
      WindowsOptions? wOptions}) async {
    writes++;
    if (rejectWrite) throw PlatformException(code: 'synthetic-write-failure');
    target[key] = value!;
  }

  @override
  Future<void> delete(
      {required String key,
      IOSOptions? iOptions,
      AndroidOptions? aOptions,
      LinuxOptions? lOptions,
      WebOptions? webOptions,
      MacOsOptions? mOptions,
      WindowsOptions? wOptions}) async {
    if (iOptions?.toMap()['groupId'] == null) source.remove(key);
    target.remove(key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('celechron/signing');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late _Storage storage;
  late DatabaseHelper db;
  late Directory directory;

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    FlutterSecureStorage.setMockInitialValues({});
    messenger.setMockMethodCallHandler(
        channel, (_) async => 'group.synthetic.ABCDEF1234');
    await initializeSecureStorageIOSOptions();
    storage = _Storage();
    directory =
        await Directory.systemTemp.createTemp('keychain-migration-test');
    Hive.init(directory.path);
    db = DatabaseHelper()
      ..secureStorage = storage
      ..optionsBox = await Hive.openBox('migration-options');
  });
  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('复制写入失败时原钥匙串凭据仍存在', () async {
    storage.rejectWrite = true;
    await db.migrateLegacySecureStorage();
    expect(storage.source['username'], 'synthetic-user');
    expect(storage.target, isEmpty);
  });

  test('目标已存在时不覆盖，重复启动不删除任何组记录', () async {
    storage.target['username'] = 'newer-synthetic-user';
    await db.migrateLegacySecureStorage();
    await db.migrateLegacySecureStorage();
    expect(storage.source['username'], 'synthetic-user');
    expect(storage.target['username'], 'newer-synthetic-user');
    expect(storage.writes, 0);
  });

  test('缺少共享组时跳过迁移，私有钥匙串记录保留', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    await initializeSecureStorageIOSOptions();
    await db.migrateLegacySecureStorage();
    expect(storage.source['username'], 'synthetic-user');
    expect(storage.target, isEmpty);
    expect(storage.writes, 0);
  });

  test('缺失目标仅复制一次，原记录和已复制记录都保留', () async {
    await db.migrateLegacySecureStorage();
    await db.migrateLegacySecureStorage();
    expect(storage.source['username'], 'synthetic-user');
    expect(storage.target['username'], 'synthetic-user');
    expect(storage.writes, 1);
  });

  test('迁移后退出登录，重启不会恢复旧凭据', () async {
    await db.migrateLegacySecureStorage();
    await storage.delete(key: 'username', iOptions: secureStorageIOSOptions);
    await db.migrateLegacySecureStorage();
    expect(storage.target['username'], isNull);
    expect(storage.source['username'], 'synthetic-user');
  });

  test('失败的复制在下一次启动仍会重试', () async {
    storage.rejectWrite = true;
    await db.migrateLegacySecureStorage();
    storage.rejectWrite = false;
    await db.migrateLegacySecureStorage();
    expect(storage.target['username'], 'synthetic-user');
    expect(storage.writes, 2);
  });
}
