import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shamsi_date/shamsi_date.dart';

import '../database/app_database.dart';
import '../models/time_record.dart';
import '../utils/time_formatter.dart';
import '../utils/jalali_date_picker.dart';
import '../services/home_widget_service.dart';
import 'countdown_timer_page.dart';
import 'record_form_page.dart';
import 'reports_page.dart';
import 'alarm_reminders_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  static const String _homeStateKey = 'home_activity_state';

  List<TimeRecord> _records = [];

  int _totalSeconds = 0;

  bool _loading = true;
  bool _saving = false;
  bool _stateLoaded = false;

  DateTime? _startTime;
  DateTime? _endTime;
  DateTime? _resumeTime;
  int _pausedSeconds = 0;

  int get _elapsedSeconds => _pausedSeconds +
      (_resumeTime == null ? 0 : _currentTime.difference(_resumeTime!).inSeconds.clamp(0, 1 << 30).toInt());

  bool get _isTracking => _startTime != null && _endTime == null;
  bool get _isRunning => _isTracking && _resumeTime != null;

  DateTime _currentTime = DateTime.now();

  final TextEditingController _subjectController = TextEditingController();

  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    _initializePage();

    _clockTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        if (!mounted) return;

        setState(() {
          _currentTime = DateTime.now();
        });
      },
    );
  }

  Future<void> _initializePage() async {
    await _restoreHomeState();
    await _loadRecords();
    await _handleWidgetAction();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!mounted) return;

      setState(() {
        _currentTime = DateTime.now();
      });

      _loadRecords();
      if (_stateLoaded) _handleWidgetAction();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _persistHomeState();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _clockTimer?.cancel();
    _subjectController.dispose();

    super.dispose();
  }

  Future<void> _handleWidgetAction() async {
    final action = await HomeWidgetService.consumePendingActivityAction();
    if (!mounted || action == null) return;
    switch (action) {
      case 'com.example.timer.ACTIVITY_START':
        await _startActivity();
        break;
      case 'com.example.timer.ACTIVITY_PAUSE':
        await _pauseActivity();
        break;
      case 'com.example.timer.ACTIVITY_STOP':
        await _endActivity();
        break;
    }
  }

  Future<void> _restoreHomeState() async {
    try {
      final saved = await AppDatabase.instance.getAppState(
        _homeStateKey,
      );

      if (saved != null) {
        final data = jsonDecode(saved) as Map<String, dynamic>;

        final startMilliseconds = (data['startTime'] as num?)?.toInt();

        final endMilliseconds = (data['endTime'] as num?)?.toInt();

        _startTime = startMilliseconds == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                startMilliseconds,
              );

        _endTime = endMilliseconds == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                endMilliseconds,
              );

        _subjectController.text = data['subject'] as String? ?? '';
        _pausedSeconds = (data['pausedSeconds'] as num?)?.toInt() ?? 0;
        final resumeMilliseconds = (data['resumeTime'] as num?)?.toInt();
        _resumeTime = resumeMilliseconds == null
            ? (_startTime != null && _endTime == null ? _startTime : null)
            : DateTime.fromMillisecondsSinceEpoch(resumeMilliseconds);
      }

      _stateLoaded = true;
      await _syncActivityWidget();

      if (mounted) {
        setState(() {
          _currentTime = DateTime.now();
        });
      }
    } catch (_) {
      _stateLoaded = true;

      if (mounted) {
        _showMessage(
          'بازیابی زمان‌های ذخیره‌شده ناموفق بود.',
        );
      }
    }
  }

  Future<void> _persistHomeState() async {
    if (!_stateLoaded) return;

    final data = <String, dynamic>{
      'startTime': _startTime?.millisecondsSinceEpoch,
      'endTime': _endTime?.millisecondsSinceEpoch,
      'subject': _subjectController.text,
      'pausedSeconds': _pausedSeconds,
      'resumeTime': _resumeTime?.millisecondsSinceEpoch,
    };

    try {
      await AppDatabase.instance.saveAppState(
        _homeStateKey,
        jsonEncode(data),
      );
      await _syncActivityWidget();
    } catch (_) {
      // در صورت بروز خطا، اطلاعات فعلی صفحه تغییر نمی‌کنند.
    }
  }

  Future<void> _syncActivityWidget() {
    final now = DateTime.now();
    final active = _startTime != null && _endTime == null;
    final start = _startTime == null
        ? null
        : now.subtract(Duration(seconds: _elapsedSeconds)).millisecondsSinceEpoch;
    return HomeWidgetService.updateActivity(
      title: _subjectController.text.trim(),
      startTimeMilliseconds: start,
      endTimeMilliseconds: active && _resumeTime != null
          ? null
          : (active || _endTime != null ? now.millisecondsSinceEpoch : null),
    );
  }

  Future<void> _clearHomeState() async {
    try {
      await AppDatabase.instance.deleteAppState(
        _homeStateKey,
      );
      await HomeWidgetService.updateActivity(title: '', startTimeMilliseconds: null);
    } catch (_) {
      _showMessage(
        'پاک‌کردن اطلاعات موقت فعالیت ناموفق بود.',
      );
    }
  }

  Future<void> _loadRecords() async {
    try {
      final records = await AppDatabase.instance.getAllRecords();

      final total = await AppDatabase.instance.getTotalSeconds();

      if (!mounted) return;

      setState(() {
        _records = records;
        _totalSeconds = total;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _loading = false;
      });

      _showMessage(
        'بارگذاری سوابق فعالیت‌ها ناموفق بود.',
      );
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _formatClock(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    final second = time.second.toString().padLeft(2, '0');

    return '$hour:$minute:$second';
  }

  String _formatDate(DateTime date) {
    return '${date.year}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> _startActivity() async {
    if (_saving || _isRunning) return;
    final now = DateTime.now();
    setState(() {
      _startTime ??= now;
      _resumeTime = now;
      _endTime = null;
    });
    await _persistHomeState();
    _showMessage(_pausedSeconds > 0 ? 'ثبت زمان ادامه یافت.' : 'زمان‌سنج شروع شد: ${_formatClock(now)}');
  }

  Future<void> _pauseActivity() async {
    if (_saving || !_isRunning || _resumeTime == null) return;
    final now = DateTime.now();
    setState(() {
      _pausedSeconds += now.difference(_resumeTime!).inSeconds;
      _resumeTime = null;
    });
    await _persistHomeState();
    _showMessage('زمان‌سنج موقتاً متوقف شد.');
  }

  Future<void> _endActivity() async {
    if (_saving) return;

    if (_startTime == null) {
      _showMessage('ابتدا دکمه شروع را بزنید.');
      return;
    }

    final end = DateTime.now();

    if (end.isBefore(_startTime!)) {
      _showMessage('زمان پایان معتبر نیست.');
      return;
    }

    setState(() {
      if (_resumeTime != null) {
        _pausedSeconds += end.difference(_resumeTime!).inSeconds;
      }
      _resumeTime = null;
      _endTime = end;
    });

    await _persistHomeState();

    final seconds = _pausedSeconds > 0 ? _pausedSeconds : end.difference(_startTime!).inSeconds;

    _showMessage(
      'زمان پایان ثبت شد. مدت فعالیت: '
      '${TimeFormatter.format(seconds)}',
    );
  }

  Future<DateTime?> _chooseDateTime(
    DateTime initialDateTime,
  ) async {
    final now = DateTime.now();

    final selectedDate = await showJalaliDatePicker(
      context: context,
      initialDate: initialDateTime,
    );

    if (selectedDate == null || !mounted) {
      return null;
    }

    final selectedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        initialDateTime,
      ),
      helpText: 'انتخاب ساعت',
      cancelText: 'انصراف',
      confirmText: 'تأیید',
    );

    if (selectedTime == null || !mounted) {
      return null;
    }

    return DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      selectedTime.hour,
      selectedTime.minute,
      now.second,
    );
  }

  Future<void> _chooseManualTimes() async {
    if (_saving) return;

    final now = DateTime.now();

    final selectedStart = await _chooseDateTime(
      _startTime ?? now,
    );

    if (selectedStart == null || !mounted) return;

    final selectedEnd = await _chooseDateTime(
      _endTime ?? (selectedStart.isBefore(now) ? now : selectedStart),
    );

    if (selectedEnd == null || !mounted) return;

    if (selectedEnd.isBefore(selectedStart)) {
      _showMessage(
        'زمان پایان نمی‌تواند قبل از زمان شروع باشد.',
      );
      return;
    }

    setState(() {
      _startTime = selectedStart;
      _endTime = selectedEnd;
      _pausedSeconds = selectedEnd.difference(selectedStart).inSeconds;
      _resumeTime = null;
    });

    await _persistHomeState();

    _showMessage('زمان شروع و پایان انتخاب شدند.');
  }

  Future<void> _saveActivity() async {
    if (_saving) return;

    final title = _subjectController.text.trim();

    if (title.isEmpty) {
      _showMessage('لطفاً موضوع فعالیت را وارد کنید.');
      return;
    }

    if (_startTime == null) {
      _showMessage(
        'ابتدا زمان شروع و پایان را ثبت یا انتخاب کنید.',
      );
      return;
    }

    if (_endTime == null) {
      _showMessage('لطفاً زمان پایان را ثبت کنید.');
      return;
    }

    if (_endTime!.isBefore(_startTime!)) {
      _showMessage(
        'زمان پایان نمی‌تواند قبل از زمان شروع باشد.',
      );
      return;
    }

    final durationSeconds = _pausedSeconds > 0
        ? _pausedSeconds
        : _endTime!.difference(_startTime!).inSeconds;

    if (durationSeconds <= 0) {
      _showMessage(
        'مدت فعالیت باید بیشتر از صفر ثانیه باشد.',
      );
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      final record = TimeRecord(
        title: title,
        category: 'عمومی',
        durationSeconds: durationSeconds,
        createdAt: DateTime.now(),
        activityDate: _startTime!,
        startedAt: _startTime!,
        endedAt: _endTime!,
        note: 'شروع: ${_formatDate(_startTime!)} '
            '${_formatClock(_startTime!)}\n'
            'پایان: ${_formatDate(_endTime!)} '
            '${_formatClock(_endTime!)}',
      );

      await AppDatabase.instance.insertRecord(record);

      if (!mounted) return;

      _subjectController.clear();

      setState(() {
        _startTime = null;
        _endTime = null;
        _resumeTime = null;
        _pausedSeconds = 0;
      });

      await _clearHomeState();
      await _loadRecords();

      if (!mounted) return;

      _showMessage('فعالیت با موفقیت ثبت شد.');
    } catch (_) {
      _showMessage('ثبت فعالیت ناموفق بود.');
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _openForm([TimeRecord? record]) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => RecordFormPage(record: record),
      ),
    );

    if (result == true) {
      await _loadRecords();
    }
  }

  Future<void> _openTimer() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const CountdownTimerPage(),
      ),
    );

    await _loadRecords();
  }

  Future<void> _openReminders() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AlarmRemindersPage()),
    );
  }

  Future<void> _openReports() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const ReportsPage(),
      ),
    );

    await _loadRecords();
  }

  Future<void> _deleteRecord(TimeRecord record) async {
    if (record.id == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف فعالیت'),
        content: Text(
          'آیا فعالیت «${record.title}» حذف شود؟',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext, false);
            },
            child: const Text('انصراف'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext, true);
            },
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await AppDatabase.instance.deleteRecord(record.id!);
      await _loadRecords();

      if (mounted) {
        _showMessage('فعالیت حذف شد.');
      }
    } catch (_) {
      _showMessage('حذف فعالیت ناموفق بود.');
    }
  }

  Widget _buildTimeRow({
    required String label,
    required DateTime? time,
    required IconData icon,
  }) {
    final value = time == null
        ? 'ثبت نشده'
        : '${_formatDate(time)}  ${_formatClock(time)}';

    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 8),
        Text(label),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              color: time == null
                  ? Theme.of(context).colorScheme.onSurfaceVariant
                  : Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActivityRecord(TimeRecord record) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(
          record.title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            '${record.category}\n'
            'مدت: ${TimeFormatter.format(record.durationSeconds)}\n'
            'تاریخ: ${_formatDate(record.activityDate)}',
          ),
        ),
        isThreeLine: true,
        onTap: () => _openForm(record),
        trailing: IconButton(
          onPressed: () => _deleteRecord(record),
          icon: const Icon(Icons.delete_outline),
          tooltip: 'حذف فعالیت',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

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
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : RefreshIndicator(
              onRefresh: _loadRecords,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      vertical: 28,
                      horizontal: 16,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: colorScheme.outlineVariant,
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          _formatClock(_currentTime),
                          textDirection: TextDirection.ltr,
                          style: theme.textTheme.displayMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.primary,
                            fontFeatures: const [],
                          ),
                        ),
                        const SizedBox(height: 8),
                        const SizedBox(height: 10),
                        Text(
                          'مدت فعالیت: ${TimeFormatter.format(_elapsedSeconds)}',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _formatDate(_currentTime),
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'ساعت دیجیتال',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(child: SizedBox(height: 52, child: ElevatedButton.icon(
                        onPressed: _saving || _isRunning ? null : _startActivity,
                        icon: const Icon(Icons.play_arrow),
                        label: Text(_pausedSeconds > 0 && !_isRunning ? 'ادامه' : 'شروع'),
                      ))),
                      const SizedBox(width: 8),
                      Expanded(child: SizedBox(height: 52, child: OutlinedButton.icon(
                        onPressed: _saving || !_isRunning ? null : _pauseActivity,
                        icon: const Icon(Icons.pause),
                        label: const Text('مکث'),
                      ))),
                      const SizedBox(width: 8),
                      Expanded(child: SizedBox(height: 52, child: ElevatedButton.icon(
                        onPressed: _saving || !_isTracking ? null : _endActivity,
                        icon: const Icon(Icons.stop),
                        label: const Text('پایان'),
                      ))),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: colorScheme.outlineVariant,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        _buildTimeRow(
                          label: 'زمان شروع:',
                          time: _startTime,
                          icon: Icons.play_circle_outline,
                        ),
                        const SizedBox(height: 12),
                        _buildTimeRow(
                          label: 'زمان پایان:',
                          time: _endTime,
                          icon: Icons.stop_circle_outlined,
                        ),
                        if (_startTime != null && _endTime != null) ...[
                          const Divider(height: 24),
                          Row(
                            children: [
                              const Icon(Icons.timer_outlined),
                              const SizedBox(width: 8),
                              const Text('مدت فعالیت:'),
                              const Spacer(),
                              Text(
                                TimeFormatter.format(
                                  _endTime!.difference(_startTime!).inSeconds,
                                ),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _saving ? null : _chooseManualTimes,
                      icon: const Icon(Icons.edit_calendar),
                      label: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'انتخاب دستی زمان شروع و پایان',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'موضوع فعالیت',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _subjectController,
                    textInputAction: TextInputAction.done,
                    onChanged: (_) {
                      _persistHomeState();
                    },
                    decoration: const InputDecoration(
                      hintText: 'موضوع فعالیت را وارد کنید',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.edit_note),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _saving ? null : _saveActivity,
                      icon: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.save_outlined),
                      label: Text(
                        _saving ? 'در حال ثبت...' : 'ثبت فعالیت',
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('مجموع تمام فعالیت‌ها'),
                          const SizedBox(height: 8),
                          Text(
                            TimeFormatter.format(_totalSeconds),
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'سوابق فعالیت‌ها',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (_records.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'هنوز فعالیتی ثبت نشده است.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  else
                    ..._records.map(_buildActivityRecord),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}
