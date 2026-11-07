import 'package:flutter/services.dart';

class HomeWidgetService {
  HomeWidgetService._();

  static const MethodChannel _channel =
      MethodChannel('com.example.timer/home_widgets');

  static Future<void> updateCountdown({
    required String title,
    required bool running,
    required int remainingSeconds,
    int? endTimeMilliseconds,
  }) async {
    try {
      await _channel.invokeMethod<void>('updateCountdownWidget', {
        'title': title,
        'running': running,
        'remainingSeconds': remainingSeconds,
        'endTime': endTimeMilliseconds,
      });
    } on PlatformException {
      // Widgets are an Android-only enhancement; the app remains usable.
    } on MissingPluginException {
      // The native widget bridge is unavailable on non-Android platforms.
    }
  }

  static Future<void> updateActivity({
    required String title,
    int? startTimeMilliseconds,
  }) async {
    try {
      await _channel.invokeMethod<void>('updateActivityWidget', {
        'title': title,
        'startTime': startTimeMilliseconds,
      });
    } on PlatformException {
      // Do not interrupt time tracking if widget refresh fails.
    } on MissingPluginException {
      // The native widget bridge is unavailable on non-Android platforms.
    }
  }
}
