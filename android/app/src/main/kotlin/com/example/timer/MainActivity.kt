package com.example.timer

import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.example.timer/home_widgets")
            .setMethodCallHandler { call, result ->
                val preferences = getSharedPreferences("TimerWidgetPrefs", Context.MODE_PRIVATE)
                when (call.method) {
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
                            .putInt("countdown_remaining", (values["remainingSeconds"] as? Number)?.toInt() ?: 0)
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
                            
                            .putBoolean("activity_running", values["running"] as? Boolean ?: false)
                            .putInt("activity_elapsed", (values["elapsedSeconds"] as? Number)?.toInt() ?: 0)
                            .apply()
                        ActivityTrackingWidgetProvider.updateAll(this)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
