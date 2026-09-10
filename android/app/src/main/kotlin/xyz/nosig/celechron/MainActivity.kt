package xyz.nosig.celechron

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
                    else -> result.notImplemented()
                }
            }
    }

    private var alarmPlayer: MediaPlayer? = null

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
