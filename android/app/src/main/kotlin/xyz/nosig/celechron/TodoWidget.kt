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
import androidx.glance.LocalSize
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.defaultWeight
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.action.clickable
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

private const val TODO_WIDGET_PREFS = "todo_widget"
private const val TODO_WIDGET_SNAPSHOT = "snapshot"

private data class TodoWidgetTask(
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
    val maxRows = when {
        LocalSize.current.height >= 260.dp -> 5
        LocalSize.current.height >= 220.dp -> 4
        LocalSize.current.height >= 180.dp -> 3
        else -> 2
    }
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
            snapshot.tasks.take(maxRows).forEach { task ->
                TodoTaskRow(task, openList)
            }
        }
    }
}

@Composable
private fun TodoTaskRow(task: TodoWidgetTask, openList: androidx.glance.action.Action) {
    Row(
        modifier = GlanceModifier
            .fillMaxWidth()
            .padding(vertical = 4.dp)
            .clickable(openList),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = if (task.overdue) "!" else "•",
            style = TextStyle(
                color = if (task.overdue) {
                    GlanceTheme.colors.error
                } else {
                    GlanceTheme.colors.primary
                },
                fontSize = 15.sp,
                fontWeight = FontWeight.Bold,
            ),
        )
        Spacer(GlanceModifier.width(7.dp))
        Column(modifier = GlanceModifier.defaultWeight()) {
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

private fun readTodoWidgetSnapshot(context: Context): TodoWidgetSnapshot {
    val raw = context.getSharedPreferences(TODO_WIDGET_PREFS, Context.MODE_PRIVATE)
        .getString(TODO_WIDGET_SNAPSHOT, null)
        ?: return TodoWidgetSnapshot()
    return try {
        val root = Json.parseToJsonElement(raw).jsonObject
        val tasks = root["tasks"]?.jsonArray?.mapNotNull { element ->
            val item = element.jsonObject
            val title = item["title"]?.jsonPrimitive?.contentOrNull ?: return@mapNotNull null
            TodoWidgetTask(
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
