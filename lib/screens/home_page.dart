import 'dart:async';
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
  Timer? _ticker;
  DateTime _now = DateTime.now();
  DateTime? _startedAt;
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
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final rows = await AppDatabase.instance.getAllRecords();
    if (mounted) setState(() => _records = rows);
  }

  String _duration(Duration d) => TimeFormatter.clock(d.inSeconds);
  void _message(String value) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  void _start() {
    if (_running) return;
    setState(() {
      _startedAt = DateTime.now();
      _running = true;
      _paused = false;
    });
  }

  void _pause() {
    if (!_running || _paused) return;
    setState(() {
      _pausedElapsed = _elapsed;
      _startedAt = null;
      _paused = true;
    });
  }

  void _resume() {
    if (!_running || !_paused) return;
    setState(() {
      _startedAt = DateTime.now();
      _paused = false;
    });
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
        content: TextField(
          controller: titleController,
          autofocus: true,
          textDirection: TextDirection.rtl,
          decoration: const InputDecoration(labelText: 'نام فعالیت', hintText: 'مثلاً مطالعه'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
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
      final start = end.subtract(Duration(seconds: seconds));
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
        _running = _continuous;
        _paused = false;
        if (_continuous) _startedAt = DateTime.now();
      });
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
          Switch(value: _continuous, onChanged: (v) => setState(() => _continuous = v)),
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
          value: _continuous, onChanged: (v) => setState(() => _continuous = v),
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

  Widget _activitiesTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(children: [
          const Expanded(child: Text('فعالیت‌ها', style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold))),
          FilledButton.icon(onPressed: () async {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => const RecordFormPage()));
            _load();
          }, icon: const Icon(Icons.add), label: const Text('ثبت دستی')),
        ]),
        const SizedBox(height: 12),
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
