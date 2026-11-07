package com.example.timer

import android.content.Context
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        storeWidgetAction(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        storeWidgetAction(intent)
    }

    private fun storeWidgetAction(intent: Intent?) {
        val action = intent?.action ?: return
        if (action == ActivityTrackingWidgetProvider.ACTION_START ||
            action == ActivityTrackingWidgetProvider.ACTION_PAUSE ||
            action == ActivityTrackingWidgetProvider.ACTION_STOP) {
            getSharedPreferences("TimerWidgetPrefs", Context.MODE_PRIVATE)
                .edit().putString(ActivityTrackingWidgetProvider.KEY_PENDING_ACTION, action).apply()
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.example.timer/home_widgets")
            .setMethodCallHandler { call, result ->
                val preferences = getSharedPreferences("TimerWidgetPrefs", Context.MODE_PRIVATE)
                when (call.method) {
                    "consumePendingActivityAction" -> {
                        val action = preferences.getString("pending_activity_widget_action", null)
                        preferences.edit().remove("pending_activity_widget_action").apply()
                        result.success(action)
                    }
                    "updateCountdownWidget" -> {
                        val values = call.arguments as? Map<*, *>
                        if (values == null) {
                            result.error("INVALID_ARGUMENTS", "Missing countdown data", null)
                            return@setMethodCallHandler
                        }
                        preferences.edit()
                            .putString("countdown_title", values["title"] as? String ?: "")
                            .putBoolean("countdown_running", values["running"] as? Boolean ?: false)
                            .putInt("countdown_remaining", (values["remainingSeconds"] as? Number)?.toInt() ?: 0)
                            .putLong("countdown_end_time", (values["endTime"] as? Number)?.toLong() ?: 0L)
                            .apply()
                        TimerCountdownWidgetProvider.updateAll(this)
                        result.success(null)
                    }
                    "updateActivityWidget" -> {
                        val values = call.arguments as? Map<*, *>
                        if (values == null) {
                            result.error("INVALID_ARGUMENTS", "Missing activity data", null)
                            return@setMethodCallHandler
                        }
                        preferences.edit()
                            .putString("activity_title", values["title"] as? String ?: "")
                            .putLong("activity_start_time", (values["startTime"] as? Number)?.toLong() ?: 0L)
                            .putLong("activity_end_time", (values["endTime"] as? Number)?.toLong() ?: 0L)
                            .apply()
                        ActivityTrackingWidgetProvider.updateAll(this)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
