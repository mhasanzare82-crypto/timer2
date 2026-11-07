import 'package:flutter/material.dart';

import 'activities_page.dart';
import 'countdown_timer_page.dart';
import 'home_page.dart';
import 'reports_page.dart';

class MainTabsPage extends StatefulWidget {
  const MainTabsPage({super.key});

  @override
  State<MainTabsPage> createState() => _MainTabsPageState();
}

class _MainTabsPageState extends State<MainTabsPage> {
  int _index = 0;

  static const _pages = <Widget>[
    HomePage(),
    ActivitiesPage(),
    ReportsPage(),
    CountdownTimerPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.timer_outlined), selectedIcon: Icon(Icons.timer), label: 'ثبت زمان'),
          NavigationDestination(icon: Icon(Icons.list_alt_outlined), selectedIcon: Icon(Icons.list_alt), label: 'فعالیت‌ها'),
          NavigationDestination(icon: Icon(Icons.analytics_outlined), selectedIcon: Icon(Icons.analytics), label: 'گزارش‌گیری'),
          NavigationDestination(icon: Icon(Icons.hourglass_bottom), label: 'تایمر معکوس'),
        ],
      ),
    );
  }
}
