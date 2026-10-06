import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';

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
  _secureStorageIOSOptions = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock,
    accountName: 'Celechron',
    groupId: group,
  );
}
