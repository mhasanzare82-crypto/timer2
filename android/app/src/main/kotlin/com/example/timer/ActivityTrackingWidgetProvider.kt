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

class ActivityTrackingWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { updateWidget(context, manager, it) }
    }

    companion object {
        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, ActivityTrackingWidgetProvider::class.java)
            manager.getAppWidgetIds(component).forEach { updateWidget(context, manager, it) }
        }

        private fun updateWidget(context: Context, manager: AppWidgetManager, id: Int) {
            val prefs = context.getSharedPreferences("TimerWidgetPrefs", Context.MODE_PRIVATE)
            val views = RemoteViews(context.packageName, R.layout.widget_activity_tracking)
            val title = prefs.getString("activity_title", "").orEmpty()
            val startTime = prefs.getLong("activity_start_time", 0L)
            val endTime = prefs.getLong("activity_end_time", 0L)
            val running = prefs.getBoolean("activity_running", false)
            val elapsedSeconds = prefs.getInt("activity_elapsed", 0)
            views.setTextViewText(R.id.activity_widget_title, title.ifBlank { "ثبت زمان فعالیت" })

            if (startTime > 0L && endTime > 0L) {
                val durationSeconds = ((endTime - startTime).coerceAtLeast(0L) / 1000L).toInt()
                views.setViewVisibility(R.id.activity_widget_clock, View.GONE)
                views.setTextViewText(R.id.activity_widget_status, "مدت ثبت‌شده: ${formatDuration(durationSeconds)}")
            } else if (running && startTime > 0L) {
                val elapsed = elapsedSeconds.coerceAtLeast(0).toLong() * 1000L +
                    (System.currentTimeMillis() - startTime).coerceAtLeast(0L)
                val base = SystemClock.elapsedRealtime() - elapsed
                views.setChronometer(R.id.activity_widget_clock, base, "%s", true)
                views.setViewVisibility(R.id.activity_widget_clock, View.VISIBLE)
                views.setTextViewText(R.id.activity_widget_status, "در حال ثبت زمان")
            } else if (elapsedSeconds > 0) {
                views.setViewVisibility(R.id.activity_widget_clock, View.GONE)
                views.setTextViewText(R.id.activity_widget_status, "مکث شده: ${formatDuration(elapsedSeconds)}")
            } else {
                views.setViewVisibility(R.id.activity_widget_clock, View.GONE)
                views.setTextViewText(R.id.activity_widget_status, "برای شروع ثبت زمان لمس کن")
            }

            val pending = PendingIntent.getActivity(
                context, 7102, Intent(context, MainActivity::class.java),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.activity_widget_root, pending)
            manager.updateAppWidget(id, views)
        }

        private fun formatDuration(seconds: Int): String {
            val hours = seconds / 3600
            val minutes = (seconds % 3600) / 60
            val remainingSeconds = seconds % 60
            return if (hours > 0) "%02d:%02d:%02d".format(hours, minutes, remainingSeconds)
            else "%02d:%02d".format(minutes, remainingSeconds)
        }
    }
}
