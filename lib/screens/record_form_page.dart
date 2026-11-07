import 'package:flutter/material.dart';
import 'package:shamsi_date/shamsi_date.dart';

import '../database/app_database.dart';
import '../models/time_record.dart';
import '../utils/jalali_date_picker.dart';

class RecordFormPage extends StatefulWidget {
  final TimeRecord? record;

  const RecordFormPage({
    super.key,
    this.record,
  });

  @override
  State<RecordFormPage> createState() => _RecordFormPageState();
}

class _RecordFormPageState extends State<RecordFormPage> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _titleController;
  late final TextEditingController _hoursController;
  late final TextEditingController _minutesController;
  late final TextEditingController _secondsController;
  late final TextEditingController _noteController;

  final List<String> _categories = [
    'عمومی',
    'مطالعه',
    'کار',
    'ورزش',
    'استراحت',
    'تایمر',
  ];

  late String _category;
  late DateTime _activityDate;

  @override
  void initState() {
    super.initState();

    final record = widget.record;

    _titleController = TextEditingController(
      text: record?.title ?? '',
    );

    _hoursController = TextEditingController(
      text: ((record?.durationSeconds ?? 0) ~/ 3600).toString(),
    );

    _minutesController = TextEditingController(
      text: (((record?.durationSeconds ?? 0) % 3600) ~/ 60).toString(),
    );

    _secondsController = TextEditingController(
      text: ((record?.durationSeconds ?? 0) % 60).toString(),
    );

    _noteController = TextEditingController(
      text: record?.note ?? '',
    );

    _category = record?.category ?? 'عمومی';
    _activityDate = record?.activityDate ?? DateTime.now();

    if (!_categories.contains(_category)) {
      _categories.add(_category);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _hoursController.dispose();
    _minutesController.dispose();
    _secondsController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  int _number(TextEditingController controller) {
    final number = int.tryParse(controller.text.trim()) ?? 0;
    return number < 0 ? 0 : number;
  }

  String _jalaliDate(DateTime date) {
    final j = Jalali.fromDateTime(date);
    return '${j.year}/${j.month.toString().padLeft(2, '0')}/${j.day.toString().padLeft(2, '0')}';
  }

  Future<void> _chooseDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _activityDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (selected != null && mounted) {
      setState(() {
        _activityDate = DateTime(
          selected.year,
          selected.month,
          selected.day,
          _activityDate.hour,
          _activityDate.minute,
        );
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final duration = _number(_hoursController) * 3600 +
        _number(_minutesController) * 60 +
        _number(_secondsController);

    if (duration <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('مدت‌زمان باید بیشتر از صفر باشد.'),
        ),
      );
      return;
    }

    final now = DateTime.now();

    final record = TimeRecord(
      id: widget.record?.id,
      title: _titleController.text.trim(),
      category: _category,
      durationSeconds: duration,
      createdAt: widget.record?.createdAt ?? now,
      activityDate: _activityDate,
      note: _noteController.text.trim().isEmpty
          ? null
          : _noteController.text.trim(),
    );

    try {
      if (widget.record == null) {
        await AppDatabase.instance.insertRecord(record);
      } else {
        await AppDatabase.instance.updateRecord(record);
      }

      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ذخیرهٔ اطلاعات ناموفق بود.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.record == null ? 'ثبت فعالیت' : 'ویرایش فعالیت',
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'عنوان فعالیت',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'عنوان را وارد کنید.';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _category,
              decoration: const InputDecoration(
                labelText: 'دسته‌بندی',
                border: OutlineInputBorder(),
              ),
              items: _categories
                  .map(
                    (category) => DropdownMenuItem(
                      value: category,
                      child: Text(category),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _category = value);
                }
              },
            ),
            const SizedBox(height: 16),
            const Text('مدت‌زمان فعالیت'),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _hoursController,
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
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'ثانیه',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('تاریخ فعالیت'),
              subtitle: Text(
                '${_activityDate.year}/'
                '${_activityDate.month.toString().padLeft(2, '0')}/'
                '${_activityDate.day.toString().padLeft(2, '0')}',
              ),
              trailing: const Icon(Icons.calendar_month),
              onTap: _chooseDate,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _noteController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'یادداشت (اختیاری)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _save,
              child: const Text('ذخیره'),
            ),
          ],
        ),
      ),
    );
  }
}
