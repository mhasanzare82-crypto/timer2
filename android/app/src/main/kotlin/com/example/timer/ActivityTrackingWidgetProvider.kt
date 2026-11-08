package com.example.timer

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.database.sqlite.SQLiteDatabase
import android.os.SystemClock
import android.view.View
import android.widget.RemoteViews
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class ActivityTrackingWidgetProvider : AppWidgetProvider() {
    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        when (intent.action) {
            ACTION_PAUSE, ACTION_RESUME, ACTION_FINISH -> {
                handleTimerAction(context, intent)
                updateAll(context)
            }
        }
    }

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { updateWidget(context, manager, it) }
    }

    companion object {
        private const val STATE_KEY = "multi_activity_timers_v1"
        private const val ACTION_PAUSE = "com.example.timer.widget.PAUSE"
        private const val ACTION_RESUME = "com.example.timer.widget.RESUME"
        private const val ACTION_FINISH = "com.example.timer.widget.FINISH"

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, ActivityTrackingWidgetProvider::class.java)
            manager.getAppWidgetIds(component).forEach { updateWidget(context, manager, it) }
        }

        private fun readTimers(context: Context): JSONArray {
            val dbFile = context.getDatabasePath("time_tracker.db")
            if (!dbFile.exists()) return JSONArray()
            return try {
                SQLiteDatabase.openDatabase(dbFile.path, null, SQLiteDatabase.OPEN_READONLY).use { db ->
                    db.rawQuery("SELECT stateValue FROM app_state WHERE stateKey = ?", arrayOf(STATE_KEY)).use { cursor ->
                        if (cursor.moveToFirst()) JSONArray(cursor.getString(0)) else JSONArray()
                    }
                }
            } catch (_: Exception) { JSONArray() }
        }

        private fun updateWidget(context: Context, manager: AppWidgetManager, id: Int) {
            val views = RemoteViews(context.packageName, R.layout.widget_activity_tracking)
            val timers = readTimers(context)
            val active = (0 until timers.length()).map { timers.getJSONObject(it) }
                .filter { it.optBoolean("running", false) || it.optLong("elapsedMs", 0L) > 0L || it.optLong("startedAt", 0L) > 0L }
            views.removeAllViews(R.id.activity_widget_list)

            if (active.isEmpty()) {
                views.setViewVisibility(R.id.activity_widget_empty, View.VISIBLE)
                views.setTextViewText(R.id.activity_widget_empty, "تایمر فعالی وجود ندارد")
            } else {
                views.setViewVisibility(R.id.activity_widget_empty, View.GONE)
                active.take(4).forEach { timer ->
                    val row = RemoteViews(context.packageName, R.layout.widget_activity_timer_row)
                    val title = timer.optString("title").ifBlank { "فعالیت بدون نام" }
                    val running = timer.optBoolean("running", false)
                    val elapsed = timer.optLong("elapsedMs", 0L) +
                        if (running) (System.currentTimeMillis() - timer.optLong("startedAt", 0L)).coerceAtLeast(0L) else 0L
                    row.setTextViewText(R.id.widget_timer_title, title)
                    if (running) {
                        row.setChronometer(R.id.widget_timer_elapsed,
                            SystemClock.elapsedRealtime() - elapsed, "%s", true)
                    } else {
                        row.setChronometer(R.id.widget_timer_elapsed,
                            SystemClock.elapsedRealtime(), "%s", false)
                        row.setTextViewText(R.id.widget_timer_elapsed,
                            formatDuration((elapsed / 1000L).toInt()))
                    }
                    row.setTextViewText(R.id.widget_timer_state, if (running) "در حال اجرا" else "متوقف")
                    val timerId = timer.optString("id")
                    row.setOnClickPendingIntent(R.id.widget_timer_pause,
                        actionPendingIntent(context, timerId, ACTION_PAUSE, timerId.hashCode() * 3 + 1))
                    row.setOnClickPendingIntent(R.id.widget_timer_resume,
                        actionPendingIntent(context, timerId, ACTION_RESUME, timerId.hashCode() * 3 + 2))
                    row.setOnClickPendingIntent(R.id.widget_timer_finish,
                        actionPendingIntent(context, timerId, ACTION_FINISH, timerId.hashCode() * 3 + 3))
                    row.setViewVisibility(R.id.widget_timer_pause, if (running) View.VISIBLE else View.GONE)
                    row.setViewVisibility(R.id.widget_timer_resume, if (running) View.GONE else View.VISIBLE)
                    views.addView(R.id.activity_widget_list, row)
                }
            }

            val open = PendingIntent.getActivity(
                context, 7102, Intent(context, MainActivity::class.java),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.activity_widget_root, open)
            manager.updateAppWidget(id, views)
        }

        private fun actionPendingIntent(context: Context, timerId: String, action: String, requestCode: Int): PendingIntent {
            val intent = Intent(context, ActivityTrackingWidgetProvider::class.java).apply {
                this.action = action
                putExtra("timer_id", timerId)
            }
            return PendingIntent.getBroadcast(context, requestCode, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }

        private fun handleTimerAction(context: Context, intent: Intent) {
            val id = intent.getStringExtra("timer_id") ?: return
            val dbFile = context.getDatabasePath("time_tracker.db")
            if (!dbFile.exists()) return
            try {
                SQLiteDatabase.openDatabase(dbFile.path, null, SQLiteDatabase.OPEN_READWRITE).use { db ->
                    db.beginTransaction()
                    try {
                        val raw = db.rawQuery("SELECT stateValue FROM app_state WHERE stateKey = ?", arrayOf(STATE_KEY)).use { c ->
                            if (c.moveToFirst()) c.getString(0) else null
                        } ?: return
                        val timers = JSONArray(raw)
                        var target: JSONObject? = null
                        var targetIndex = -1
                        for (i in 0 until timers.length()) {
                            val item = timers.getJSONObject(i)
                            if (item.optString("id") == id) { target = item; targetIndex = i; break }
                        }
                        val timer = target ?: return
                        val now = System.currentTimeMillis()
                        when (intent.action) {
                            ACTION_PAUSE -> if (timer.optBoolean("running", false)) {
                                val started = timer.optLong("startedAt", now)
                                timer.put("elapsedMs", timer.optLong("elapsedMs", 0L) + (now - started).coerceAtLeast(0L))
                                timer.put("startedAt", JSONObject.NULL)
                                timer.put("running", false)
                            }
                            ACTION_RESUME -> if (!timer.optBoolean("running", false)) {
                                timer.put("startedAt", now)
                                timer.put("firstStartedAt", timer.optLong("firstStartedAt", now).takeIf { it > 0L } ?: now)
                                timer.put("running", true)
                            }
                            ACTION_FINISH -> {
                                val elapsed = timer.optLong("elapsedMs", 0L) +
                                    if (timer.optBoolean("running", false)) (now - timer.optLong("startedAt", now)).coerceAtLeast(0L) else 0L
                                val title = timer.optString("title").trim()
                                if (elapsed > 0L && title.isNotEmpty()) {
                                    val values = android.content.ContentValues().apply {
                                        put("title", title); put("category", "عمومی")
                                        put("durationSeconds", (elapsed / 1000L).toInt())
                                        put("createdAt", now)
                                        put("activityDate", timer.optLong("firstStartedAt", now).takeIf { it > 0L } ?: now)
                                        putNull("note")
                                    }
                                    db.insertOrThrow("time_records", null, values)
                                    timers.remove(targetIndex)
                                } else return
                            }
                        }
                        db.execSQL("UPDATE app_state SET stateValue = ? WHERE stateKey = ?", arrayOf(timers.toString(), STATE_KEY))
                        db.setTransactionSuccessful()
                    } finally { db.endTransaction() }
                }
            } catch (_: Exception) { /* Keep widget actions fail-safe; app data remains intact. */ }
        }

        private fun formatDuration(seconds: Int): String {
            val safe = seconds.coerceAtLeast(0)
            return "%02d:%02d:%02d".format(safe / 3600, (safe % 3600) / 60, safe % 60)
        }
    }
}
