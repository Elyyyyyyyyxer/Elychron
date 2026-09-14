package xyz.nosig.celechron

import android.content.Context
import android.content.Intent
import android.net.Uri
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
import androidx.glance.appwidget.lazy.LazyColumn
import androidx.glance.appwidget.lazy.items
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

private const val TODO_WIDGET_PREFS = "todo_widget"
private const val TODO_WIDGET_SNAPSHOT = "snapshot"
private const val TODO_WIDGET_PENDING_COMPLETIONS = "pending_completions"
private val todoTaskIdKey = ActionParameters.Key<String>("todoTaskId")
private val todoWidgetCompletionLock = Any()

private data class TodoWidgetTask(
    val id: String,
    val title: String,
    val time: String,
    val overdue: Boolean,
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
            LazyColumn(
                modifier = GlanceModifier.fillMaxWidth().defaultWeight(),
            ) {
                items(
                    items = snapshot.tasks,
                    itemId = { task -> task.id.hashCode().toLong() },
                ) { task ->
                    TodoTaskRow(task, openList)
                }
            }
        }
    }
}

@Composable
private fun TodoTaskRow(task: TodoWidgetTask, openList: Action) {
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
                text = task.time,
                maxLines = 1,
                style = TextStyle(
                    color = if (task.overdue) {
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
        val taskId = parameters[todoTaskIdKey] ?: return
        queueTodoWidgetCompletion(context, taskId)
        TodoWidget().updateAll(context)
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
        .apply()
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

private fun queueTodoWidgetCompletion(context: Context, taskId: String) {
    synchronized(todoWidgetCompletionLock) {
        val preferences = context.getSharedPreferences(TODO_WIDGET_PREFS, Context.MODE_PRIVATE)
        val pending = preferences
            .getStringSet(TODO_WIDGET_PENDING_COMPLETIONS, emptySet())
            .orEmpty()
            .toMutableSet()
        pending.add(taskId)

        val rawSnapshot = preferences.getString(TODO_WIDGET_SNAPSHOT, null)
        val updatedSnapshot = rawSnapshot?.let { removeTaskFromSnapshot(it, taskId) }
        val editor = preferences.edit()
            .putStringSet(TODO_WIDGET_PENDING_COMPLETIONS, pending)
        if (updatedSnapshot != null) {
            editor.putString(TODO_WIDGET_SNAPSHOT, updatedSnapshot)
        }
        editor.apply()
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
