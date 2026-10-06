import 'package:celechron/database/database_helper.dart';
import 'package:celechron/mod/database_mod.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

/// Keep device-specific AlarmKit choices out of the shared task/Hive schema.
class IosTaskReminderPreferences {
  static bool get isIOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static String _key(String uid) => 'iosTaskReminderMode:$uid';

  static int modeFor(String uid, {String? fromUid}) {
    if (!Get.isRegistered<DatabaseHelper>(tag: 'db')) return 0;
    final db = Get.find<DatabaseHelper>(tag: 'db');
    final value = db.optionsBox.get(_key(uid)) ??
        (fromUid == null ? null : db.optionsBox.get(_key(fromUid)));
    return value == 0 || value == 1 ? value as int : db.getReminderMode();
  }

  static Future<void> inherit(String uid, String? fromUid) async {
    if (fromUid == null) return;
    final box = Get.find<DatabaseHelper>(tag: 'db').optionsBox;
    if (box.containsKey(_key(uid))) return;
    final source = box.get(_key(fromUid));
    if (source == 0 || source == 1) await box.put(_key(uid), source);
  }

  static Future<void> save(String uid, int mode) async {
    if (mode != 0 && mode != 1) throw ArgumentError.value(mode, 'mode');
    await Get.find<DatabaseHelper>(tag: 'db').optionsBox.put(_key(uid), mode);
  }
}
