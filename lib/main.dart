import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/main_tabs_page.dart';
import 'theme/app_theme.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await NotificationService.instance.initialize();
  } catch (error) {
    debugPrint('Notification initialization error: $error');
  }

  runApp(const TimeTrackerApp());
}

class TimeTrackerApp extends StatelessWidget {
  const TimeTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ثبت مدت‌زمان',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      locale: const Locale('fa', 'IR'),
      supportedLocales: const [Locale('fa', 'IR'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const MainTabsPage(),
    );
  }
}
