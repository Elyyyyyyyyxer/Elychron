import 'package:celechron/mod/lan_sync_client.dart';
import 'package:celechron/mod/webdav_sync_service.dart';

/// ===== 用户数据变了：通知各个同步通道 =====
///
/// 原来这件事散在 4 个文件里，每处手写一行 `LanSyncClient.instance.scheduleSync()`。
/// 加了全平台同步（WebDAV）之后，"改一次就同步一次"有两条通道，
/// 每个写库的地方都抄两行太容易漏 —— 漏了就是"明明改了却不同步"这种最难查的问题。
///
/// 所以收成一个入口。两条通道各自防抖、各自判断"配没配好 / 开没开"，
/// 这里不做任何判断，也不关心它们现在能不能用。
void notifyDataChanged() {
  try {
    LanSyncClient.instance.scheduleSync();
  } catch (_) {}
  try {
    WebDavSyncService.instance.scheduleSync();
  } catch (_) {}
}
