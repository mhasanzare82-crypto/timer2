import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shamsi_date/shamsi_date.dart';

import '../database/app_database.dart';
import '../models/time_record.dart';
import '../utils/time_formatter.dart';
import '../services/home_widget_service.dart';
import 'countdown_timer_page.dart';
import 'record_form_page.dart';
import 'reports_page.dart';
import 'alarm_reminders_page.dart';

class _ActivityTimer {
  _ActivityTimer({required this.id, String title = ''})
      : controller = TextEditingController(text: title);

  final String id;
  final TextEditingController controller;
  DateTime? startedAt;
  DateTime? firstStartedAt;
  Duration elapsed = Duration.zero;
  bool running = false;

  Duration get currentElapsed =>
      elapsed + (running && startedAt != null
          ? DateTime.now().difference(startedAt!)
          : Duration.zero);

  Map<String, Object?> toMap() => {
        'id': id,
        'title': controller.text,
        'startedAt': startedAt?.millisecondsSinceEpoch,
        'firstStartedAt': firstStartedAt?.millisecondsSinceEpoch,
        'elapsedMs': elapsed.inMilliseconds,
        'running': running,
      };

  void dispose() => controller.dispose();
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  static const String _stateKey = 'multi_activity_timers_v1';
  final List<_ActivityTimer> _timers = [];
  DateTime _now = DateTime.now();
  Timer? _ticker;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _restoreTimers();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    for (final timer in _timers) {
      timer.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _persistTimers();
    } else if (state == AppLifecycleState.resumed) {
      setState(() => _now = DateTime.now());
    }
  }

  String _jalaliDate(DateTime date) {
    final j = Jalali.fromDateTime(date);
    return '${j.year}/${j.month.toString().padLeft(2, '0')}/${j.day.toString().padLeft(2, '0')}';
  }

  String _clock(DateTime date) =>
      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}:${date.second.toString().padLeft(2, '0')}';

  Future<void> _restoreTimers() async {
    try {
      final saved = await AppDatabase.instance.getAppState(_stateKey);
      if (saved != null) {
        final decoded = jsonDecode(saved) as List<dynamic>;
        for (final raw in decoded) {
          final map = raw as Map<String, dynamic>;
          final timer = _ActivityTimer(
            id: map['id'] as String,
            title: map['title'] as String? ?? '',
          );
          final started = map['startedAt'] as num?;
          timer.startedAt = started == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(started.toInt());
          final firstStarted = map['firstStartedAt'] as num?;
          timer.firstStartedAt = firstStarted == null
              ? timer.startedAt
              : DateTime.fromMillisecondsSinceEpoch(firstStarted.toInt());
          timer.elapsed = Duration(
            milliseconds: (map['elapsedMs'] as num?)?.toInt() ?? 0,
          );
          timer.running = map['running'] as bool? ?? false;
          _timers.add(timer);
        }
      }
    } catch (_) {
      _message('بازیابی تایمرهای ذخیره‌شده انجام نشد.');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _persistTimers() async {
    try {
      await AppDatabase.instance.saveAppState(
        _stateKey,
        jsonEncode(_timers.map((e) => e.toMap()).toList()),
      );
      final activeTimers = _timers.where((e) => e.running).toList();
      final active = activeTimers.isEmpty ? null : activeTimers.first;
      if (active != null) {
        await HomeWidgetService.updateActivity(
          title: active.controller.text.trim(),
          startTimeMilliseconds: active.startedAt?.millisecondsSinceEpoch,
        );
      } else {
        await HomeWidgetService.updateActivity(title: '', startTimeMilliseconds: null);
      }
    } catch (_) {
      _message('ذخیره وضعیت تایمرها ناموفق بود.');
    }
  }

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(value), behavior: SnackBarBehavior.floating),
    );
  }

  void _addTimer() {
    setState(() {
      _timers.add(_ActivityTimer(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
      ));
    });
    _persistTimers();
  }

  Future<void> _start(_ActivityTimer timer) async {
    if (timer.running) return;
    setState(() {
      final now = DateTime.now();
      timer.firstStartedAt ??= now;
      timer.startedAt = now;
      timer.running = true;
    });
    await _persistTimers();
  }

  Future<void> _pause(_ActivityTimer timer) async {
    if (!timer.running || timer.startedAt == null) return;
    setState(() {
      timer.elapsed += DateTime.now().difference(timer.startedAt!);
      timer.startedAt = null;
      timer.running = false;
    });
    await _persistTimers();
  }

  Future<void> _stop(_ActivityTimer timer) async {
    if (timer.running && timer.startedAt != null) {
      timer.elapsed += DateTime.now().difference(timer.startedAt!);
      timer.startedAt = null;
      timer.running = false;
    }
    if (timer.elapsed.inSeconds <= 0) {
      _message('برای ثبت فعالیت، ابتدا تایمر را اجرا کنید.');
      return;
    }

    var title = timer.controller.text.trim();
    if (title.isEmpty) {
      final controller = TextEditingController();
      final entered = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('نام فعالیت'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'اسم این فعالیت چی بود؟',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('انصراف'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
              child: const Text('ثبت'),
            ),
          ],
        ),
      );
      controller.dispose();
      if (entered == null || entered.trim().isEmpty) {
        await _persistTimers();
        return;
      }
      title = entered.trim();
      timer.controller.text = title;
    }

    final end = DateTime.now();
    final start = timer.firstStartedAt ?? end.subtract(timer.elapsed);
    final record = TimeRecord(
      title: title,
      category: 'عمومی',
      durationSeconds: timer.elapsed.inSeconds,
      createdAt: end,
      activityDate: start,
      note: 'شروع: ${_jalaliDate(start)} ${_clock(start)}\n'
          'پایان: ${_jalaliDate(end)} ${_clock(end)}',
    );

    try {
      await AppDatabase.instance.insertRecord(record);
      setState(() {
        _timers.remove(timer);
      });
      timer.dispose();
      await _persistTimers();
      _message('فعالیت «$title» ثبت شد.');
    } catch (_) {
      _message('ثبت فعالیت ناموفق بود.');
      await _persistTimers();
    }
  }

  Future<void> _openTimer() async {
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => const CountdownTimerPage()));
  }

  Future<void> _openReminders() async {
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => const AlarmRemindersPage()));
  }

  Future<void> _openReports() async {
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => const ReportsPage()));
  }

  Widget _timerCard(_ActivityTimer timer, ThemeData theme) {
    final elapsed = timer.currentElapsed.inSeconds;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            TextField(
              controller: timer.controller,
              onChanged: (_) => _persistTimers(),
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'نام فعالیت',
                hintText: 'نام فعالیت را وارد کنید (اختیاری تا زمان توقف)',
                prefixIcon: Icon(Icons.edit_note),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    TimeFormatter.clock(elapsed),
                    textDirection: TextDirection.ltr,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontFeatures: const [],
                    ),
                  ),
                ),
                Text(
                  timer.running ? 'در حال اجرا' : (timer.startedAt != null || timer.elapsed > Duration.zero ? 'مکث' : 'آماده'),
                  style: TextStyle(
                    color: timer.running ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.tonalIcon(
                  onPressed: timer.running ? null : () => _start(timer),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('شروع'),
                ),
                OutlinedButton.icon(
                  onPressed: timer.running ? () => _pause(timer) : null,
                  icon: const Icon(Icons.pause),
                  label: const Text('مکث'),
                ),
                FilledButton.icon(
                  onPressed: timer.startedAt != null || timer.elapsed > Duration.zero
                      ? () => _stop(timer)
                      : null,
                  icon: const Icon(Icons.stop),
                  label: const Text('توقف و ثبت'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('ثبت زمان'),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: _openReminders,
            icon: const Icon(Icons.notifications_active_outlined),
            tooltip: 'آلارم و یادآور',
          ),
          IconButton(
            onPressed: _openReports,
            icon: const Icon(Icons.bar_chart),
            tooltip: 'گزارش‌ها',
          ),
          IconButton(
            onPressed: _openTimer,
            icon: const Icon(Icons.hourglass_bottom),
            tooltip: 'تایمر معکوس',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Column(
                    children: [
                      Text(
                        _jalaliDate(_now),
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _clock(_now),
                        textDirection: TextDirection.ltr,
                        style: theme.textTheme.displayMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: scheme.primary,
                          fontFeatures: const [],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _addTimer,
                    icon: const Icon(Icons.add),
                    label: const Text('افزودن فعالیت'),
                  ),
                ),
                const SizedBox(height: 14),
                if (_timers.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'برای شروع، دکمه «افزودن فعالیت» را بزنید.',
                      textAlign: TextAlign.center,
                    ),
                  )
                else
                  ..._timers.map((timer) => _timerCard(timer, theme)),
              ],
            ),
    );
  }
}
