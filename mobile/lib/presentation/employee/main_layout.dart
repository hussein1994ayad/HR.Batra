// =========================================================================
// HR Pro v6.0 — الهيكل العام للتطبيق (Main Layout)
// =========================================================================
// هذا الملف هو الحاوية الرئيسية للتطبيق بعد تسجيل الدخول.
//
// ما يفعله:
//   • يعرض شريط التبويب السفلي (Bottom Navigation Bar)
//   • يُدير الانتقال بين تبويبات الموظف: الرئيسية، الدوام، الإجازات، السلف، الإعدادات
//   • يستخدم IndexedStack لإبقاء حالة كل تبويب في الذاكرة
//   • يُرسل ValueNotifier للشاشة الرئيسية لتحديث بيانات الدوام عند العودة إليها
//
// للتعديل على التبويبات: غيّر _tabs وقائمة NavBar في هذا الملف
// لإضافة تبويب جديد: أضف الشاشة في _tabs وزر في BottomNavBar
// =========================================================================

// =========================================================================
// نظام HR Pro v6.0 - تخطيط الهيكل الرئيسي للتطبيق (Main App Layout Container)
// =========================================================================

import 'package:flutter/material.dart';

import '../shared/widgets/bottom_nav_bar.dart';
import '../shared/widgets/glass_background.dart';
import 'attendance_screen.dart';
import 'home_screen.dart';
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
  // يُستخدم لإبلاغ HomeScreen بالعودة إليها (لإعادة تحميل بيانات الدوام)
  final ValueNotifier<int> _homeRefreshNotifier = ValueNotifier<int>(0);

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
    final comingBackHome = index == 0 && _currentIndex != 0;
    setState(() {
      _currentIndex = index;
      _loadedTabs.add(index);
    });
    // لما يرجع للشاشة الرئيسية، ننبّه الـ HomeScreen لتحديث بيانات الدوام
    if (comingBackHome) {
      _homeRefreshNotifier.value++;
    }
  }

  Widget _buildScreen(int index) {
    switch (index) {
      case 0:
        return HomeScreen(onTabChange: _onTabChanged, refreshNotifier: _homeRefreshNotifier);
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
  void dispose() {
    _homeRefreshNotifier.dispose();
    super.dispose();
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
