import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../database/app_database.dart';
import '../models/time_record.dart';
import '../services/notification_service.dart';
import '../services/home_widget_service.dart';
import '../utils/time_formatter.dart';

class CountdownTimerPage extends StatefulWidget {
  const CountdownTimerPage({super.key});

  @override
  State<CountdownTimerPage> createState() => _CountdownTimerPageState();
}

class _CountdownTimerPageState extends State<CountdownTimerPage> {
  static const String _stateKey = 'countdown_timer_state';

  final _titleController = TextEditingController();
  final _hoursController = TextEditingController(text: '0');
  final _minutesController = TextEditingController(text: '25');
  final _secondsController = TextEditingController(text: '0');

  Timer? _timer;

  int _remainingSeconds = 0;
  int _initialSeconds = 0;

  DateTime? _endTime;

  bool _running = false;
  bool _finished = false;
  bool _loading = true;
  bool _completionRecorded = false;

  @override
  void initState() {
    super.initState();
    _restoreState();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _titleController.dispose();
    _hoursController.dispose();
    _minutesController.dispose();
    _secondsController.dispose();
    super.dispose();
  }

  int _readNumber(TextEditingController controller) {
    final value = int.tryParse(controller.text.trim()) ?? 0;
    return value < 0 ? 0 : value;
  }

  Future<void> _restoreState() async {
    try {
      final saved = await AppDatabase.instance.getAppState(_stateKey);

      if (saved == null) {
        if (mounted) {
          setState(() => _loading = false);
        }
        await _syncWidget();
        return;
      }

      final data = jsonDecode(saved) as Map<String, dynamic>;

      _titleController.text = data['title'] as String? ?? '';
      _hoursController.text = data['hours'] as String? ?? '0';
      _minutesController.text = data['minutes'] as String? ?? '25';
      _secondsController.text = data['seconds'] as String? ?? '0';

      _initialSeconds = (data['initialSeconds'] as num?)?.toInt() ?? 0;
      _remainingSeconds = (data['remainingSeconds'] as num?)?.toInt() ?? 0;
      _running = data['running'] as bool? ?? false;
      _finished = data['finished'] as bool? ?? false;
      _completionRecorded = data['completionRecorded'] as bool? ?? false;

      final endMilliseconds = (data['endTime'] as num?)?.toInt();

      if (_running && endMilliseconds != null) {
        _endTime = DateTime.fromMillisecondsSinceEpoch(endMilliseconds);

        _remainingSeconds =
            (_endTime!.difference(DateTime.now()).inMilliseconds / 1000).ceil();

        if (_remainingSeconds <= 0) {
          _remainingSeconds = 0;
          _running = false;
          _finished = true;
          _endTime = null;

          if (mounted) {
            setState(() {
              _loading = false;
            });
          }

          await _persistState();

          if (!_completionRecorded) {
            await _completeTimer(showNotification: false);
          }

          return;
        }

        await NotificationService.instance.scheduleCountdownFinished(
          title: _titleController.text.trim(),
          endTime: _endTime!,
        );
      } else {
        _endTime = null;
      }

      if (!mounted) return;

      setState(() {
        _loading = false;
      });

      await _syncWidget();

      if (_running) {
        _startTicker();
      }

      if (_finished && !_completionRecorded) {
        await _completeTimer(showNotification: false);
      }
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _running = false;
        _endTime = null;
      });

      _message('بازیابی وضعیت تایمر ناموفق بود.');
    }
  }

  Future<void> _persistState() async {
    final data = <String, dynamic>{
      'title': _titleController.text.trim(),
      'hours': _hoursController.text,
      'minutes': _minutesController.text,
      'seconds': _secondsController.text,
      'initialSeconds': _initialSeconds,
      'remainingSeconds': _remainingSeconds,
      'running': _running,
      'finished': _finished,
      'completionRecorded': _completionRecorded,
      'endTime': _endTime?.millisecondsSinceEpoch,
    };

    await AppDatabase.instance.saveAppState(
      _stateKey,
      jsonEncode(data),
    );
    await _syncWidget();
  }

  Future<void> _syncWidget() => HomeWidgetService.updateCountdown(
        title: _titleController.text.trim(),
        running: _running,
        remainingSeconds: _remainingSeconds,
        endTimeMilliseconds: _endTime?.millisecondsSinceEpoch,
      );

  void _startTicker() {
    _timer?.cancel();

    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _updateRemainingTime(),
    );
  }

  void _updateRemainingTime() {
    if (!mounted || !_running || _endTime == null) return;

    final remaining =
        (_endTime!.difference(DateTime.now()).inMilliseconds / 1000).ceil();

    if (remaining <= 0) {
      _finishTimer();
      return;
    }

    setState(() {
      _remainingSeconds = remaining;
    });
  }

  Future<void> _start() async {
    if (_loading || _running) return;

    final title = _titleController.text.trim();

    if (title.isEmpty) {
      _message('عنوان فعالیت را وارد کنید.');
      return;
    }

    if (_finished) {
      _message('برای شروع تایمر جدید، ابتدا بازنشانی کنید.');
      return;
    }

    if (_remainingSeconds == 0) {
      final hours = _readNumber(_hoursController);
      final minutes = _readNumber(_minutesController);
      final seconds = _readNumber(_secondsController);

      final total = hours * 3600 + minutes * 60 + seconds;

      if (total <= 0) {
        _message('مدت‌زمان باید بیشتر از صفر باشد.');
        return;
      }

      _initialSeconds = total;
      _remainingSeconds = total;
      _completionRecorded = false;
    }

    _endTime = DateTime.now().add(
      Duration(seconds: _remainingSeconds),
    );

    setState(() {
      _running = true;
      _finished = false;
    });

    try {
      await _persistState();

      await NotificationService.instance.scheduleCountdownFinished(
        title: title,
        endTime: _endTime!,
      );

      _startTicker();
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _running = false;
        _endTime = null;
      });

      await _persistState();
      _message('شروع تایمر یا زمان‌بندی اعلان ناموفق بود.');
    }
  }

  Future<void> _pause() async {
    if (!_running) return;

    _timer?.cancel();

    if (_endTime != null) {
      final remaining =
          (_endTime!.difference(DateTime.now()).inMilliseconds / 1000).ceil();

      _remainingSeconds = remaining > 0 ? remaining : 0;
    }

    if (_remainingSeconds <= 0) {
      await _finishTimer();
      return;
    }

    setState(() {
      _running = false;
      _endTime = null;
    });

    try {
      await NotificationService.instance.cancelCountdownFinished();
      await _persistState();
    } catch (_) {
      _message('ذخیرهٔ وضعیت مکث تایمر ناموفق بود.');
    }
  }

  Future<void> _reset() async {
    _timer?.cancel();

    setState(() {
      _running = false;
      _finished = false;
      _remainingSeconds = 0;
      _initialSeconds = 0;
      _endTime = null;
      _completionRecorded = false;
    });

    try {
      await NotificationService.instance.cancelCountdownFinished();
      await AppDatabase.instance.deleteAppState(_stateKey);
      await _syncWidget();
    } catch (_) {
      _message('بازنشانی کامل تایمر ناموفق بود.');
    }
  }

  Future<void> _finishTimer() async {
    if (_finished) return;

    _timer?.cancel();

    setState(() {
      _remainingSeconds = 0;
      _running = false;
      _finished = true;
      _endTime = null;
    });

    await _persistState();

    try {
      await NotificationService.instance.cancelCountdownFinished();
      await NotificationService.instance.showCountdownFinished(
        _titleController.text.trim(),
      );
    } catch (_) {
      if (mounted) {
        _message('نمایش اعلان با مشکل مواجه شد.');
      }
    }

    await _completeTimer(showNotification: false);
  }

  Future<void> _completeTimer({
    required bool showNotification,
  }) async {
    if (_completionRecorded) return;

    final title = _titleController.text.trim();

    if (title.isEmpty || _initialSeconds <= 0) return;

    final now = DateTime.now();

    try {
      await AppDatabase.instance.insertRecord(
        TimeRecord(
          title: title,
          category: 'تایمر',
          durationSeconds: _initialSeconds,
          createdAt: now,
          activityDate: now,
          note: 'ثبت خودکار پس از پایان تایمر',
        ),
      );

      _completionRecorded = true;
      await _persistState();

      if (!mounted) return;

      setState(() {});

      _message('تایمر تمام شد و فعالیت ذخیره شد.');
    } catch (_) {
      if (mounted) {
        _message('تایمر تمام شد، اما ذخیرهٔ فعالیت ناموفق بود.');
      }
    }
  }

  void _message(String text) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('تایمر معکوس'),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('تایمر معکوس'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _titleController,
            enabled: !_running && !_finished,
            onChanged: (_) => _persistState(),
            decoration: const InputDecoration(
              labelText: 'عنوان فعالیت',
              hintText: 'مثلاً مطالعه',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          const Text('مدت‌زمان تایمر'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _hoursController,
                  enabled: !_running && !_finished && _remainingSeconds == 0,
                  onChanged: (_) => _persistState(),
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'ساعت',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _minutesController,
                  enabled: !_running && !_finished && _remainingSeconds == 0,
                  onChanged: (_) => _persistState(),
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'دقیقه',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _secondsController,
                  enabled: !_running && !_finished && _remainingSeconds == 0,
                  onChanged: (_) => _persistState(),
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'ثانیه',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          Center(
            child: Text(
              TimeFormatter.clock(_remainingSeconds),
              textDirection: TextDirection.ltr,
              style: const TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _running ? null : _start,
            child: Text(
              _remainingSeconds > 0 ? 'ادامهٔ تایمر' : 'شروع تایمر',
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _running ? _pause : null,
            child: const Text('مکث'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _reset,
            child: const Text('بازنشانی'),
          ),
          if (_finished) ...[
            const SizedBox(height: 16),
            const Text(
              'زمان به پایان رسید. فعالیت در سوابق ذخیره شد.',
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}
