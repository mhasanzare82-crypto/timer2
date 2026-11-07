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
            views.setTextViewText(R.id.activity_widget_title, title.ifBlank { "ثبت زمان فعالیت" })

            if (startTime > 0L) {
                val elapsed = (System.currentTimeMillis() - startTime).coerceAtLeast(0L)
                val base = SystemClock.elapsedRealtime() - elapsed
                views.setChronometer(R.id.activity_widget_clock, base, "%s", true)
                views.setViewVisibility(R.id.activity_widget_clock, View.VISIBLE)
                views.setTextViewText(R.id.activity_widget_status, "در حال ثبت زمان")
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
    }
}
