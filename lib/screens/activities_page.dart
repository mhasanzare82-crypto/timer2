import 'package:flutter/material.dart';
import 'package:shamsi_date/shamsi_date.dart';

import '../database/app_database.dart';
import '../models/time_record.dart';
import '../utils/time_formatter.dart';

class ActivitiesPage extends StatefulWidget {
  const ActivitiesPage({super.key});

  @override
  State<ActivitiesPage> createState() => _ActivitiesPageState();
}

class _ActivitiesPageState extends State<ActivitiesPage> {
  List<String> _activities = [];
  bool _loading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final values = await AppDatabase.instance.getActivityNames();
      if (!mounted) return;
      setState(() {
        _activities = values;
        _loadError = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = 'بارگذاری فعالیت‌ها ناموفق بود: $error';
        _loading = false;
      });
    }
  }

  Future<void> _add() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('افزودن فعالیت'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'نام فعالیت',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('ذخیره'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty) return;
    try {
      await AppDatabase.instance.addActivity(name);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('فعالیت ذخیره شد.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ذخیره فعالیت ناموفق بود: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('فعالیت‌ها')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('افزودن فعالیت'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_loadError!, textAlign: TextAlign.center),
                ))
          : _activities.isEmpty
              ? const Center(child: Text('هنوز فعالیتی تعریف نشده است.'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                  itemCount: _activities.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final name = _activities[index];
                    return FutureBuilder<List<TimeRecord>>(
                      future: AppDatabase.instance.getRecordsForActivity(name),
                      builder: (context, snapshot) {
                        final records = snapshot.data ?? const <TimeRecord>[];
                        final total = records.fold<int>(
                          0, (sum, record) => sum + record.durationSeconds,
                        );
                        return Card(
                          child: ListTile(
                            title: Text(name),
                            subtitle: snapshot.connectionState == ConnectionState.waiting
                                ? const Text('در حال محاسبه زمان...')
                                : Text('${records.length} نوبت • مجموع ${TimeFormatter.format(total)}'),
                            trailing: const Icon(Icons.chevron_left),
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ActivityDetailPage(title: name),
                                ),
                              );
                              if (mounted) await _load();
                            },
                          ),
                        );
                      },
                    );
                  },
                ),
    );
  }
}

class ActivityDetailPage extends StatefulWidget {
  const ActivityDetailPage({super.key, required this.title});
  final String title;

  @override
  State<ActivityDetailPage> createState() => _ActivityDetailPageState();
}

class _ActivityDetailPageState extends State<ActivityDetailPage> {
  List<TimeRecord> _records = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final values =
        await AppDatabase.instance.getRecordsForActivity(widget.title);
    if (!mounted) return;
    setState(() {
      _records = values;
      _loading = false;
    });
  }

  String _date(DateTime value) {
    final j = Jalali.fromDateTime(value);
    return '${j.year}/${j.month.toString().padLeft(2, '0')}/${j.day.toString().padLeft(2, '0')}';
  }

  String _time(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  DateTime _endTime(TimeRecord record) {
    // Records created by the stopwatch/countdown store the exact end time in note.
    final lines = record.note?.split('\n') ?? [];
    for (final line in lines) {
      if (line.startsWith('پایان: ')) {
        final value = line.substring('پایان: '.length);
        final parts = value.split(' ');
        if (parts.length == 2) {
          final date = parts[0].split('/').map(int.tryParse).toList();
          final clock = parts[1].split(':').map(int.tryParse).toList();
          if (date.length == 3 && clock.length >= 2 &&
              date.every((e) => e != null) &&
              clock.take(2).every((e) => e != null)) {
            try {
              final g = Jalali(date[0]!, date[1]!, date[2]!).toDateTime();
              return DateTime(g.year, g.month, g.day, clock[0]!, clock[1]!);
            } catch (_) {}
          }
        }
      }
    }
    return record.createdAt;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _records.isEmpty
              ? const Center(child: Text('هنوز زمانی برای این فعالیت ثبت نشده است.'))
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _records.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final record = _records[index];
                    final end = _endTime(record);
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.calendar_month_outlined, size: 19),
                                const SizedBox(width: 8),
                                Expanded(child: Text(_date(record.activityDate), style: const TextStyle(fontWeight: FontWeight.w600))),
                                Text(TimeFormatter.format(record.durationSeconds), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                const Icon(Icons.play_arrow, size: 18),
                                const SizedBox(width: 6),
                                Expanded(child: Text('شروع: ${_time(record.activityDate)}')),
                                const Icon(Icons.stop, size: 18),
                                const SizedBox(width: 6),
                                Text('پایان: ${_time(end)}'),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text('دسته‌بندی: ${record.category}'),
                            if (record.note != null && record.note!.trim().isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(record.note!, style: Theme.of(context).textTheme.bodySmall),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
