import 'package:flutter/services.dart';

class HomeWidgetService {
  HomeWidgetService._();

  static const MethodChannel _channel =
      MethodChannel('com.example.timer/home_widgets');

  static Future<void> updateCountdown({
    required String title,
    required bool running,
    required int remainingSeconds,
    
  }) async {
    try {
      await _channel.invokeMethod<void>('updateCountdownWidget', {
        'title': title,
        'running': running,
        'remainingSeconds': remainingSeconds,
        
      });
    } on PlatformException {
      // Widgets are an Android-only enhancement; the app remains usable.
    } on MissingPluginException {
      // The native widget bridge is unavailable on non-Android platforms.
    }
  }

  static Future<void> updateActivity({
    required String title,
    
    
    bool running = true,
    int elapsedSeconds = 0,
  }) async {
    try {
      await _channel.invokeMethod<void>('updateActivityWidget', {
        'title': title,
        
        
        'running': running,
        'elapsedSeconds': elapsedSeconds,
      });
    } on PlatformException {
      // Do not interrupt time tracking if widget refresh fails.
    } on MissingPluginException {
      // The native widget bridge is unavailable on non-Android platforms.
    }
  }
}
