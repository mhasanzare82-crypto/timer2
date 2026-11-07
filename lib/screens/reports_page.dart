import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shamsi_date/shamsi_date.dart';

import '../database/app_database.dart';
import '../models/time_record.dart';
import '../utils/time_formatter.dart';

enum _Period { day, week, month, custom }

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  List<TimeRecord> _records = [];
  bool _loading = true;
  bool _working = false;
  _Period _period = _Period.day;
  String _activity = 'همه فعالیت‌ها';
  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  DateTime _to = DateTime.now();

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

  DateTime get _start {
    final now = DateTime.now();
    switch (_period) {
      case _Period.day:
        return DateTime(now.year, now.month, now.day);
      case _Period.week:
        final today = DateTime(now.year, now.month, now.day);
        return today.subtract(Duration(days: today.weekday - 1));
      case _Period.month:
        return DateTime(now.year, now.month);
      case _Period.custom:
        return DateTime(_from.year, _from.month, _from.day);
    }
  }

  DateTime get _end {
    final now = DateTime.now();
    switch (_period) {
      case _Period.day:
        return DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
      case _Period.week:
        final today = DateTime(now.year, now.month, now.day);
        return today.subtract(Duration(days: today.weekday - 1)).add(const Duration(days: 7));
      case _Period.month:
        return DateTime(now.year, now.month + 1);
      case _Period.custom:
        return DateTime(_to.year, _to.month, _to.day).add(const Duration(days: 1));
    }
  }

  List<TimeRecord> get _filtered => _records.where((r) =>
    !r.activityDate.isBefore(_start) && r.activityDate.isBefore(_end) &&
    (_activity == 'همه فعالیت‌ها' || r.title == _activity)).toList();

  int get _total => _filtered.fold(0, (sum, r) => sum + r.durationSeconds);

  List<String> get _activities => ['همه فعالیت‌ها', ...{
    for (final r in _records) r.title
  }.toList()..sort()];

  String _jalali(DateTime date) {
    final j = Jalali.fromDateTime(date);
    return '${j.year}/${j.month.toString().padLeft(2, '0')}/${j.day.toString().padLeft(2, '0')}';
  }

  Future<void> _pickDate({required bool start}) async {
    final current = start ? _from : _to;
    final selected = await showDatePicker(context: context, initialDate: current,
      firstDate: DateTime(2000), lastDate: DateTime(2100));
    if (selected == null || !mounted) return;
    setState(() {
      if (start) {
        _from = selected;
        if (_to.isBefore(_from)) _to = _from;
      } else {
        _to = selected;
        if (_to.isBefore(_from)) _from = _to;
      }
    });
  }

  Future<void> _exportExcel() async {
    setState(() => _working = true);
    try {
      final book = Excel.createExcel();
      final sheet = book['گزارش'];
      sheet.appendRow([
        TextCellValue('عنوان فعالیت'), TextCellValue('دسته‌بندی'),
        TextCellValue('تاریخ شمسی'), TextCellValue('مدت (ثانیه)'),
        TextCellValue('ساعت شروع'), TextCellValue('ساعت پایان'),
      ]);
      for (final r in _filtered) {
        sheet.appendRow([
          TextCellValue(r.title), TextCellValue(r.category),
          TextCellValue(_jalali(r.activityDate)), IntCellValue(r.durationSeconds),
          TextCellValue(r.startedAt == null ? '' : TimeOfDay.fromDateTime(r.startedAt!).format(context)),
          TextCellValue(r.endedAt == null ? '' : TimeOfDay.fromDateTime(r.endedAt!).format(context)),
        ]);
      }
      final bytes = book.encode();
      if (bytes == null) throw Exception('Excel encoding failed');
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/time-report.xlsx');
      await file.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles([XFile(file.path)], text: 'گزارش فعالیت‌ها');
    } catch (_) {
      _message('ساخت فایل Excel ناموفق بود.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _backupZip() async {
    setState(() => _working = true);
    try {
      final all = await AppDatabase.instance.getAllRecords();
      final payload = jsonEncode({
        'format': 'timer2-backup-v1',
        'createdAt': DateTime.now().toIso8601String(),
        'records': all.map((r) => r.toMap()).toList(),
      });
      final bytes = utf8.encode(payload);
      final archive = Archive()
        ..addFile(ArchiveFile('timer2-backup.json', bytes.length, bytes));
      final zipped = ZipEncoder().encode(archive);
      if (zipped == null) throw Exception('ZIP encoding failed');
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/timer2-backup.zip');
      await file.writeAsBytes(zipped, flush: true);
      await Share.shareXFiles([XFile(file.path)], text: 'پشتیبان اطلاعات برنامه');
    } catch (_) {
      _message('ساخت نسخهٔ پشتیبان ناموفق بود.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _restoreZip() async {
    setState(() => _working = true);
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['zip'], withData: true);
      if (picked == null || picked.files.isEmpty) return;
      final bytes = picked.files.single.bytes ??
        (picked.files.single.path == null ? null : await File(picked.files.single.path!).readAsBytes());
      if (bytes == null) throw Exception('No file bytes');
      final archive = ZipDecoder().decodeBytes(bytes);
      final matches = archive.files.where((f) => f.name == 'timer2-backup.json').toList();
      if (matches.isEmpty) throw Exception('Invalid backup');
      final backup = matches.first;
      final decoded = jsonDecode(utf8.decode(backup.content as List<int>)) as Map<String, dynamic>;
      if (decoded['format'] != 'timer2-backup-v1') throw Exception('Unsupported backup');
      final raw = decoded['records'] as List<dynamic>;
      final records = raw.map((e) => TimeRecord.fromMap(Map<String, Object?>.from(e as Map))).toList();
      final db = await AppDatabase.instance.database;
      await db.transaction((txn) async {
        await txn.delete('time_records');
        for (final record in records) {
          final map = record.toMap()..remove('id');
          await txn.insert('time_records', map);
        }
      });
      await _load();
      _message('بازیابی اطلاعات انجام شد.');
    } catch (_) {
      _message('فایل پشتیبان معتبر نیست یا بازیابی انجام نشد.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _message(String value) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filtered;
    return Scaffold(
      appBar: AppBar(title: const Text('گزارش‌گیری')),
      body: _loading ? const Center(child: CircularProgressIndicator()) :
        ListView(padding: const EdgeInsets.all(16), children: [
          SegmentedButton<_Period>(
            segments: const [
              ButtonSegment(value: _Period.day, label: Text('روزانه')),
              ButtonSegment(value: _Period.week, label: Text('هفتگی')),
              ButtonSegment(value: _Period.month, label: Text('ماهانه')),
              ButtonSegment(value: _Period.custom, label: Text('بازه دلخواه')),
            ],
            selected: {_period},
            onSelectionChanged: (v) => setState(() => _period = v.first),
          ),
          if (_period == _Period.custom) ...[
            ListTile(title: const Text('از تاریخ'), subtitle: Text(_jalali(_from)),
              trailing: const Icon(Icons.calendar_month), onTap: () => _pickDate(start: true)),
            ListTile(title: const Text('تا تاریخ'), subtitle: Text(_jalali(_to)),
              trailing: const Icon(Icons.calendar_month), onTap: () => _pickDate(start: false)),
          ],
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _activity, decoration: const InputDecoration(labelText: 'فعالیت'),
            items: _activities.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
            onChanged: (v) { if (v != null) setState(() => _activity = v); },
          ),
          const SizedBox(height: 16),
          Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(children: [
            const Text('مجموع مدت فعالیت در بازه'),
            const SizedBox(height: 8),
            Text(TimeFormatter.format(_total),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
            Text('${rows.length} رکورد'),
          ]))),
          const SizedBox(height: 8),
          ...rows.map((r) => Card(child: ListTile(
            title: Text(r.title),
            subtitle: Text('${_jalali(r.activityDate)} • ${r.category}'),
            trailing: Text(TimeFormatter.format(r.durationSeconds)),
          ))),
          const Divider(height: 28),
          FilledButton.icon(onPressed: _working ? null : _exportExcel,
            icon: const Icon(Icons.table_view), label: const Text('خروجی Excel')),
          const SizedBox(height: 8),
          OutlinedButton.icon(onPressed: _working ? null : _backupZip,
            icon: const Icon(Icons.archive_outlined), label: const Text('تهیه نسخه پشتیبان ZIP')),
          const SizedBox(height: 8),
          OutlinedButton.icon(onPressed: _working ? null : _restoreZip,
            icon: const Icon(Icons.restore), label: const Text('بازیابی از فایل ZIP')),
          if (_working) const Padding(padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator())),
        ]),
    );
  }
}
