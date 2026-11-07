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
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            ACTION_START, ACTION_PAUSE, ACTION_STOP -> {
                context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                    .edit().putString(KEY_PENDING_ACTION, intent.action).apply()
                val launch = Intent(context, MainActivity::class.java).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                }
                context.startActivity(launch)
            }
            else -> super.onReceive(context, intent)
        }
    }

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { updateWidget(context, manager, it) }
    }

    companion object {
        const val ACTION_START = "com.example.timer.ACTIVITY_START"
        const val ACTION_PAUSE = "com.example.timer.ACTIVITY_PAUSE"
        const val ACTION_STOP = "com.example.timer.ACTIVITY_STOP"
        const val PREFS = "TimerWidgetPrefs"
        const val KEY_PENDING_ACTION = "pending_activity_widget_action"

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, ActivityTrackingWidgetProvider::class.java)
            manager.getAppWidgetIds(component).forEach { updateWidget(context, manager, it) }
        }

        private fun actionIntent(context: Context, action: String, requestCode: Int): PendingIntent {
            val intent = Intent(context, ActivityTrackingWidgetProvider::class.java).setAction(action)
            return PendingIntent.getBroadcast(
                context, requestCode, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        private fun updateWidget(context: Context, manager: AppWidgetManager, id: Int) {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val views = RemoteViews(context.packageName, R.layout.widget_activity_tracking)
            val title = prefs.getString("activity_title", "").orEmpty()
            val startTime = prefs.getLong("activity_start_time", 0L)
            val endTime = prefs.getLong("activity_end_time", 0L)
            views.setTextViewText(R.id.activity_widget_title, title.ifBlank { "ثبت زمان فعالیت" })

            if (startTime > 0L && endTime > 0L) {
                val durationSeconds = ((endTime - startTime).coerceAtLeast(0L) / 1000L).toInt()
                views.setViewVisibility(R.id.activity_widget_clock, View.GONE)
                views.setTextViewText(R.id.activity_widget_status, "مدت ثبت‌شده: ${formatDuration(durationSeconds)}")
            } else if (startTime > 0L) {
                val elapsed = (System.currentTimeMillis() - startTime).coerceAtLeast(0L)
                val base = SystemClock.elapsedRealtime() - elapsed
                views.setChronometer(R.id.activity_widget_clock, base, "%s", true)
                views.setViewVisibility(R.id.activity_widget_clock, View.VISIBLE)
                views.setTextViewText(R.id.activity_widget_status, "در حال ثبت زمان")
            } else {
                views.setViewVisibility(R.id.activity_widget_clock, View.GONE)
                views.setTextViewText(R.id.activity_widget_status, "برای شروع ثبت زمان")
            }

            views.setOnClickPendingIntent(R.id.activity_widget_start, actionIntent(context, ACTION_START, 7103))
            views.setOnClickPendingIntent(R.id.activity_widget_pause, actionIntent(context, ACTION_PAUSE, 7104))
            views.setOnClickPendingIntent(R.id.activity_widget_stop, actionIntent(context, ACTION_STOP, 7105))
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
