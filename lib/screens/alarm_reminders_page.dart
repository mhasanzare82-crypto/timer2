import 'dart:convert';
import 'package:flutter/material.dart';
import '../database/app_database.dart';
import '../services/notification_service.dart';

class AlarmRemindersPage extends StatefulWidget {
  const AlarmRemindersPage({super.key});
  @override
  State<AlarmRemindersPage> createState() => _AlarmRemindersPageState();
}

class _AlarmRemindersPageState extends State<AlarmRemindersPage> {
  static const _storageKey = 'user_reminders';
  final _titleController = TextEditingController();
  DateTime _scheduledAt = DateTime.now().add(const Duration(hours: 1));
  bool _daily = false, _loading = true, _saving = false;
  List<Map<String, dynamic>> _reminders = [];

  @override
  void initState() { super.initState(); _loadReminders(); }
  @override
  void dispose() { _titleController.dispose(); super.dispose(); }

  Future<void> _loadReminders() async {
    try {
      final raw = await AppDatabase.instance.getAppState(_storageKey);
      final decoded = raw == null ? <dynamic>[] : jsonDecode(raw) as List<dynamic>;
      if (!mounted) return;
      setState(() {
        _reminders = decoded.map((item) => Map<String, dynamic>.from(item as Map)).toList()
          ..sort((a, b) => (a['scheduledAt'] as int).compareTo(b['scheduledAt'] as int));
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showMessage('بارگذاری یادآورها ناموفق بود.');
    }
  }

  Future<void> _persist() => AppDatabase.instance.saveAppState(_storageKey, jsonEncode(_reminders));
  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));
  }

  Future<void> _chooseDate() async {
    final picked = await showDatePicker(context: context, initialDate: _scheduledAt,
      firstDate: DateTime.now(), lastDate: DateTime(2100), helpText: 'تاریخ یادآور');
    if (picked == null || !mounted) return;
    setState(() => _scheduledAt = DateTime(picked.year, picked.month, picked.day, _scheduledAt.hour, _scheduledAt.minute));
  }

  Future<void> _chooseTime() async {
    final picked = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_scheduledAt), helpText: 'ساعت یادآور');
    if (picked == null || !mounted) return;
    setState(() => _scheduledAt = DateTime(_scheduledAt.year, _scheduledAt.month, _scheduledAt.day, picked.hour, picked.minute));
  }

  Future<void> _addReminder() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) { _showMessage('عنوان یادآور را وارد کنید.'); return; }
    if (!_daily && !_scheduledAt.isAfter(DateTime.now())) { _showMessage('زمان یادآور باید در آینده باشد.'); return; }
    setState(() => _saving = true);
    try {
      final id = DateTime.now().microsecondsSinceEpoch.remainder(2147483647);
      final reminder = <String, dynamic>{'id': id, 'title': title, 'scheduledAt': _scheduledAt.millisecondsSinceEpoch, 'daily': _daily};
      await NotificationService.instance.scheduleReminder(id: id, title: title, scheduledAt: _scheduledAt, daily: _daily);
      _reminders.add(reminder);
      await _persist();
      _titleController.clear();
      if (!mounted) return;
      setState(() { _daily = false; _scheduledAt = DateTime.now().add(const Duration(hours: 1)); });
      _showMessage('یادآور با موفقیت ثبت شد.');
    } catch (error) { _showMessage('ثبت یادآور انجام نشد: $error'); }
    finally { if (mounted) setState(() => _saving = false); }
  }

  Future<void> _deleteReminder(Map<String, dynamic> reminder) async {
    try {
      await NotificationService.instance.cancelReminder(reminder['id'] as int);
      _reminders.removeWhere((item) => item['id'] == reminder['id']);
      await _persist();
      if (mounted) setState(() {});
      _showMessage('یادآور حذف شد.');
    } catch (_) { _showMessage('حذف یادآور ناموفق بود.'); }
  }

  String _formatDate(DateTime d) => '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
  String _formatTime(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('آلارم و یادآور'), centerTitle: true),
    body: _loading ? const Center(child: CircularProgressIndicator()) : ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('یادآور جدید', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(controller: _titleController, textInputAction: TextInputAction.done,
              decoration: const InputDecoration(labelText: 'عنوان یادآور', hintText: 'مثلاً زمان استراحت یا جلسه', border: OutlineInputBorder(), prefixIcon: Icon(Icons.edit_note))),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: OutlinedButton.icon(onPressed: _chooseDate, icon: const Icon(Icons.calendar_month), label: Text(_formatDate(_scheduledAt)))),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton.icon(onPressed: _chooseTime, icon: const Icon(Icons.access_time), label: Text(_formatTime(_scheduledAt)))),
            ]),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('تکرار روزانه'), value: _daily, onChanged: (v) => setState(() => _daily = v)),
            const SizedBox(height: 8),
            FilledButton.icon(onPressed: _saving ? null : _addReminder, icon: const Icon(Icons.notifications_active_outlined), label: Text(_saving ? 'در حال ثبت...' : 'ثبت یادآور')),
          ],
        ))),
        const SizedBox(height: 20),
        Text('یادآورهای ثبت‌شده', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        if (_reminders.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('هنوز یادآوری ثبت نشده است.', textAlign: TextAlign.center))
        else ..._reminders.map((r) {
          final date = DateTime.fromMillisecondsSinceEpoch(r['scheduledAt'] as int);
          final daily = r['daily'] as bool? ?? false;
          return Card(child: ListTile(
            leading: Icon(daily ? Icons.repeat : Icons.notifications_outlined, color: Theme.of(context).colorScheme.primary),
            title: Text(r['title'] as String),
            subtitle: Text('${_formatDate(date)}  ${_formatTime(date)}${daily ? ' • هر روز' : ''}'),
            trailing: IconButton(tooltip: 'حذف یادآور', onPressed: () => _deleteReminder(r), icon: const Icon(Icons.delete_outline)),
          ));
        }),
      ],
    ),
  );
}
