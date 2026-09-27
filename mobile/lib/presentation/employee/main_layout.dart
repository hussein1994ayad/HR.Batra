// =========================================================================
// HR Pro — الهيكل الرئيسي بعد تسجيل الدخول
// =========================================================================
// • 5 تبويبات: الرئيسية، الدوام، الإجازات، السلف، الإعدادات
// • هاتف: شريط سفلي — تابلت (≥600dp): شريط جانبي — شاشة عريضة (≥840dp): شريط جانبي موسّع
// • كل تبويب يُبنى أول مرة يُفتح فقط (lazy) ويبقى محفوظاً بعدها (IndexedStack)
// • زر الرجوع في تبويب غير الرئيسية يرجع للرئيسية بدل إغلاق التطبيق
// =========================================================================

import 'package:flutter/material.dart';

import '../../core/design/design.dart';
import '../shared/widgets/bottom_nav_bar.dart';
import 'attendance_screen.dart';
import 'home_screen.dart';
import 'leave_request_screen.dart';
import 'loan_request_screen.dart';
import 'settings_screen.dart';

class MainLayout extends StatefulWidget {
  final int initialTab;

  const MainLayout({super.key, this.initialTab = 0});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  late int _currentIndex;
  final Set<int> _loadedTabs = {};
  // يُبلغ HomeScreen بالعودة إليها لإعادة تحميل بيانات الدوام
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
    if (comingBackHome) _homeRefreshNotifier.value++;
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
    final size = AppBreakpoints.of(context);
    final tabs = IndexedStack(
      index: _currentIndex,
      children: List.generate(kMainDestinations.length, (index) {
        if (!_loadedTabs.contains(index)) return const SizedBox.shrink();
        return TickerMode(
          enabled: _currentIndex == index,
          child: ExcludeFocus(excluding: _currentIndex != index, child: _buildScreen(index)),
        );
      }),
    );

    return PopScope(
      canPop: _currentIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onTabChanged(0);
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: size == WindowSize.compact
            ? tabs
            : Row(
                children: [
                  SafeArea(
                    right: false,
                    left: false,
                    child: AppNavRail(currentIndex: _currentIndex, onTap: _onTabChanged, extended: size == WindowSize.expanded),
                  ),
                  Expanded(child: tabs),
                ],
              ),
        bottomNavigationBar: size == WindowSize.compact ? AppBottomNav(currentIndex: _currentIndex, onTap: _onTabChanged) : null,
      ),
    );
  }
}
