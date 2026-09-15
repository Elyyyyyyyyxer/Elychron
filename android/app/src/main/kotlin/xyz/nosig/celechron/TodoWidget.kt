package xyz.nosig.celechron

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Log
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.action.Action
import androidx.glance.action.ActionParameters
import androidx.glance.action.actionParametersOf
import androidx.glance.action.clickable
import androidx.glance.appwidget.CheckBox
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.action.ActionCallback
import androidx.glance.appwidget.action.actionRunCallback
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.cornerRadius
// 注意：原来这里 import 了 androidx.glance.appwidget.lazy.LazyColumn / items，
// 现在内容改成了普通 Column（原因见 TodoWidgetContent 里的长注释），故不再需要。
import androidx.glance.appwidget.provideContent
import androidx.glance.appwidget.updateAll
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import java.util.Calendar
import java.util.Locale

private const val TODO_WIDGET_PREFS = "todo_widget"

/// 小组件自己的日志标签：`adb logcat -s ElychronWidget` 就能只看这几行。
private const val TAG = "ElychronWidget"
private const val TODO_WIDGET_SNAPSHOT = "snapshot"
private const val TODO_WIDGET_PENDING_COMPLETIONS = "pending_completions"
private val todoTaskIdKey = ActionParameters.Key<String>("todoTaskId")
private val todoWidgetCompletionLock = Any()

private data class TodoWidgetTask(
    val id: String,
    val title: String,
    /** 旧字段：Dart 侧算好的文案，仅在拿不到 kind/at 时兜底（旧快照） */
    val time: String,
    /** 旧字段：同上 */
    val overdue: Boolean,
    /** 四种语义：event / deadline / remind / memo（备忘没有时间） */
    val kind: String,
    /** 排序与显示用的时刻（活动=开始、其余=结束）；备忘为 null */
    val atMillis: Long?,
)

private data class TodoWidgetSnapshot(
    val pendingCount: Int = 0,
    val tasks: List<TodoWidgetTask> = emptyList(),
)

class TodoWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = TodoWidget()
}

class TodoWidget : GlanceAppWidget() {
    override val sizeMode: SizeMode = SizeMode.Exact

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val snapshot = readTodoWidgetSnapshot(context)
        provideContent {
            GlanceTheme {
                TodoWidgetContent(context, snapshot)
            }
        }
    }
}

@Composable
private fun TodoWidgetContent(context: Context, snapshot: TodoWidgetSnapshot) {
    val openList = actionStartActivity(todoWidgetIntent(context, create = false))
    val createTask = actionStartActivity(todoWidgetIntent(context, create = true))

    Column(
        modifier = GlanceModifier
            .fillMaxSize()
            .background(GlanceTheme.colors.background)
            .cornerRadius(16.dp)
            .padding(horizontal = 16.dp, vertical = 12.dp),
    ) {
        Row(
            modifier = GlanceModifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Image(
                provider = ImageProvider(R.drawable.todo_check_24px),
                contentDescription = "待办",
                modifier = GlanceModifier.size(22.dp).clickable(openList),
            )
            Spacer(GlanceModifier.width(7.dp))
            Text(
                text = "最近待办",
                maxLines = 1,
                style = TextStyle(
                    color = GlanceTheme.colors.onBackground,
                    fontSize = 16.sp,
                    fontWeight = FontWeight.Bold,
                ),
                modifier = GlanceModifier.clickable(openList),
            )
            Spacer(GlanceModifier.defaultWeight())
            if (snapshot.pendingCount > 0) {
                Text(
                    text = "${snapshot.pendingCount} 项",
                    maxLines = 1,
                    style = TextStyle(
                        color = GlanceTheme.colors.onSurfaceVariant,
                        fontSize = 11.sp,
                    ),
                )
                Spacer(GlanceModifier.width(10.dp))
            }
            Box(
                modifier = GlanceModifier
                    .size(32.dp)
                    .cornerRadius(16.dp)
                    .background(GlanceTheme.colors.primaryContainer)
                    .clickable(createTask),
                contentAlignment = Alignment.Center,
            ) {
                Image(
                    provider = ImageProvider(R.drawable.add_24px),
                    contentDescription = "新增待办",
                    modifier = GlanceModifier.size(20.dp),
                )
            }
        }

        Spacer(GlanceModifier.height(8.dp))
        if (snapshot.tasks.isEmpty()) {
            Column(
                modifier = GlanceModifier.fillMaxSize().clickable(createTask),
                verticalAlignment = Alignment.CenterVertically,
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text(
                    text = "暂无待办",
                    style = TextStyle(
                        color = GlanceTheme.colors.onSurfaceVariant,
                        fontSize = 14.sp,
                    ),
                )
                Spacer(GlanceModifier.height(4.dp))
                Text(
                    text = "点按 + 新增",
                    style = TextStyle(
                        color = GlanceTheme.colors.primary,
                        fontSize = 12.sp,
                    ),
                )
            }
        } else {
            // ===== 不用 LazyColumn（原版是它，这是"点了没反应"的头号嫌疑）=====
            //
            // Glance 的 LazyColumn 是**适配器型集合**：内容由 RemoteViewsService 提供，
            // 更新时还要请桌面重新拉一次数据（日志里能看到 lazyCollection=2、
            // ListAdapterCallbackTrampoline）。华为/鸿蒙这类 OEM 桌面在收到更新后
            // 经常不去重新拉，表现就是——数据全对、画面纹丝不动：
            //   实测日志：onAction queued=true ✓ → updateAll ✓ → SessionWorker SUCCESS ✓
            //              → 小组件画面完全不变 ✗
            // 而这里最多只显示 6 条，懒加载一点用都没有。
            // 换成普通 Column 后就是一份普通的 RemoteViews，update 即可直接重画。
            // 代价：失去滚动（超出高度的部分会被裁掉）—— 小组件本身可拉伸，先按可靠优先。
            Column(
                modifier = GlanceModifier.fillMaxWidth().defaultWeight(),
            ) {
                for (task in snapshot.tasks) {
                    TodoTaskRow(task, openList)
                }
            }
        }
    }
}

/**
 * 小组件**自己按当前时间**算「今天 10:00 截止 / 已逾期 / 备忘」这些文案。
 *
 * 以前这些是 Dart 侧推快照时算好的，App 不开就永远停在旧值 —— 小组件看着"像是死的"。
 * 现在 Dart 只把原始时间戳（`at`）与语义（`kind`）传下来，文案在这里现算；
 * 配合 `updatePeriodMillis` 的周期刷新，时间就会自己走。
 *
 * 口径与 Dart 侧 `TodoWidgetMessenger._timeLabel` 保持一致（改一处要改两处）：
 * 今天/明天用「今天 HH:mm」、其余用「M月d日 HH:mm」；
 * 只有截止型会「已逾期」；活动加「开始」、提醒加「提醒」、其余加「截止」。
 */
private fun todoWidgetLabel(task: TodoWidgetTask, nowMillis: Long): String {
    val atMillis = task.atMillis
    if (task.kind == "memo" || atMillis == null) return task.time

    val now = Calendar.getInstance().apply { timeInMillis = nowMillis }
    val at = Calendar.getInstance().apply { timeInMillis = atMillis }
    val tomorrow = Calendar.getInstance().apply {
        timeInMillis = nowMillis
        add(Calendar.DAY_OF_YEAR, 1)
    }

    val clock = String.format(
        Locale.US,
        "%02d:%02d",
        at.get(Calendar.HOUR_OF_DAY),
        at.get(Calendar.MINUTE),
    )
    fun isSameDay(left: Calendar, right: Calendar): Boolean =
        left.get(Calendar.YEAR) == right.get(Calendar.YEAR) &&
            left.get(Calendar.DAY_OF_YEAR) == right.get(Calendar.DAY_OF_YEAR)

    val date = when {
        isSameDay(now, at) -> "今天 $clock"
        isSameDay(tomorrow, at) -> "明天 $clock"
        else -> "${at.get(Calendar.MONTH) + 1}月${at.get(Calendar.DAY_OF_MONTH)}日 $clock"
    }

    if (todoWidgetOverdue(task, nowMillis)) return "已逾期 · $date"
    return when (task.kind) {
        "event" -> "$date 开始"
        "remind" -> "$date 提醒"
        else -> "$date 截止"
    }
}

/** 只有「截止」且时间已经过去才算逾期（与 Dart 侧同口径）。 */
private fun todoWidgetOverdue(task: TodoWidgetTask, nowMillis: Long): Boolean {
    val atMillis = task.atMillis
    return task.kind == "deadline" && atMillis != null && atMillis < nowMillis
}

@Composable
private fun TodoTaskRow(task: TodoWidgetTask, openList: Action) {
    val nowMillis = System.currentTimeMillis()
    val label = todoWidgetLabel(task, nowMillis)
    val overdue = todoWidgetOverdue(task, nowMillis)
    Row(
        modifier = GlanceModifier
            .fillMaxWidth()
            .padding(vertical = 2.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        CheckBox(
            checked = false,
            onCheckedChange = actionRunCallback<CompleteTodoAction>(
                actionParametersOf(todoTaskIdKey to task.id),
            ),
            text = "",
            modifier = GlanceModifier.size(36.dp),
        )
        Spacer(GlanceModifier.width(4.dp))
        Column(
            modifier = GlanceModifier
                .defaultWeight()
                .padding(vertical = 4.dp)
                .clickable(openList),
        ) {
            Text(
                text = task.title,
                maxLines = 1,
                style = TextStyle(
                    color = GlanceTheme.colors.onBackground,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Medium,
                ),
            )
            Text(
                text = label,
                maxLines = 1,
                style = TextStyle(
                    color = if (overdue) {
                        GlanceTheme.colors.error
                    } else {
                        GlanceTheme.colors.onSurfaceVariant
                    },
                    fontSize = 11.sp,
                ),
            )
        }
    }
}

class CompleteTodoAction : ActionCallback {
    override suspend fun onAction(
        context: Context,
        glanceId: GlanceId,
        parameters: ActionParameters,
    ) {
        // ===== 探针 =====
        //
        // 用户反馈：点小组件上的方框"没反应"（但进 App 后待办确实完成了）。
        // 光看系统日志只能确认动作被派发了（InvisibleActionTrampolineActivity 起来过），
        // 分不清是"回调没跑"还是"跑了但画面没重画"。这两行 + queueTodoWidgetCompletion
        // 里的日志，用 `adb logcat -s ElychronWidget` 就能一刀切开。
        Log.i(TAG, "onAction 收到勾选: id=$glanceId task=${parameters[todoTaskIdKey]}")
        val taskId = parameters[todoTaskIdKey]
        if (taskId == null) {
            Log.w(TAG, "onAction 参数里没有 task id，直接返回")
            return
        }
        val queued = queueTodoWidgetCompletion(context, taskId)
        Log.i(TAG, "onAction 结果: queued=$queued（false = 快照里没找到这条，或快照坏了）")
        // 用**点到的这个小组件**的 glanceId 定向重画（原来是无差别 updateAll）。
        // 定向更新更直接，也不用去遍历所有实例，某些桌面上更可靠。
        try {
            TodoWidget().update(context, glanceId)
            Log.i(TAG, "onAction 已请求定向 update($glanceId)")
        } catch (error: Exception) {
            Log.w(TAG, "定向 update 失败，退回 updateAll: ${error.message}")
            TodoWidget().updateAll(context)
        }
    }
}

private fun todoWidgetIntent(context: Context, create: Boolean): Intent =
    Intent(context, MainActivity::class.java).apply {
        action = Intent.ACTION_VIEW
        data = Uri.parse(if (create) "celechron://todo/create" else "celechron://todo")
        flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or
            Intent.FLAG_ACTIVITY_SINGLE_TOP
    }

internal fun saveTodoWidgetSnapshot(context: Context, rawSnapshot: String) {
    // Validate before replacing the last known-good snapshot.
    Json.parseToJsonElement(rawSnapshot).jsonObject
    context.getSharedPreferences(TODO_WIDGET_PREFS, Context.MODE_PRIVATE)
        .edit()
        .putString(TODO_WIDGET_SNAPSHOT, rawSnapshot)
        // 同步写：紧接着 updateAll 就要按新快照渲染，别留"写还没落"的窗口
        .commit()
    // 探针：App 每次推快照都会经过这里。用户反馈"小组件不跟着更新"时，
    // 先看这条日志有没有出现 —— 没有的话说明问题在 Dart → 原生这一跳；
    // 有的话说明快照是新的，画面没变就是启动器/重画那边的事。
    //
    // 还打 id 列表：把这里的 id 和 onAction 那三行里的 task id 对一下就知道了 ——
    // 如果**刚勾掉的那几条又出现在新快照里**，那就不是小组件的问题，
    // 而是 App 把它们重新变成了未完成（线上就抓到过这种"3→4→5→6"的回涨）。
    val snapshotJson = runCatching {
        Json.parseToJsonElement(rawSnapshot).jsonObject
    }.getOrNull()
    val ids = snapshotJson?.get("tasks")?.jsonArray
        ?.mapNotNull { it.jsonObject["id"]?.jsonPrimitive?.contentOrNull }
        .orEmpty()
    Log.i(
        TAG,
        "App 推来新快照: 条数=${ids.size}(含可见 ${snapshotJson?.get("pendingCount")?.jsonPrimitive?.intOrNull}), " +
            "字节=${rawSnapshot.length}, id=${ids.joinToString(",") { it.take(8) }}",
    )
}

internal fun pendingTodoWidgetCompletions(context: Context): List<String> =
    synchronized(todoWidgetCompletionLock) {
        context.getSharedPreferences(TODO_WIDGET_PREFS, Context.MODE_PRIVATE)
            .getStringSet(TODO_WIDGET_PENDING_COMPLETIONS, emptySet())
            .orEmpty()
            .toList()
    }

internal fun acknowledgeTodoWidgetCompletions(context: Context, ids: Set<String>) {
    if (ids.isEmpty()) return
    synchronized(todoWidgetCompletionLock) {
        val preferences = context.getSharedPreferences(TODO_WIDGET_PREFS, Context.MODE_PRIVATE)
        val remaining = preferences
            .getStringSet(TODO_WIDGET_PENDING_COMPLETIONS, emptySet())
            .orEmpty()
            .toMutableSet()
        remaining.removeAll(ids)
        preferences.edit()
            .putStringSet(TODO_WIDGET_PENDING_COMPLETIONS, remaining)
            .apply()
    }
}

private fun queueTodoWidgetCompletion(context: Context, taskId: String): Boolean {
    synchronized(todoWidgetCompletionLock) {
        val preferences = context.getSharedPreferences(TODO_WIDGET_PREFS, Context.MODE_PRIVATE)
        val pending = preferences
            .getStringSet(TODO_WIDGET_PENDING_COMPLETIONS, emptySet())
            .orEmpty()
            .toMutableSet()
        pending.add(taskId)

        val rawSnapshot = preferences.getString(TODO_WIDGET_SNAPSHOT, null)
        val updatedSnapshot = rawSnapshot?.let { removeTaskFromSnapshot(it, taskId) }
        if (updatedSnapshot == null) {
            // 快照里没有这条 id（或者快照读不出来）→ 画面上那一行**不会消失**。
            // 完成本身仍然记进了 pending，App 下次启动/回前台时照样会把它标记完成。
            Log.w(
                TAG,
                "快照里没找到 id=$taskId（快照=${if (rawSnapshot == null) "读不到" else "有"}），" +
                    "画面不会变；已记入待处理队列",
            )
        }
        val editor = preferences.edit()
            .putStringSet(TODO_WIDGET_PENDING_COMPLETIONS, pending)
        if (updatedSnapshot != null) {
            editor.putString(TODO_WIDGET_SNAPSHOT, updatedSnapshot)
        }
        // commit() 而不是 apply()：这里紧接着就要重画小组件，
        // 用同步写把"写完了但画面按旧数据渲染"的可能彻底排除掉（这点开销无所谓）。
        editor.commit()
        return updatedSnapshot != null
    }
}

private fun removeTaskFromSnapshot(rawSnapshot: String, taskId: String): String? = try {
    val root = Json.parseToJsonElement(rawSnapshot).jsonObject
    val tasks = root["tasks"]?.jsonArray ?: JsonArray(emptyList())
    val remaining = tasks.filterNot { element ->
        element.jsonObject["id"]?.jsonPrimitive?.contentOrNull == taskId
    }
    if (remaining.size == tasks.size) {
        null
    } else {
        val currentCount = root["pendingCount"]?.jsonPrimitive?.intOrNull ?: tasks.size
        JsonObject(root.toMutableMap().apply {
            put("pendingCount", JsonPrimitive((currentCount - 1).coerceAtLeast(0)))
            put("tasks", JsonArray(remaining))
        }).toString()
    }
} catch (_: Exception) {
    null
}

private fun readTodoWidgetSnapshot(context: Context): TodoWidgetSnapshot {
    val raw = context.getSharedPreferences(TODO_WIDGET_PREFS, Context.MODE_PRIVATE)
        .getString(TODO_WIDGET_SNAPSHOT, null)
        ?: return TodoWidgetSnapshot()
    return try {
        val root = Json.parseToJsonElement(raw).jsonObject
        val tasks = root["tasks"]?.jsonArray?.mapNotNull { element ->
            val item = element.jsonObject
            val id = item["id"]?.jsonPrimitive?.contentOrNull ?: return@mapNotNull null
            val title = item["title"]?.jsonPrimitive?.contentOrNull ?: return@mapNotNull null
            TodoWidgetTask(
                id = id,
                title = title,
                time = item["time"]?.jsonPrimitive?.contentOrNull.orEmpty(),
                overdue = item["overdue"]?.jsonPrimitive?.booleanOrNull ?: false,
                // 新格式才有的两个字段；旧快照没有时会退回上面那两个算好的值
                kind = item["kind"]?.jsonPrimitive?.contentOrNull.orEmpty(),
                atMillis = item["at"]?.jsonPrimitive?.longOrNull,
            )
        }.orEmpty()
        TodoWidgetSnapshot(
            pendingCount = root["pendingCount"]?.jsonPrimitive?.intOrNull ?: tasks.size,
            tasks = tasks,
        )
    } catch (_: Exception) {
        TodoWidgetSnapshot()
    }
}
