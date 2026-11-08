import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:shamsi_date/shamsi_date.dart';

import '../database/app_database.dart';
import '../models/time_record.dart';
import '../services/home_widget_service.dart';
import '../services/notification_service.dart';
import '../utils/time_formatter.dart';

class CountdownTimerPage extends StatefulWidget {
  const CountdownTimerPage({super.key});

  @override
  State<CountdownTimerPage> createState() => _CountdownTimerPageState();
}

class _CountdownTimerPageState extends State<CountdownTimerPage> {
  static const String _stateKey = 'countdown_timer_state_v2';
  final _titleController = TextEditingController();
  Timer? _ticker;

  int _hours = 0;
  int _minutes = 25;
  int _seconds = 0;
  int _initialSeconds = 0;
  int _remainingSeconds = 0;
  DateTime? _startAt;
  DateTime? _endAt;
  bool _running = false;
  bool _finished = false;
  bool _alarmEnabled = true;
  bool _loading = true;
  bool _saved = false;
  bool _prompting = false;
  int _alarmRepeat = 1;
  bool _alarmSound = true;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _titleController.dispose();
    super.dispose();
  }

  String _jalali(DateTime date) {
    final j = Jalali.fromDateTime(date);
    return '${j.year}/${j.month.toString().padLeft(2, '0')}/${j.day.toString().padLeft(2, '0')}';
  }

  String _clock(DateTime date) =>
      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}:${date.second.toString().padLeft(2, '0')}';

  Future<void> _restore() async {
    try {
      final raw = await AppDatabase.instance.getAppState(_stateKey);
      if (raw != null) {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        _titleController.text = data['title'] as String? ?? '';
        _hours = (data['hours'] as num?)?.toInt() ?? 0;
        _minutes = (data['minutes'] as num?)?.toInt() ?? 25;
        _seconds = (data['seconds'] as num?)?.toInt() ?? 0;
        _initialSeconds = (data['initial'] as num?)?.toInt() ?? 0;
        _remainingSeconds = (data['remaining'] as num?)?.toInt() ?? 0;
        _alarmEnabled = data['alarm'] as bool? ?? true;
        _alarmRepeat = (data['alarmRepeat'] as num?)?.toInt() ?? 1;
        _alarmSound = data['alarmSound'] as bool? ?? true;
        _finished = data['finished'] as bool? ?? false;
        _saved = data['saved'] as bool? ?? false;
        _completionPending = data['completionPending'] as bool? ?? false;
        final start = data['startAt'] as num?;
        final end = data['endAt'] as num?;
        if (start != null) _startAt = DateTime.fromMillisecondsSinceEpoch(start.toInt());
        if (_running = data['running'] as bool? ?? false) {
          if (end != null) {
            _endAt = DateTime.fromMillisecondsSinceEpoch(end.toInt());
            _remainingSeconds =
                (_endAt!.difference(DateTime.now()).inMilliseconds / 1000).ceil();
            if (_remainingSeconds <= 0) {
              _remainingSeconds = 0;
              _running = false;
              _finished = true;
              _completionPending = true;
              _endAt = null;
            }
          } else {
            _running = false;
          }
        }
      }
    } catch (_) {
      _showMessage('بازیابی وضعیت تایمر انجام نشد.');
    }
    if (!mounted) return;
    setState(() => _loading = false);
    if (_running) {
      _startTicker();
      if (_alarmEnabled && _endAt != null) {
        await NotificationService.instance.scheduleCountdownFinished(
          title: _titleController.text.trim(),
          endTime: _endAt!,
          repeatCount: _alarmRepeat,
          withSound: _alarmSound,
        );
      }
    }
    if (_finished && !_saved && _completionPending) await _complete();
    await _syncWidget();
  }

  Future<void> _persist() async {
    await AppDatabase.instance.saveAppState(_stateKey, jsonEncode({
      'title': _titleController.text.trim(),
      'hours': _hours,
      'minutes': _minutes,
      'seconds': _seconds,
      'initial': _initialSeconds,
      'remaining': _remainingSeconds,
      'startAt': _startAt?.millisecondsSinceEpoch,
      'endAt': _endAt?.millisecondsSinceEpoch,
      'running': _running,
      'finished': _finished,
      'alarm': _alarmEnabled,
      'alarmRepeat': _alarmRepeat,
      'alarmSound': _alarmSound,
      'saved': _saved,
      'completionPending': _completionPending,
    }));
    await _syncWidget();
  }

  Future<void> _syncWidget() => HomeWidgetService.updateCountdown(
        title: _titleController.text.trim(),
        running: _running,
        remainingSeconds: _remainingSeconds,
        endTimeMilliseconds: _endAt?.millisecondsSinceEpoch,
      );

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    if (!mounted || !_running || _endAt == null) return;
    final left = (_endAt!.difference(DateTime.now()).inMilliseconds / 1000).ceil();
    if (left <= 0) {
      _finish();
    } else {
      setState(() => _remainingSeconds = left);
    }
  }

  Future<void> _start() async {
    if (_running || _loading) return;
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      _showMessage('عنوان تایمر را وارد کنید.');
      return;
    }
    if (_finished) {
      _showMessage('برای شروع دوباره، تایمر را بازنشانی کنید.');
      return;
    }
    if (_remainingSeconds <= 0) {
      _initialSeconds = _hours * 3600 + _minutes * 60 + _seconds;
      if (_initialSeconds <= 0) {
        _showMessage('مدت‌زمان باید بیشتر از صفر باشد.');
        return;
      }
      _remainingSeconds = _initialSeconds;
      _startAt = DateTime.now();
      _saved = false;
    }
    _endAt = DateTime.now().add(Duration(seconds: _remainingSeconds));
    setState(() => _running = true);
    try {
      await _persist();
      if (_alarmEnabled) {
        await NotificationService.instance.scheduleCountdownFinished(
          title: title,
          endTime: _endAt!,
          repeatCount: _alarmRepeat,
          withSound: _alarmSound,
        );
      } else {
        await NotificationService.instance.cancelCountdownFinished();
      }
      _startTicker();
    } catch (_) {
      setState(() {
        _running = false;
        _endAt = null;
      });
      _showMessage('شروع تایمر با مشکل مواجه شد.');
    }
  }

  Future<void> _pause() async {
    if (!_running || _endAt == null) return;
    final left = (_endAt!.difference(DateTime.now()).inMilliseconds / 1000).ceil();
    if (left <= 0) {
      await _finish();
      return;
    }
    _ticker?.cancel();
    setState(() {
      _remainingSeconds = left;
      _running = false;
      _endAt = null;
    });
    await NotificationService.instance.cancelCountdownFinished();
    await _persist();
  }

  Future<void> _stop() async {
    if (!_running) return;
    final left = _endAt == null
        ? _remainingSeconds
        : (_endAt!.difference(DateTime.now()).inMilliseconds / 1000).ceil().clamp(0, _initialSeconds);
    _ticker?.cancel();
    await NotificationService.instance.cancelCountdownFinished();
    setState(() {
      _running = false;
      _finished = true;
      _remainingSeconds = left;
      _endAt = null;
      _saved = false;
      _completionPending = false;
    });
    await _persist();
    _showMessage('تایمر متوقف شد؛ برای شروع مجدد آن را بازنشانی کنید.');
  }

  Future<void> _reset() async {
    _ticker?.cancel();
    await NotificationService.instance.cancelCountdownFinished();
    setState(() {
      _running = false;
      _finished = false;
      _remainingSeconds = 0;
      _initialSeconds = 0;
      _startAt = null;
      _endAt = null;
      _saved = false;
      _completionPending = false;
    });
    await AppDatabase.instance.deleteAppState(_stateKey);
    await _syncWidget();
    _showMessage('تایمر بازنشانی شد.');
  }

  Future<void> _finish() async {
    if (_finished) return;
    _ticker?.cancel();
    setState(() {
      _running = false;
      _finished = true;
      _completionPending = true;
      _remainingSeconds = 0;
      _endAt = null;
    });
    await _persist();
    await NotificationService.instance.cancelCountdownFinished();
    if (_alarmEnabled) {
      await NotificationService.instance.showCountdownFinished(
        _titleController.text.trim(),
        withSound: _alarmSound,
        repeatCount: _alarmRepeat,
      );
    }
    await _complete();
  }

  Future<void> _complete() async {
    if (_saved || _prompting || _startAt == null || _initialSeconds <= 0 || !mounted) return;
    _prompting = true;
    final controller = TextEditingController(text: _titleController.text.trim());
    final title = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('زمان به پایان رسید'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'موضوع فعالیت',
            hintText: 'نام فعالیتی که انجام دادید',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('ثبت فعالیت'),
          ),
        ],
      ),
    );
    controller.dispose();
    _prompting = false;
    if (title == null || title.trim().isEmpty || !mounted) {
      _showMessage('برای ذخیره، نام فعالیت را وارد کنید.');
      return;
    }
    _titleController.text = title.trim();
    final end = DateTime.now();
    final start = _startAt!;
    try {
      await AppDatabase.instance.insertRecord(TimeRecord(
        title: title.trim(),
        category: 'تایمر',
        durationSeconds: _initialSeconds,
        createdAt: end,
        activityDate: start,
        note: 'شروع: ${_jalali(start)} ${_clock(start)}\n'
            'پایان: ${_jalali(end)} ${_clock(end)}',
      ));
      _saved = true;
      _completionPending = false;
      await _persist();
      if (mounted) _showMessage('فعالیت در فهرست فعالیت‌ها و گزارش‌ها ثبت شد.');
    } catch (_) {
      if (mounted) _showMessage('تایمر تمام شد، اما ذخیره فعالیت ناموفق بود.');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Widget _wheel({
    required int value,
    required int count,
    required String label,
    required ValueChanged<int> onChanged,
  }) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          SizedBox(
            height: 150,
            child: CupertinoPicker(
              scrollController: FixedExtentScrollController(initialItem: value),
              itemExtent: 42,
              magnification: 1.15,
              useMagnifier: true,
              onSelectedItemChanged: onChanged,
              children: List.generate(
                count,
                (i) => Center(
                  child: Text(i.toString().padLeft(2, '0'),
                      style: const TextStyle(fontSize: 25)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final total = _initialSeconds > 0
        ? _initialSeconds
        : (_hours * 3600 + _minutes * 60 + _seconds);
    final progress = total == 0 ? 0.0 : (1 - _remainingSeconds / total).clamp(0.0, 1.0);
    final editable = !_running && !_finished && _remainingSeconds == 0;
    return Scaffold(
      appBar: AppBar(title: const Text('تایمر معکوس')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: _titleController,
            enabled: !_running && !_finished,
            onChanged: (_) => _persist(),
            textAlign: TextAlign.center,
            decoration: const InputDecoration(
              labelText: 'عنوان تایمر',
              hintText: 'مثلاً مطالعه یا استراحت',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 18),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('هشدار پایان تایمر'),
            value: _alarmEnabled,
            onChanged: (value) async {
              setState(() => _alarmEnabled = value);
              if (!value) {
                await NotificationService.instance.cancelCountdownFinished();
              } else if (_running && _endAt != null) {
                await NotificationService.instance.scheduleCountdownFinished(
                  title: _titleController.text.trim(),
                  endTime: _endAt!,
                  repeatCount: _alarmRepeat,
                  withSound: _alarmSound,
                );
              }
              await _persist();
            },
          ),
          if (_alarmEnabled) ...[
            DropdownButtonFormField<int>(
              value: _alarmRepeat,
              decoration: const InputDecoration(
                labelText: 'تعداد دفعات هشدار',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 1, child: Text('یک بار')),
                DropdownMenuItem(value: 2, child: Text('دو بار')),
                DropdownMenuItem(value: 3, child: Text('سه بار')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _alarmRepeat = value);
                _persist();
              },
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('پخش صدای هشدار'),
              value: _alarmSound,
              onChanged: (value) {
                setState(() => _alarmSound = value);
                _persist();
              },
            ),
          ],
          if (editable) ...[
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final preset in [
                  ('۵ دقیقه', 0, 5),
                  ('۱۵ دقیقه', 0, 15),
                  ('۲۵ دقیقه', 0, 25),
                  ('۴۵ دقیقه', 0, 45),
                  ('۱ ساعت', 1, 0),
                ])
                  ActionChip(
                    label: Text(preset.$1),
                    onPressed: () => setState(() {
                      _hours = preset.$2;
                      _minutes = preset.$3;
                      _seconds = 0;
                      _initialSeconds = 0;
                      _remainingSeconds = 0;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _wheel(value: _hours, count: 24, label: 'ساعت',
                    onChanged: (v) { setState(() => _hours = v); _persist(); }),
                _wheel(value: _minutes, count: 60, label: 'دقیقه',
                    onChanged: (v) { setState(() => _minutes = v); _persist(); }),
                _wheel(value: _seconds, count: 60, label: 'ثانیه',
                    onChanged: (v) { setState(() => _seconds = v); _persist(); }),
              ],
            ),
          ],
          const SizedBox(height: 24),
          Center(
            child: SizedBox(
              width: 250,
              height: 250,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox.expand(
                    child: CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 12,
                      strokeCap: StrokeCap.round,
                      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(TimeFormatter.clock(_remainingSeconds),
                          textDirection: TextDirection.ltr,
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          )),
                      Text(_finished ? 'پایان یافت' : (_running ? 'در حال شمارش' : 'آماده')),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          if (!_running)
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: _finished ? null : _start,
                icon: const Icon(Icons.play_arrow),
                label: Text(_remainingSeconds > 0 ? 'ادامه' : 'شروع'),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pause,
                    icon: const Icon(Icons.pause),
                    label: const Text('مکث'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _stop,
                    icon: const Icon(Icons.stop),
                    label: const Text('توقف'),
                  ),
                ),
              ],
            ),
          if (!_running && (_remainingSeconds > 0 || _finished)) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _reset,
              icon: const Icon(Icons.restart_alt),
              label: const Text('بازنشانی'),
            ),
          ],
          if (_finished)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: Text(_saved ? 'زمان به پایان رسید و فعالیت ثبت شد.' : 'تایمر متوقف شده است؛ برای شروع دوباره بازنشانی کنید.',
                  textAlign: TextAlign.center),
            ),
        ],
      ),
    );
  }
}
