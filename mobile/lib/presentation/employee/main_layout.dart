// =========================================================================
// HR Pro - main layout with the bottom navigation tabs
// =========================================================================

import 'package:flutter/material.dart';
import '../shared/widgets/bottom_nav_bar.dart';
import '../shared/widgets/glass_background.dart';
import 'home_screen.dart';
import 'attendance_screen.dart';
import 'leave_request_screen.dart';
import 'loan_request_screen.dart';
import 'settings_screen.dart';

class MainLayout extends StatefulWidget {
  final int initialTab;

  const MainLayout({
    super.key,
    this.initialTab = 0,
  });

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  static const _tabCount = 5;

  late int _currentIndex;

  /// Tabs are built the first time they are opened and then kept alive, so
  /// app start-up only pays for the tab the user actually sees.
  final _visited = <int>{};

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialTab.clamp(0, _tabCount - 1);
    _visited.add(_currentIndex);
  }

  @override
  void didUpdateWidget(covariant MainLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The router can switch tabs from outside (e.g. /employee/attendance).
    if (oldWidget.initialTab != widget.initialTab) {
      _onTabChanged(widget.initialTab);
    }
  }

  void _onTabChanged(int index) {
    final tab = index.clamp(0, _tabCount - 1);
    if (tab == _currentIndex) return;
    setState(() {
      _currentIndex = tab;
      _visited.add(tab);
    });
  }

  Widget _buildTab(int index) {
    switch (index) {
      case 0:
        return HomeScreen(onTabChange: _onTabChanged);
      case 1:
        return const AttendanceScreen();
      case 2:
        return const LeaveRequestScreen();
      case 3:
        return const LoanRequestScreen();
      default:
        return const SettingsScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassBackground(
      safeBottom: false,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: IndexedStack(
          index: _currentIndex,
          children: [
            for (var i = 0; i < _tabCount; i++)
              _visited.contains(i)
                  ? TickerMode(enabled: i == _currentIndex, child: _buildTab(i))
                  : const SizedBox.shrink(),
          ],
        ),
        bottomNavigationBar: PremiumBottomNavBar(
          currentIndex: _currentIndex,
          onTap: _onTabChanged,
        ),
      ),
    );
  }
}
