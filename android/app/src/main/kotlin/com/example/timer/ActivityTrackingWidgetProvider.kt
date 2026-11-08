package com.example.timer

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.SystemClock
import android.view.View
import android.widget.RemoteViews
import org.json.JSONArray

class ActivityTrackingWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { updateWidget(context, manager, it) }
    }

    companion object {
        private const val STATE_KEY = "multi_activity_timers_v1"

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, ActivityTrackingWidgetProvider::class.java)
            manager.getAppWidgetIds(component).forEach { updateWidget(context, manager, it) }
        }

        private fun readTimers(context: Context): JSONArray {
            val dbFile = context.getDatabasePath("time_tracker.db")
            if (!dbFile.exists()) return JSONArray()
            return try {
                android.database.sqlite.SQLiteDatabase.openDatabase(
                    dbFile.path, null,
                    android.database.sqlite.SQLiteDatabase.OPEN_READONLY
                ).use { db ->
                    db.rawQuery(
                        "SELECT stateValue FROM app_state WHERE stateKey = ?",
                        arrayOf(STATE_KEY)
                    ).use { cursor ->
                        if (cursor.moveToFirst()) JSONArray(cursor.getString(0)) else JSONArray()
                    }
                }
            } catch (_: Exception) {
                JSONArray()
            }
        }

        private fun updateWidget(context: Context, manager: AppWidgetManager, id: Int) {
            val views = RemoteViews(context.packageName, R.layout.widget_activity_tracking)
            val timers = readTimers(context)
            val active = (0 until timers.length())
                .map { timers.getJSONObject(it) }
                .filter {
                    it.optBoolean("running", false) ||
                        it.optLong("elapsedMs", 0L) > 0L ||
                        it.optLong("startedAt", 0L) > 0L
                }

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
                        if (running) (System.currentTimeMillis() -
                            timer.optLong("startedAt", 0L)).coerceAtLeast(0L) else 0L

                    row.setTextViewText(R.id.widget_timer_title, title)
                    row.setTextViewText(
                        R.id.widget_timer_state,
                        if (running) "در حال اجرا" else "متوقف"
                    )
                    if (running) {
                        row.setChronometer(
                            R.id.widget_timer_elapsed,
                            SystemClock.elapsedRealtime() - elapsed,
                            "%s",
                            true
                        )
                    } else {
                        row.setChronometer(
                            R.id.widget_timer_elapsed,
                            SystemClock.elapsedRealtime(),
                            "%s",
                            false
                        )
                        row.setTextViewText(
                            R.id.widget_timer_elapsed,
                            formatDuration((elapsed / 1000L).toInt())
                        )
                    }
                    views.addView(R.id.activity_widget_list, row)
                }
            }

            val openApp = PendingIntent.getActivity(
                context,
                7102,
                Intent(context, MainActivity::class.java),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.activity_widget_root, openApp)
            manager.updateAppWidget(id, views)
        }

        private fun formatDuration(seconds: Int): String {
            val safe = seconds.coerceAtLeast(0)
            return "%02d:%02d:%02d".format(
                safe / 3600, (safe % 3600) / 60, safe % 60
            )
        }
    }
}
