import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:persian_datetime_picker/persian_datetime_picker.dart';
import 'package:shamsi_date/shamsi_date.dart';
import 'package:share_plus/share_plus.dart';

import '../database/app_database.dart';
import '../models/time_record.dart';
import '../utils/time_formatter.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  List<TimeRecord> _records = [];
  List<String> _activities = [];
  final Set<String> _selectedActivities = {};
  DateTime _from = DateTime.now().subtract(const Duration(days: 6));
  DateTime _to = DateTime.now();
  bool _loading = true;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final records = await AppDatabase.instance.getAllRecords();
      final activities = await AppDatabase.instance.getActivityNames();
      if (!mounted) return;
      setState(() {
        _records = records;
        _activities = activities;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  DateTime get _rangeEnd => DateTime(_to.year, _to.month, _to.day + 1);

  List<TimeRecord> get _filtered => _records.where((record) {
        final date = record.activityDate;
        final inRange = !date.isBefore(DateTime(_from.year, _from.month, _from.day)) &&
            date.isBefore(_rangeEnd);
        final inActivity = _selectedActivities.isEmpty ||
            _selectedActivities.contains(record.title);
        return inRange && inActivity;
      }).toList();

  int get _total => _filtered.fold(0, (sum, item) => sum + item.durationSeconds);

  String _date(DateTime value) {
    final j = Jalali.fromDateTime(value);
    return '${j.year}/${j.month.toString().padLeft(2, '0')}/${j.day.toString().padLeft(2, '0')}';
  }

  Future<void> _preset(String value) async {
    final now = DateTime.now();
    final j = Jalali.fromDateTime(now);
    DateTime from;
    if (value == 'روزانه') {
      from = DateTime(now.year, now.month, now.day);
    } else if (value == 'هفتگی') {
      from = DateTime(now.year, now.month, now.day).subtract(Duration(days: (now.weekday + 1) % 7));
    } else {
      from = Jalali(j.year, j.month, 1).toDateTime();
    }
    setState(() {
      _from = from;
      _to = now;
    });
  }

  Future<void> _pickDate(bool isStart) async {
    final current = isStart ? _from : _to;
    final picked = await showPersianDatePicker(
      context: context,
      initialDate: Jalali.fromDateTime(current),
      firstDate: Jalali(1300, 1, 1),
      lastDate: Jalali(1500, 12, 29),
      helpText: isStart ? 'از تاریخ' : 'تا تاریخ',
      textDirection: TextDirection.rtl,
    );
    if (picked == null || !mounted) return;
    final date = picked.toDateTime();
    setState(() {
      if (isStart) {
        _from = date;
      } else {
        _to = date;
      }
    });
  }

  Future<void> _exportExcel() async {
    if (_filtered.isEmpty) {
      _message('برای خروجی، رکوردی در این بازه وجود ندارد.');
      return;
    }
    setState(() => _working = true);
    try {
      final book = Excel.createExcel();
      final sheet = book['گزارش فعالیت'];
      sheet.appendRow([
        TextCellValue('نام فعالیت'),
        TextCellValue('تاریخ شمسی'),
        TextCellValue('مدت (ثانیه)'),
        TextCellValue('مدت'),
        TextCellValue('یادداشت'),
      ]);
      for (final item in _filtered) {
        sheet.appendRow([
          TextCellValue(item.title),
          TextCellValue(_date(item.activityDate)),
          IntCellValue(item.durationSeconds),
          TextCellValue(TimeFormatter.format(item.durationSeconds)),
          TextCellValue(item.note ?? ''),
        ]);
      }
      final bytes = book.encode();
      if (bytes == null) throw StateError('Excel encoding failed');
      await Share.shareXFiles([
        XFile.fromData(Uint8List.fromList(bytes),
            name: 'time_report.xlsx',
            mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'),
      ], text: 'گزارش فعالیت‌ها');
    } catch (error) {
      _message('ساخت فایل اکسل ناموفق بود: $error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _exportBackup() async {
    setState(() => _working = true);
    try {
      final payload = {
        'format': 'timer2-backup',
        'version': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'records': _records.map((e) => e.toMap()).toList(),
        'activities': _activities,
        'appState': await AppDatabase.instance.getAllAppStates(),
      };
      final jsonBytes = utf8.encode(const JsonEncoder.withIndent('  ').convert(payload));
      final archive = Archive()
        ..addFile(ArchiveFile('timer2-backup.json', jsonBytes.length, jsonBytes));
      final zipped = ZipEncoder().encode(archive);
      if (zipped == null) throw StateError('ZIP encoding failed');
      await Share.shareXFiles([
        XFile.fromData(Uint8List.fromList(zipped),
            name: 'timer2-backup.zip', mimeType: 'application/zip'),
      ], text: 'نسخه پشتیبان برنامه تایمر');
    } catch (error) {
      _message('ساخت نسخه پشتیبان ناموفق بود: $error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _importBackup() async {
    setState(() => _working = true);
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
        withData: true,
      );
      if (picked == null || picked.files.single.bytes == null) return;
      final archive = ZipDecoder().decodeBytes(picked.files.single.bytes!);
      final backupFiles = archive.files.where((f) => f.name == 'timer2-backup.json').toList();
      final file = backupFiles.isEmpty ? null : backupFiles.first;
      if (file == null) throw const FormatException('فایل پشتیبان معتبر نیست.');
      final data = jsonDecode(utf8.decode(file.content as List<int>)) as Map<String, dynamic>;
      if (data['format'] != 'timer2-backup' || data['version'] != 1) {
        throw const FormatException('نسخه فایل پشتیبان پشتیبانی نمی‌شود.');
      }
      final records = (data['records'] as List<dynamic>).map((e) {
        final map = Map<String, Object?>.from(e as Map);
        map['id'] = null;
        return TimeRecord.fromMap(map);
      }).toList();
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('بازیابی نسخه پشتیبان'),
          content: Text('${records.length} رکورد به داده‌های فعلی اضافه می‌شود. ادامه می‌دهید؟'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('انصراف')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('بازیابی')),
          ],
        ),
      );
      if (confirmed != true) return;
      for (final record in records) {
        await AppDatabase.instance.insertRecord(record);
      }
      final names = (data['activities'] as List<dynamic>? ?? []).cast<String>();
      for (final name in names) {
        await AppDatabase.instance.addActivity(name);
      }
      final appState = Map<String, dynamic>.from(data['appState'] as Map? ?? {});
      for (final entry in appState.entries) {
        await AppDatabase.instance.saveAppState(entry.key, entry.value as String);
      }
      await _load();
      _message('بازیابی انجام شد؛ رکوردها به اطلاعات فعلی اضافه شدند.');
    } catch (error) {
      _message('بازیابی انجام نشد: $error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(value), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final filtered = _filtered;
    return Scaffold(
      appBar: AppBar(title: const Text('گزارش‌گیری')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final preset in ['روزانه', 'هفتگی', 'ماهانه'])
                OutlinedButton(
                  onPressed: () => _preset(preset),
                  child: Text(preset),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: OutlinedButton.icon(
              onPressed: () => _pickDate(true),
              icon: const Icon(Icons.calendar_month),
              label: Text('از ${_date(_from)}'),
            )),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(
              onPressed: () => _pickDate(false),
              icon: const Icon(Icons.event),
              label: Text('تا ${_date(_to)}'),
            )),
          ]),
          const SizedBox(height: 16),
          Text('فیلتر فعالیت‌ها', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text('اگر هیچ فعالیتی انتخاب نشود، گزارش همه فعالیت‌ها نمایش داده می‌شود.'),
          ..._activities.map((name) => CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(name),
            value: _selectedActivities.contains(name),
            onChanged: (checked) => setState(() {
              if (checked == true) {
                _selectedActivities.add(name);
              } else {
                _selectedActivities.remove(name);
              }
            }),
          )),
          const Divider(),
          Card(
            child: ListTile(
              title: const Text('مجموع زمان در بازه انتخابی'),
              subtitle: Text('${filtered.length} نوبت فعالیت'),
              trailing: Text(TimeFormatter.format(_total),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 8),
          if (filtered.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('در این بازه فعالیتی ثبت نشده است.', textAlign: TextAlign.center),
            )
          else
            ...filtered.map((record) => Card(
              child: ListTile(
                title: Text(record.title),
                subtitle: Text('${_date(record.activityDate)} • ${TimeFormatter.format(record.durationSeconds)}'),
                trailing: Text(TimeFormatter.clock(record.durationSeconds)),
              ),
            )),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _working ? null : _exportExcel,
            icon: const Icon(Icons.table_view),
            label: const Text('خروجی اکسل'),
          ),
          OutlinedButton.icon(
            onPressed: _working ? null : _exportBackup,
            icon: const Icon(Icons.archive_outlined),
            label: const Text('خروجی ZIP (نسخه پشتیبان)'),
          ),
          OutlinedButton.icon(
            onPressed: _working ? null : _importBackup,
            icon: const Icon(Icons.restore),
            label: const Text('وارد کردن نسخه پشتیبان ZIP'),
          ),
          if (_working) const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: CircularProgressIndicator()),
          ),
        ],
      ),
    );
  }
}
