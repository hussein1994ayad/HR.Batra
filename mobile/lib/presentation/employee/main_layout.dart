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

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialTab;
  }

  @override
  void didUpdateWidget(covariant MainLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    // التحديث عند تغيير التبويب خارجياً (مثلاً عبر الـ Router)
    if (oldWidget.initialTab != widget.initialTab) {
      setState(() {
        _currentIndex = widget.initialTab;
      });
    }
  }

  void _onTabChanged(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    // قائمة الشاشات المرتبطة بشريط التنقل
    // نمرر دوال التنقل للشاشة الرئيسية لتسهيل الانتقال عبر بطاقاتها الفعالة
    final List<Widget> screens = [
      HomeScreen(onTabChange: _onTabChanged),
      const AttendanceScreen(),
      const LeaveRequestScreen(),
      const LoanRequestScreen(),
      const SettingsScreen(),
    ];

    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: IndexedStack(
          index: _currentIndex,
          children: screens,
        ),
        bottomNavigationBar: PremiumBottomNavBar(
          currentIndex: _currentIndex,
          onTap: _onTabChanged,
        ),
      ),
    );
  }
}
