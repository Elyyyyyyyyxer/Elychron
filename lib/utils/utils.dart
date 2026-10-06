import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:uuid/uuid.dart';

DateTime dateOnly(DateTime date, {int? hour, int? minute}) {
  return DateTime(date.year, date.month, date.day, hour ?? 0, minute ?? 0);
}

String durationToString(Duration duration) {
  String str = '';
  if (duration.inHours != 0) {
    str = '${duration.inHours} 小时';
  }
  if (duration.inMinutes % 60 != 0 || duration.inHours == 0) {
    if (str != '') str = '$str ';
    str = '$str${duration.inMinutes % 60} 分钟';
  }
  return str;
}

String toStringHumanReadable(DateTime dateTime) {
  String str =
      dateTime.toLocal().toIso8601String().replaceFirst(RegExp(r'T'), ' ');
  str = str.substring(0, str.length - 7);
  return str;
}

var _secureStorageIOSOptions = !kReleaseMode
    ? const IOSOptions(
        accessibility: KeychainAccessibility.first_unlock,
        accountName: 'Celechron',
        groupId: 'group.top.celechron.celechron.debug')
    : const IOSOptions(
        accessibility: KeychainAccessibility.first_unlock,
        accountName: 'Celechron',
        groupId: 'group.top.celechron.celechron');

IOSOptions get secureStorageIOSOptions => _secureStorageIOSOptions;

Future<void> initializeSecureStorageIOSOptions() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
  String? group;
  try {
    group = await const MethodChannel('celechron/signing')
        .invokeMethod<String>('getAppGroup')
        .timeout(const Duration(seconds: 2));
  } on Object {
    // Missing sharing capability must not prevent private Keychain login.
  }
  // Signing metadata alone does not grant access: some signers strip App Groups.
  if (group != null && !await _canUseSharedKeychain(group)) group = null;
  _secureStorageIOSOptions = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock,
    accountName: 'Celechron',
    groupId: group,
  );
}

Future<bool> _canUseSharedKeychain(String group) async {
  final storage = FlutterSecureStoragePlatform.instance;
  final options = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock,
    accountName: 'CelechronSigningProbe',
    groupId: group,
  ).toMap();
  final key = 'capability-${const Uuid().v4()}';
  const timeout = Duration(seconds: 2);
  try {
    await storage
        .write(key: key, value: 'available', options: options)
        .timeout(timeout);
    return await storage.read(key: key, options: options).timeout(timeout) ==
        'available';
  } on Object {
    return false;
  } finally {
    try {
      await storage.delete(key: key, options: options).timeout(timeout);
    } on Object {
      // A timed-out native write may finish later; always attempt scoped cleanup.
    }
  }
}
