import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  static const int _countdownNotificationId = 1001;
  static const int _maxAlarmRepeats = 3;

  Future<void> initialize() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidSettings);
    await _plugin.initialize(settings);
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
    _initialized = true;
  }

  NotificationDetails get _details {
    const android = AndroidNotificationDetails(
      'countdown_timer_channel',
      'هشدار تایمر',
      channelDescription: 'اعلان پایان شمارش معکوس',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );
    return const NotificationDetails(android: android);
  }

  Future<void> showCountdownFinished(String title, {int repeatCount = 1}) async {
    await initialize();
    final count = repeatCount.clamp(1, _maxAlarmRepeats);
    for (var i = 0; i < count; i++) {
      await _plugin.show(
        _countdownNotificationId + i,
        'پایان تایمر',
        'زمان فعالیت «$title» به پایان رسید.',
        _details,
      );
    }
  }

  Future<void> scheduleCountdownFinished({
    required String title,
    required DateTime endTime,
    int repeatCount = 1,
  }) async {
    await initialize();
    if (!endTime.isAfter(DateTime.now())) {
      await showCountdownFinished(title, repeatCount: repeatCount);
      return;
    }
    final count = repeatCount.clamp(1, _maxAlarmRepeats);
    for (var i = 0; i < count; i++) {
      await _plugin.zonedSchedule(
        _countdownNotificationId + i,
        'پایان تایمر',
        'زمان فعالیت «$title» به پایان رسید.',
        tz.TZDateTime.from(endTime.add(Duration(seconds: i * 10)), tz.local),
        _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  Future<void> cancelCountdownFinished() async {
    await initialize();
    for (var i = 0; i < _maxAlarmRepeats; i++) {
      await _plugin.cancel(_countdownNotificationId + i);
    }
  }
}
