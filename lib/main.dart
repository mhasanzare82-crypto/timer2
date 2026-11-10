import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/home_page.dart';
import 'screens/activities_page.dart';
import 'screens/reports_page.dart';
import 'screens/countdown_timer_page.dart';
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
      locale: const Locale('fa', 'IR'),
      supportedLocales: const [Locale('fa', 'IR'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        scaffoldBackgroundColor: const Color(0xFFF7F8FC),
      ),
      home: const MainTabsPage(),
    );
  }
}

class MainTabsPage extends StatefulWidget {
  const MainTabsPage({super.key});

  @override
  State<MainTabsPage> createState() => _MainTabsPageState();
}

class _MainTabsPageState extends State<MainTabsPage> {
  int _selectedIndex = 0;
  final GlobalKey<ActivitiesPageState> _activitiesKey =
      GlobalKey<ActivitiesPageState>();

  late final List<Widget> _pages = [
    const HomePage(),
    ActivitiesPage(key: _activitiesKey),
    ReportsPage(),
    CountdownTimerPage(),
  ];

  static const _destinations = <NavigationDestination>[
    NavigationDestination(
      icon: Icon(Icons.timer_outlined),
      selectedIcon: Icon(Icons.timer),
      label: 'ثبت زمان',
    ),
    NavigationDestination(
      icon: Icon(Icons.list_alt_outlined),
      selectedIcon: Icon(Icons.list_alt),
      label: 'فعالیت‌ها',
    ),
    NavigationDestination(
      icon: Icon(Icons.insert_chart_outlined),
      selectedIcon: Icon(Icons.insert_chart),
      label: 'گزارش‌گیری',
    ),
    NavigationDestination(
      icon: Icon(Icons.hourglass_bottom_outlined),
      selectedIcon: Icon(Icons.hourglass_bottom),
      label: 'تایمر معکوس',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
          if (index == 1) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _activitiesKey.currentState?.refresh();
            });
          }
        },
        destinations: _destinations,
      ),
    );
  }
}
