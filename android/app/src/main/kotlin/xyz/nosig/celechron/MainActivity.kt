package xyz.nosig.celechron

import android.app.NotificationManager
import android.os.Build
import android.os.PowerManager
import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import androidx.glance.appwidget.updateAll
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.io.File

class MainActivity: FlutterActivity() {
    /** 冷启动时先攒着，等 Flutter 端订阅后再推过去 */
    private var pendingShare: List<Map<String, Any?>>? = null
    private var shareEventSink: EventChannel.EventSink? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.statusBarColor = 0
        handleShareIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleShareIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "top.celechron.celechron/ecardWidget").setMethodCallHandler {
                call, result ->
            CoroutineScope(Dispatchers.Main).launch {
                ECardWidget().updateAll(this@MainActivity)
            }
        }

        // 其它应用「分享」过来的内容
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "celechron/share").setMethodCallHandler {
                call, result ->
            when (call.method) {
                "getInitialShared" -> {
                    result.success(pendingShare)
                    pendingShare = null
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "celechron/share/stream")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    shareEventSink = events
                    val pending = pendingShare
                    if (pending != null && events != null) {
                        events.success(pending)
                        pendingShare = null
                    }
                }

                override fun onCancel(arguments: Any?) {
                    shareEventSink = null
                }
            })

        // 免打扰（DND）：专注开始时切到「完全静音」，结束时还原。
        // setInterruptionFilter 需要「勿扰访问权限」；没授权时一律返回 false，
        // 由 Dart 侧提示去授权 —— 不静默失败。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "celechron/dnd")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isGranted" -> result.success(isDndAccessGranted())
                    "currentFilter" -> result.success(currentInterruptionFilter())
                    "setFilter" -> {
                        val filter = call.argument<Int>("filter") ?: -1
                        result.success(setInterruptionFilter(filter))
                    }
                    "openSettings" -> {
                        openDndSettings()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        // 设备信息：只给「复制反馈信息」用（机型 / 系统版本 / 厂商）
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "celechron/device")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "info" -> result.success(
                        mapOf(
                            "manufacturer" to Build.MANUFACTURER,
                            "model" to Build.MODEL,
                            "release" to Build.VERSION.RELEASE,
                            "sdk" to Build.VERSION.SDK_INT,
                        )
                    )
                    else -> result.notImplemented()
                }
            }

        // 闹钟模式：播放系统默认闹钟铃声（循环）
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "celechron/alarm")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        startAlarmSound()
                        result.success(null)
                    }
                    "stop" -> {
                        stopAlarmSound()
                        result.success(null)
                    }
                    // 闹钟可靠性：Android 14+ 全屏通知要单独授权，否则锁屏时不弹全屏
                    "canUseFullScreenIntent" -> result.success(canUseFullScreenIntent())
                    "openFullScreenIntentSettings" -> {
                        openFullScreenIntentSettings()
                        result.success(null)
                    }
                    "isIgnoringBatteryOptimizations" -> result.success(isIgnoringBatteryOptimizations())
                    "getAlarmChannelImportance" -> result.success(getAlarmChannelImportance())
                    "openAppNotificationSettings" -> {
                        openAppNotificationSettings()
                        result.success(null)
                    }
                    "openAlarmChannelSettings" -> {
                        openAlarmChannelSettings()
                        result.success(null)
                    }
                    "openBatterySettings" -> {
                        openBatterySettings()
                        result.success(null)
                    }
                    // 把一条待办交给**系统时钟**（优先级等同起床闹钟）。
                    // 注意：系统只提供「设置」，没有「按标签删除」的接口，
                    // 所以撤销不了 —— 界面上必须把这一点说清楚。
                    "canSetSystemAlarm" -> result.success(canSetSystemAlarm())
                    "setSystemAlarm" -> {
                        val hour = call.argument<Int>("hour") ?: -1
                        val minutes = call.argument<Int>("minutes") ?: -1
                        val label = call.argument<String>("label") ?: "Elychron"
                        result.success(setSystemAlarm(hour, minutes, label))
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private var alarmPlayer: MediaPlayer? = null

    /** 闹钟渠道当前的重要度（5=MAX 才是能横幅/全屏/响铃的级别；渠道被系统降级会变成 3） */
    private fun getAlarmChannelImportance(): Int {
        return try {
            val manager = getSystemService(NotificationManager::class.java)
            manager?.getNotificationChannel("task_reminder_alarm_v2")?.importance ?: -1
        } catch (e: Exception) {
            -1
        }
    }

    private fun openAlarmChannelSettings() {
        try {
            startActivity(
                Intent("android.settings.CHANNEL_NOTIFICATION_SETTINGS")
                    .putExtra("android.provider.extra.APP_PACKAGE", packageName)
                    .putExtra("android.provider.extra.CHANNEL_ID", "task_reminder_alarm_v2")
            )
        } catch (e: Exception) {
            openAppNotificationSettings()
        }
    }

    /** Android 14+ 需要单独授予「全屏通知」权限，否则闹钟只弹通知不弹全屏 */
    private fun canUseFullScreenIntent(): Boolean {
        return if (Build.VERSION.SDK_INT >= 34) {
            val manager = getSystemService(NotificationManager::class.java)
            manager?.canUseFullScreenIntent() ?: false
        } else {
            true
        }
    }

    private fun openFullScreenIntentSettings() {
        try {
            if (Build.VERSION.SDK_INT >= 34) {
                startActivity(
                    Intent("android.settings.MANAGE_APP_USE_FULL_SCREEN_INTENT")
                        .setData(Uri.parse("package:" + packageName))
                )
            } else {
                openAppNotificationSettings()
            }
        } catch (e: Exception) {
            openAppNotificationSettings()
        }
    }

    private fun openAppNotificationSettings() {
        try {
            startActivity(
                Intent("android.settings.APP_NOTIFICATION_SETTINGS")
                    .putExtra("android.provider.extra.APP_PACKAGE", packageName)
            )
        } catch (e: Exception) {
            android.util.Log.e("CelechronAlarm", "open settings failed", e)
        }
    }

    /** 设备上有没有能接收「设置闹钟」的应用（正常都有系统时钟） */
    private fun canSetSystemAlarm(): Boolean {
        return try {
            val intent = Intent(android.provider.AlarmClock.ACTION_SET_ALARM)
            intent.resolveActivity(packageManager) != null
        } catch (e: Exception) {
            false
        }
    }

    /**
     * 让系统时钟在指定时刻响一个闹钟。
     *
     * SKIP_UI=true 表示不打开时钟界面直接设好（需要 SET_ALARM 权限，已在 manifest 声明）。
     * 返回 false 表示这台设备不认这个请求（少数 ROM 会移掉系统时钟）。
     */
    private fun setSystemAlarm(hour: Int, minutes: Int, label: String): Boolean {
        if (hour !in 0..23 || minutes !in 0..59) return false
        return try {
            val intent = Intent(android.provider.AlarmClock.ACTION_SET_ALARM).apply {
                putExtra(android.provider.AlarmClock.EXTRA_HOUR, hour)
                putExtra(android.provider.AlarmClock.EXTRA_MINUTES, minutes)
                putExtra(android.provider.AlarmClock.EXTRA_MESSAGE, label)
                putExtra(android.provider.AlarmClock.EXTRA_SKIP_UI, true)
            }
            if (intent.resolveActivity(packageManager) == null) return false
            startActivity(intent)
            true
        } catch (e: Exception) {
            android.util.Log.e("CelechronAlarm", "setSystemAlarm failed", e)
            false
        }
    }

    /** 有没有「勿扰访问权限」（用户需要在系统设置里手动授予） */
    private fun isDndAccessGranted(): Boolean {
        return try {
            val nm = getSystemService(NotificationManager::class.java) ?: return false
            nm.isNotificationPolicyAccessGranted
        } catch (e: Exception) {
            false
        }
    }

    /** 当前免打扰档位（1=全部允许 2=仅优先 4=完全静音 5=仅闹钟） */
    private fun currentInterruptionFilter(): Int {
        return try {
            getSystemService(NotificationManager::class.java)?.currentInterruptionFilter ?: 1
        } catch (e: Exception) {
            1
        }
    }

    /** 切免打扰档位；没授权或系统拒绝时返回 false */
    private fun setInterruptionFilter(filter: Int): Boolean {
        if (filter < 0) return false
        return try {
            val nm = getSystemService(NotificationManager::class.java) ?: return false
            if (!nm.isNotificationPolicyAccessGranted) return false
            nm.setInterruptionFilter(filter)
            true
        } catch (e: Exception) {
            android.util.Log.e("CelechronDnd", "setInterruptionFilter failed", e)
            false
        }
    }

    /** 跳到系统的「勿扰权限」授权页 */
    private fun openDndSettings() {
        try {
            startActivity(
                Intent(android.provider.Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
        } catch (e: Exception) {
            android.util.Log.e("CelechronDnd", "open settings failed", e)
        }
    }

    /** 国产 ROM（华为/小米等）常把后台闹钟掐掉，电池优化白名单能显著提升可靠性 */
    private fun isIgnoringBatteryOptimizations(): Boolean {        return try {
            val manager = getSystemService(PowerManager::class.java)
            manager?.isIgnoringBatteryOptimizations(packageName) ?: false
        } catch (e: Exception) {
            false
        }
    }

    private fun openBatterySettings() {
        try {
            startActivity(Intent("android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS"))
        } catch (e: Exception) {
            try {
                startActivity(Intent("android.settings.APPLICATION_DETAILS_SETTINGS")
                    .setData(Uri.parse("package:" + packageName)))
            } catch (e2: Exception) {
                android.util.Log.e("CelechronAlarm", "open battery settings failed", e2)
            }
        }
    }

    private fun startAlarmSound() {
        if (alarmPlayer != null) return
        try {
            var uri: Uri? = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            if (uri == null) {
                uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
            }
            if (uri == null) {
                uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            }
            alarmPlayer = MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build()
                )
                setDataSource(this@MainActivity, uri)
                isLooping = true
                prepare()
                start()
            }
        } catch (e: Exception) {
            android.util.Log.e("CelechronAlarm", "start failed", e)
            alarmPlayer = null
        }
    }

    private fun stopAlarmSound() {
        try {
            alarmPlayer?.stop()
        } catch (_: Exception) {
        } finally {
            alarmPlayer?.release()
            alarmPlayer = null
        }
    }

    override fun onDestroy() {
        stopAlarmSound()
        super.onDestroy()
    }

    /** 解析 ACTION_SEND / ACTION_SEND_MULTIPLE：文本 + 图片/文件 */
    private fun handleShareIntent(intent: Intent?) {
        if (intent == null) return
        val action = intent.action ?: return
        if (action != Intent.ACTION_SEND && action != Intent.ACTION_SEND_MULTIPLE) return

        val items = mutableListOf<Map<String, Any?>>()

        val text = intent.getStringExtra(Intent.EXTRA_TEXT)
        if (!text.isNullOrBlank()) {
            items.add(mapOf("text" to text))
        }

        val uris = mutableListOf<Uri>()
        if (action == Intent.ACTION_SEND) {
            @Suppress("DEPRECATION")
            val uri = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
            if (uri != null) uris.add(uri)
        } else {
            @Suppress("DEPRECATION")
            val list = intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
            if (list != null) uris.addAll(list)
        }

        for (uri in uris) {
            val file = copyToCache(uri) ?: continue
            items.add(
                mapOf(
                    "path" to file.absolutePath,
                    "name" to file.name,
                    "mime" to (intent.type ?: ""),
                )
            )
        }

        android.util.Log.d(
            "CelechronShare",
            "action=$action text=${text?.take(20)} uris=${uris.size} items=${items.size}"
        )

        if (items.isEmpty()) return
        // 处理过就把 action 清掉，避免配置变化时重复处理
        intent.action = null

        val sink = shareEventSink
        if (sink != null) {
            sink.success(items)
        } else {
            pendingShare = items
        }
    }

    private fun copyToCache(uri: Uri): File? {
        return try {
            val dir = File(cacheDir, "shared").apply { mkdirs() }
            val name = displayName(uri) ?: "shared_${System.currentTimeMillis()}"
            val target = File(dir, name)
            contentResolver.openInputStream(uri)?.use { input ->
                target.outputStream().use { output -> input.copyTo(output) }
            }
            if (target.exists()) target else null
        } catch (e: Exception) {
            android.util.Log.e("CelechronShare", "copy failed: $uri", e)
            null
        }
    }

    private fun displayName(uri: Uri): String? {
        return try {
            contentResolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME),
                null,
                null,
                null
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (index >= 0) cursor.getString(index) else null
                } else {
                    null
                }
            }
        } catch (e: Exception) {
            uri.lastPathSegment
        }
    }
}
