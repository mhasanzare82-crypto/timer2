import 'package:flutter/material.dart';
import 'package:shamsi_date/shamsi_date.dart';

Future<DateTime?> showJalaliDatePicker({
  required BuildContext context,
  required DateTime initialDate,
}) async {
  final initial = Jalali.fromDateTime(initialDate);
  var year = initial.year;
  var month = initial.month;
  var day = initial.day.clamp(1, month <= 6 ? 31 : (month <= 11 ? 30 : 29)).toInt();

  return showDialog<DateTime>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) {
        final maxDay = month <= 6 ? 31 : (month <= 11 ? 30 : 29);
        if (day > maxDay) day = maxDay;
        return AlertDialog(
          title: const Text('انتخاب تاریخ شمسی'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: day,
                    decoration: const InputDecoration(labelText: 'روز'),
                    items: List.generate(maxDay, (i) => i + 1)
                      .map((v) => DropdownMenuItem(value: v, child: Text('$v'))).toList(),
                    onChanged: (v) { if (v != null) setDialogState(() => day = v); },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: month,
                    decoration: const InputDecoration(labelText: 'ماه'),
                    items: List.generate(12, (i) => i + 1)
                      .map((v) => DropdownMenuItem(value: v, child: Text('$v'))).toList(),
                    onChanged: (v) {
                      if (v != null) setDialogState(() {
                        month = v;
                        final limit = month <= 6 ? 31 : (month <= 11 ? 30 : 29);
                        if (day > limit) day = limit;
                      });
                    },
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                value: year,
                decoration: const InputDecoration(labelText: 'سال'),
                items: List.generate(151, (i) => initial.year - 75 + i)
                  .map((v) => DropdownMenuItem(value: v, child: Text('$v'))).toList(),
                onChanged: (v) { if (v != null) setDialogState(() => year = v); },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('انصراف')),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, Jalali(year, month, day).toDateTime()),
              child: const Text('تأیید'),
            ),
          ],
        );
      },
    ),
  );
}
