import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../database/app_database.dart';
import '../models/time_record.dart';
import '../utils/time_formatter.dart';
import 'countdown_timer_page.dart';
import 'record_form_page.dart';
import 'reports_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  int _tab = 0;
  List<TimeRecord> _records = [];
  List<String> _activityNames = [];
  Timer? _ticker;
  DateTime _now = DateTime.now();
  DateTime? _startedAt;
  DateTime? _sessionStartedAt;
  Duration _elapsed = Duration.zero;
  Duration _pausedElapsed = Duration.zero;
  bool _running = false;
  bool _paused = false;
  bool _continuous = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _restoreTimerState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _now = DateTime.now();
        if (_running && !_paused && _startedAt != null) {
          _elapsed = _pausedElapsed + _now.difference(_startedAt!);
        }
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _load();
      _restoreTimerState();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _persistTimerState();
    }
  }

  Future<void> _restoreTimerState() async {
    try {
      final saved = await AppDatabase.instance.getAppState('active_timer_state');
      if (saved == null) return;
      final data = jsonDecode(saved) as Map<String, dynamic>;
      final started = (data['startedAt'] as num?)?.toInt();
      final pausedMs = (data['pausedElapsedMs'] as num?)?.toInt() ?? 0;
      final sessionMs = (data['sessionStartedAt'] as num?)?.toInt();
      final wasRunning = data['running'] as bool? ?? false;
      final wasPaused = data['paused'] as bool? ?? false;
      if (!mounted) return;
      setState(() {
        _continuous = data['continuous'] as bool? ?? true;
        _running = wasRunning;
        _paused = wasPaused;
        _pausedElapsed = Duration(milliseconds: pausedMs);
        _sessionStartedAt = sessionMs == null ? null : DateTime.fromMillisecondsSinceEpoch(sessionMs);
        _startedAt = wasRunning && !wasPaused && started != null
            ? DateTime.fromMillisecondsSinceEpoch(started)
            : null;
        _elapsed = _pausedElapsed +
            (_startedAt == null ? Duration.zero : DateTime.now().difference(_startedAt!));
      });
    } catch (_) {
      _message('بازیابی تایمر فعالیت ناموفق بود.');
    }
  }

  Future<void> _persistTimerState() async {
    final data = {
      'startedAt': _startedAt?.millisecondsSinceEpoch,
      'sessionStartedAt': _sessionStartedAt?.millisecondsSinceEpoch,
      'pausedElapsedMs': _pausedElapsed.inMilliseconds,
      'running': _running,
      'paused': _paused,
      'continuous': _continuous,
    };
    try {
      await AppDatabase.instance.saveAppState('active_timer_state', jsonEncode(data));
    } catch (_) {}
  }

  Future<void> _load() async {
    final rows = await AppDatabase.instance.getAllRecords();
    final savedNames = await AppDatabase.instance.getAppState('activity_names');
    final names = <String>{...rows.map((e) => e.title)};
    if (savedNames != null) {
      try { names.addAll((jsonDecode(savedNames) as List).cast<String>()); } catch (_) {}
    }
    if (mounted) setState(() { _records = rows; _activityNames = names.toList()..sort(); });
  }

  String _duration(Duration d) => TimeFormatter.clock(d.inSeconds);
  void _message(String value) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  void _start() {
    if (_running) return;
    setState(() {
      _startedAt = DateTime.now();
      _sessionStartedAt = DateTime.now();
      _running = true;
      _paused = false;
    });
    _persistTimerState();
  }

  void _pause() {
    if (!_running || _paused) return;
    setState(() {
      _pausedElapsed = _elapsed;
      _startedAt = null;
      _paused = true;
    });
    _persistTimerState();
  }

  void _resume() {
    if (!_running || !_paused) return;
    setState(() {
      _startedAt = DateTime.now();
      _paused = false;
    });
    _persistTimerState();
  }

  Future<void> _stopAndSave() async {
    if (!_running || _busy) return;
    final end = DateTime.now();
    final seconds = _elapsed.inSeconds;
    if (seconds <= 0) {
      _message('مدت فعالیت باید بیشتر از صفر باشد.');
      return;
    }
    final titleController = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ثبت فعالیت'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: titleController,
            autofocus: true,
            textDirection: TextDirection.rtl,
            decoration: const InputDecoration(labelText: 'نام فعالیت', hintText: 'مثلاً مطالعه'),
            onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          ),
          if (_activityNames.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Align(alignment: Alignment.centerRight, child: Text('نام‌های قبلی')),
            Wrap(spacing: 6, children: _activityNames.map((name) => ActionChip(
              label: Text(name),
              onPressed: () => titleController.text = name,
            )).toList()),
          ],
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, titleController.text.trim()), child: const Text('ذخیره')),
        ],
      ),
    );
    titleController.dispose();
    if (title == null || title.isEmpty) return;
    setState(() => _busy = true);
    try {
      final start = _sessionStartedAt ?? end.subtract(Duration(seconds: seconds));
      await AppDatabase.instance.insertRecord(TimeRecord(
        title: title,
        category: 'عمومی',
        durationSeconds: seconds,
        createdAt: DateTime.now(),
        activityDate: start,
        note: 'شروع: ${TimeFormatter.jalaliDateTime(start)}\nپایان: ${TimeFormatter.jalaliDateTime(end)}',
      ));
      if (!mounted) return;
      setState(() {
        _elapsed = Duration.zero;
        _pausedElapsed = Duration.zero;
        _startedAt = null;
        _sessionStartedAt = null;
        _running = _continuous;
        _paused = false;
        if (_continuous) _startedAt = DateTime.now();
      });
      await _persistTimerState();
      await _load();
      _message('فعالیت «$title» ذخیره شد.');
    } catch (_) {
      _message('ذخیره فعالیت انجام نشد.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _timerTab() {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Row(children: [
          const Expanded(child: Text('ثبت زمان', style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold))),
          const Text('فعالیت‌های پیوسته'),
          Switch(value: _continuous, onChanged: (v) { setState(() => _continuous = v); _persistTimerState(); }),
        ]),
        const SizedBox(height: 12),
        Card(child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
          child: Column(children: [
            Text(TimeFormatter.persianDigits('${_now.hour.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')}:${_now.second.toString().padLeft(2, '0')}'),
              style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(TimeFormatter.jalaliDate(_now), style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 22),
            const Text('مدت فعالیت جاری'),
            const SizedBox(height: 8),
            Text(_duration(_elapsed), textDirection: TextDirection.ltr,
              style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Colors.indigo)),
            const SizedBox(height: 22),
            Row(children: [
              Expanded(child: FilledButton.icon(onPressed: _running ? null : _start, icon: const Icon(Icons.play_arrow), label: const Text('شروع'))),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton.icon(onPressed: _running ? (_paused ? _resume : _pause) : null,
                icon: Icon(_paused ? Icons.play_arrow : Icons.pause), label: Text(_paused ? 'ادامه' : 'مکث'))),
              const SizedBox(width: 8),
              Expanded(child: FilledButton.tonalIcon(onPressed: _running && !_busy ? _stopAndSave : null,
                icon: const Icon(Icons.stop), label: const Text('توقف'))),
            ]),
            if (_paused) const Padding(padding: EdgeInsets.only(top: 12), child: Text('تایمر در حالت مکث است')),
          ]),
        )),
        const SizedBox(height: 12),
        Card(child: SwitchListTile(
          title: const Text('فعالیت‌های پیوسته'),
          subtitle: Text(_continuous ? 'پس از ذخیره، تایمر فعالیت بعدی خودکار شروع می‌شود.' : 'پس از ذخیره، تایمر متوقف می‌ماند.'),
          value: _continuous, onChanged: (v) { setState(() => _continuous = v); _persistTimerState(); },
        )),
        const SizedBox(height: 8),
        Text('آخرین فعالیت‌ها', style: Theme.of(context).textTheme.titleMedium),
        ..._records.take(4).map((r) => ListTile(
          leading: const CircleAvatar(child: Icon(Icons.task_alt)),
          title: Text(r.title),
          subtitle: Text('${TimeFormatter.jalaliDate(r.activityDate)} • ${TimeFormatter.format(r.durationSeconds)}'),
        )),
      ],
    );
  }

  Future<void> _addActivityName() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('افزودن نام فعالیت'),
      content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(labelText: 'نام فعالیت')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
        FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('ذخیره')),
      ],
    ));
    controller.dispose();
    if (name == null || name.isEmpty || _activityNames.contains(name)) return;
    final names = [..._activityNames, name]..sort();
    await AppDatabase.instance.saveAppState('activity_names', jsonEncode(names));
    if (mounted) setState(() => _activityNames = names);
  }

  Widget _activitiesTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(children: [
          const Expanded(child: Text('فعالیت‌ها', style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold))),
          OutlinedButton.icon(onPressed: _addActivityName, icon: const Icon(Icons.add), label: const Text('نام جدید')),
          const SizedBox(width: 6),
          FilledButton.icon(onPressed: () async {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => const RecordFormPage()));
            _load();
          }, icon: const Icon(Icons.edit_calendar), label: const Text('ثبت دستی')),
        ]),
        const SizedBox(height: 12),
        if (_activityNames.isNotEmpty) ...[
          const Text('نام‌های ذخیره‌شده', style: TextStyle(fontWeight: FontWeight.bold)),
          Wrap(spacing: 6, children: _activityNames.map((name) => Chip(label: Text(name))).toList()),
          const SizedBox(height: 8),
        ],
        if (_records.isEmpty) const Padding(padding: EdgeInsets.all(30), child: Center(child: Text('هنوز فعالیتی ثبت نشده است.'))),
        ..._records.map((r) => Card(child: ListTile(
          leading: const CircleAvatar(child: Icon(Icons.timelapse)),
          title: Text(r.title),
          subtitle: Text('${TimeFormatter.jalaliDate(r.activityDate)} • ${TimeFormatter.format(r.durationSeconds)}\n${r.note ?? r.category}'),
          isThreeLine: true,
          trailing: PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'edit') {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => RecordFormPage(record: r)));
              } else if (r.id != null) {
                await AppDatabase.instance.deleteRecord(r.id!);
              }
              _load();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('ویرایش')),
              PopupMenuItem(value: 'delete', child: Text('حذف')),
            ],
          ),
        ))),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [_timerTab(), _activitiesTab(), const ReportsPage(), const CountdownTimerPage()];
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: SafeArea(child: IndexedStack(index: _tab, children: pages)),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (v) => setState(() => _tab = v),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.timer_outlined), selectedIcon: Icon(Icons.timer), label: 'ثبت زمان'),
            NavigationDestination(icon: Icon(Icons.list_alt), label: 'فعالیت‌ها'),
            NavigationDestination(icon: Icon(Icons.bar_chart), label: 'گزارش‌گیری'),
            NavigationDestination(icon: Icon(Icons.hourglass_bottom), label: 'تایمر معکوس'),
          ],
        ),
      ),
    );
  }
}
