import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  static const int _countdownNotificationId = 1001;\n  static const int _countdownMaxRepeats = 3;

  Future<void> initialize() async {
    if (_initialized) return;

    tz_data.initializeTimeZones();
    final timezoneName = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(timezoneName));

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

  AndroidNotificationDetails _countdownDetails(bool withSound) =>
      AndroidNotificationDetails(
        withSound ? 'countdown_timer_channel_sound' : 'countdown_timer_channel_silent',
        'هشدار تایمر',
        channelDescription: 'اعلان پایان شمارش معکوس',
        importance: Importance.max,
        priority: Priority.high,
        playSound: withSound,
        enableVibration: true,
      );

  Future<void> showCountdownFinished(
    String title, {
    bool withSound = true,
    int repeatCount = 1,
  }) async {
    await initialize();
    final count = repeatCount.clamp(1, _countdownMaxRepeats);
    await _plugin.show(
      _countdownNotificationId,
      'پایان تایمر',
      'زمان فعالیت «$title» به پایان رسید.',
      NotificationDetails(android: _countdownDetails(withSound)),
    );
    for (var i = 1; i < count; i++) {
      await _plugin.zonedSchedule(
        _countdownNotificationId + i,
        'پایان تایمر',
        'زمان فعالیت «$title» به پایان رسید.',
        tz.TZDateTime.now(tz.local).add(Duration(seconds: i * 5)),
        NotificationDetails(android: _countdownDetails(withSound)),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  Future<void> scheduleCountdownFinished({
    required String title,
    required DateTime endTime,
    int repeatCount = 1,
    bool withSound = true,
  }) async {
    await initialize();
    final count = repeatCount.clamp(1, _countdownMaxRepeats);
    if (!endTime.isAfter(DateTime.now())) {
      await showCountdownFinished(
        title,
        withSound: withSound,
        repeatCount: count,
      );
      return;
    }

    for (var i = 0; i < count; i++) {
      await _plugin.zonedSchedule(
        _countdownNotificationId + i,
        'پایان تایمر',
        'زمان فعالیت «$title» به پایان رسید.',
        tz.TZDateTime.from(endTime.add(Duration(seconds: i * 5)), tz.local),
        NotificationDetails(android: _countdownDetails(withSound)),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  Future<void> cancelCountdownFinished() async {
    await initialize();
    for (var i = 0; i < _countdownMaxRepeats; i++) {
      await _plugin.cancel(_countdownNotificationId + i);
    }
  }

  Future<void> scheduleReminder({
    required int id,
    required String title,
    required DateTime scheduledAt,
    required bool daily,
  }) async {
    await initialize();
    if (!daily && !scheduledAt.isAfter(DateTime.now())) {
      throw ArgumentError('زمان یادآور باید در آینده باشد.');
    }
    const androidDetails = AndroidNotificationDetails(
      'reminders_channel', 'یادآورها',
      channelDescription: 'اعلان یادآورهای ثبت‌شده',
      importance: Importance.max, priority: Priority.high,
      playSound: true, enableVibration: true,
    );
    const details = NotificationDetails(android: androidDetails);
    await _plugin.zonedSchedule(
      id, 'یادآوری', title,
      tz.TZDateTime.from(scheduledAt, tz.local), details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: daily ? DateTimeComponents.time : null,
    );
  }

  Future<void> cancelReminder(int id) async {
    await initialize();
    await _plugin.cancel(id);
  }
}
