import 'package:flutter/material.dart';
import 'package:shamsi_date/shamsi_date.dart';

import '../database/app_database.dart';
import '../utils/time_formatter.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  int _dailyTotal = 0;
  int _monthlyTotal = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    final now = DateTime.now();

    final dayStart = DateTime(now.year, now.month, now.day);
    final nextDay = dayStart.add(const Duration(days: 1));

    final jalaliNow = Jalali.fromDateTime(now);
    final monthStartJalali = Jalali(jalaliNow.year, jalaliNow.month, 1);
    final nextMonthJalali = jalaliNow.month == 12
        ? Jalali(jalaliNow.year + 1, 1, 1)
        : Jalali(jalaliNow.year, jalaliNow.month + 1, 1);
    final monthStart = monthStartJalali.toDateTime();
    final nextMonth = nextMonthJalali.toDateTime();

    final daily = await AppDatabase.instance.getTotalSeconds(
      start: dayStart,
      end: nextDay,
    );

    final monthly = await AppDatabase.instance.getTotalSeconds(
      start: monthStart,
      end: nextMonth,
    );

    if (!mounted) return;

    setState(() {
      _dailyTotal = daily;
      _monthlyTotal = monthly;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('گزارش‌ها'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ListTile(
                  title: const Text('مجموع فعالیت امروز'),
                  subtitle: Text(TimeFormatter.format(_dailyTotal)),
                ),
                const Divider(),
                ListTile(
                  title: const Text('مجموع فعالیت این ماه'),
                  subtitle: Text(TimeFormatter.format(_monthlyTotal)),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    setState(() => _loading = true);
                    _loadReports();
                  },
                  child: const Text('به‌روزرسانی گزارش'),
                ),
              ],
            ),
    );
  }
}
