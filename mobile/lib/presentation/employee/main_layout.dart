// =========================================================================
// نظام HR Pro v6.0 - تخطيط الهيكل الرئيسي للتطبيق (Main App Layout Container)
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
  late int _currentIndex;
  final Set<int> _loadedTabs = {};

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialTab;
    _loadedTabs.add(widget.initialTab);
  }

  @override
  void didUpdateWidget(covariant MainLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    // التحديث عند تغيير التبويب خارجياً (مثلاً عبر الـ Router)
    if (oldWidget.initialTab != widget.initialTab) {
      setState(() {
        _currentIndex = widget.initialTab;
        _loadedTabs.add(widget.initialTab);
      });
    }
  }

  void _onTabChanged(int index) {
    setState(() {
      _currentIndex = index;
      _loadedTabs.add(index);
    });
  }

  Widget _buildScreen(int index) {
    switch (index) {
      case 0:
        return HomeScreen(onTabChange: _onTabChanged);
      case 1:
        return const AttendanceScreen();
      case 2:
        return const LeaveRequestScreen();
      case 3:
        return const LoanRequestScreen();
      case 4:
        return const SettingsScreen();
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: IndexedStack(
          index: _currentIndex,
          children: List.generate(5, (index) {
            final isLoaded = _loadedTabs.contains(index);
            if (!isLoaded) {
              return const SizedBox.shrink();
            }
            return TickerMode(
              enabled: _currentIndex == index,
              child: _buildScreen(index),
            );
          }),
        ),
        bottomNavigationBar: PremiumBottomNavBar(
          currentIndex: _currentIndex,
          onTap: _onTabChanged,
        ),
      ),
    );
  }
}
