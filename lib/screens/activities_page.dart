import 'package:flutter/material.dart';

import '../database/app_database.dart';
import '../models/time_record.dart';
import '../utils/time_formatter.dart';
import 'package:shamsi_date/shamsi_date.dart';
import 'record_form_page.dart';

class ActivitiesPage extends StatefulWidget {
  const ActivitiesPage({super.key});

  @override
  State<ActivitiesPage> createState() => _ActivitiesPageState();
}

class _ActivitiesPageState extends State<ActivitiesPage> {
  List<TimeRecord> _records = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final records = await AppDatabase.instance.getAllRecords();
    if (!mounted) return;
    setState(() { _records = records; _loading = false; });
  }

  String _date(DateTime value) {
    final j = Jalali.fromDateTime(value);
    return '${j.year}/${j.month.toString().padLeft(2, '0')}/${j.day.toString().padLeft(2, '0')}';
  }

  Future<void> _edit(TimeRecord record) async {
    final saved = await Navigator.push<bool>(context,
      MaterialPageRoute(builder: (_) => RecordFormPage(record: record)));
    if (saved == true) _load();
  }

  Future<void> _delete(TimeRecord record) async {
    if (record.id == null) return;
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) =>
      AlertDialog(title: const Text('حذف فعالیت'),
        content: Text('«${record.title}» حذف شود؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
        ]));
    if (confirmed == true) {
      await AppDatabase.instance.deleteRecord(record.id!);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('فعالیت‌ها')),
    body: _loading ? const Center(child: CircularProgressIndicator())
      : _records.isEmpty ? const Center(child: Text('هنوز فعالیتی ثبت نشده است.'))
      : RefreshIndicator(onRefresh: _load, child: ListView.builder(
        padding: const EdgeInsets.all(12), itemCount: _records.length,
        itemBuilder: (context, index) {
          final record = _records[index];
          final start = record.startedAt;
          final end = record.endedAt;
          return Card(child: ListTile(
            title: Text(record.title, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('${record.category}  •  ${_date(record.activityDate)}\n'
              'مدت: ${TimeFormatter.format(record.durationSeconds)}\n'
              'شروع: ${start == null ? '—' : TimeOfDay.fromDateTime(start).format(context)}'
              '   پایان: ${end == null ? '—' : TimeOfDay.fromDateTime(end).format(context)}'),
            isThreeLine: true,
            onTap: () => _edit(record),
            trailing: IconButton(icon: const Icon(Icons.delete_outline),
              onPressed: () => _delete(record)),
          ));
        },
      )),
    floatingActionButton: FloatingActionButton(
      onPressed: () async {
        final saved = await Navigator.push<bool>(context,
          MaterialPageRoute(builder: (_) => const RecordFormPage()));
        if (saved == true) _load();
      },
      child: const Icon(Icons.add),
    ),
  );
}
