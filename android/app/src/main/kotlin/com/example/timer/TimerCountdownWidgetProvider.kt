package com.example.timer

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.SystemClock
import android.view.View
import android.widget.RemoteViews

class TimerCountdownWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { updateWidget(context, manager, it) }
    }

    companion object {
        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, TimerCountdownWidgetProvider::class.java)
            manager.getAppWidgetIds(component).forEach { updateWidget(context, manager, it) }
        }

        private fun updateWidget(context: Context, manager: AppWidgetManager, id: Int) {
            val prefs = context.getSharedPreferences("TimerWidgetPrefs", Context.MODE_PRIVATE)
            val views = RemoteViews(context.packageName, R.layout.widget_countdown_timer)
            val title = prefs.getString("countdown_title", "").orEmpty()
            val running = prefs.getBoolean("countdown_running", false)
            val endTime = prefs.getLong("countdown_end_time", 0L)
            val savedRemaining = prefs.getInt("countdown_remaining", 0)
            val remaining = if (running && endTime > 0L) {
                ((endTime - System.currentTimeMillis()).coerceAtLeast(0L) / 1000L).toInt()
            } else savedRemaining

            views.setTextViewText(R.id.countdown_widget_title, title.ifBlank { "تایمر معکوس" })
            if (running && remaining > 0 && endTime > 0L && Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                val base = SystemClock.elapsedRealtime() + (endTime - System.currentTimeMillis()).coerceAtLeast(0L)
                views.setChronometer(R.id.countdown_widget_clock, base, "%s", true)
                views.setChronometerCountDown(R.id.countdown_widget_clock, true)
                views.setViewVisibility(R.id.countdown_widget_clock, View.VISIBLE)
                views.setViewVisibility(R.id.countdown_widget_remaining, View.GONE)
                views.setTextViewText(R.id.countdown_widget_status, "در حال شمارش")
            } else {
                views.setViewVisibility(R.id.countdown_widget_clock, View.GONE)
                views.setViewVisibility(R.id.countdown_widget_remaining, View.VISIBLE)
                views.setTextViewText(R.id.countdown_widget_status, if (remaining > 0) "متوقف" else "برای تنظیم لمس کن")
                views.setTextViewText(R.id.countdown_widget_remaining, formatTime(remaining))
            }

            val pending = PendingIntent.getActivity(
                context, 7101, Intent(context, MainActivity::class.java),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.countdown_widget_root, pending)
            manager.updateAppWidget(id, views)
        }

        private fun formatTime(seconds: Int): String {
            val safe = seconds.coerceAtLeast(0)
            val hours = safe / 3600
            val minutes = (safe % 3600) / 60
            val secs = safe % 60
            return if (hours > 0) "%02d:%02d:%02d".format(hours, minutes, secs)
            else "%02d:%02d".format(minutes, secs)
        }
    }
}
