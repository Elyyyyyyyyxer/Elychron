import 'package:celechron/utils/utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('celechron/signing');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    FlutterSecureStorage.setMockInitialValues({});
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('自签后的分组用于系统钥匙串并保持服务名和解锁策略', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'getAppGroup');
      return 'group.com.example.elychron.ABCDEF1234';
    });
    await initializeSecureStorageIOSOptions();
    final options = secureStorageIOSOptions.toMap();
    expect(options['groupId'], 'group.com.example.elychron.ABCDEF1234');
    expect(options['accountName'], 'Celechron');
    expect(options['accessibility'], 'first_unlock');
  });

  test('签名没有共享组时使用应用私有钥匙串而不冒用旧组', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    await initializeSecureStorageIOSOptions();
    expect(secureStorageIOSOptions.toMap()['groupId'], isNull);
  });

  test('签名桥接异常不泄露错误或阻塞普通钥匙串登录', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'unavailable');
    });
    await initializeSecureStorageIOSOptions();
    expect(secureStorageIOSOptions.toMap()['groupId'], isNull);
  });
}
