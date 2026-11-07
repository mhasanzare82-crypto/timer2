import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  static const int _countdownNotificationId = 1001;

  Future<void> initialize() async {
    if (_initialized) return;

    tz_data.initializeTimeZones();

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    const settings = InitializationSettings(
      android: androidSettings,
    );

    await _plugin.initialize(settings);

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    await android?.requestNotificationsPermission();

    _initialized = true;
  }

  Future<void> showCountdownFinished(String title) async {
    await initialize();

    const androidDetails = AndroidNotificationDetails(
      'countdown_timer_channel',
      'هشدار تایمر',
      channelDescription: 'اعلان پایان شمارش معکوس',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
    );

    await _plugin.show(
      _countdownNotificationId,
      'پایان تایمر',
      'زمان فعالیت «$title» به پایان رسید.',
      details,
    );
  }

  Future<void> scheduleCountdownFinished({
    required String title,
    required DateTime endTime,
  }) async {
    await initialize();

    if (!endTime.isAfter(DateTime.now())) {
      await showCountdownFinished(title);
      return;
    }

    const androidDetails = AndroidNotificationDetails(
      'countdown_timer_channel',
      'هشدار تایمر',
      channelDescription: 'اعلان پایان شمارش معکوس',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
    );

    await _plugin.zonedSchedule(
      _countdownNotificationId,
      'پایان تایمر',
      'زمان فعالیت «$title» به پایان رسید.',
      tz.TZDateTime.from(endTime, tz.local),
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  Future<void> cancelCountdownFinished() async {
    await initialize();
    await _plugin.cancel(_countdownNotificationId);
  }
}
