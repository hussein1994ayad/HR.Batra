// =========================================================================
// HR Pro — التنقّل الرئيسي المتجاوب
// =========================================================================
// هاتف (< 600dp): شريط سفلي NavigationBar
// تابلت/شاشة عريضة (≥ 600dp): شريط جانبي NavigationRail
// =========================================================================

import 'package:flutter/material.dart';

import '../../../core/design/design.dart';

class AppDestination {
  const AppDestination(this.icon, this.activeIcon, this.label);
  final IconData icon;
  final IconData activeIcon;
  final String label;
}

const List<AppDestination> kMainDestinations = [
  AppDestination(Icons.home_outlined, Icons.home_rounded, 'الرئيسية'),
  AppDestination(Icons.fingerprint_rounded, Icons.fingerprint_rounded, 'الدوام'),
  AppDestination(Icons.event_note_outlined, Icons.event_note_rounded, 'الإجازات'),
  AppDestination(Icons.account_balance_wallet_outlined, Icons.account_balance_wallet_rounded, 'السلف'),
  AppDestination(Icons.settings_outlined, Icons.settings_rounded, 'الإعدادات'),
];

/// الشريط السفلي للهاتف.
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({super.key, required this.currentIndex, required this.onTap});

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
      child: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (i) {
          AppHaptics.select();
          onTap(i);
        },
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          for (final d in kMainDestinations)
            NavigationDestination(icon: Icon(d.icon), selectedIcon: Icon(d.activeIcon), label: d.label, tooltip: d.label),
        ],
      ),
    );
  }
}

/// الشريط الجانبي للتابلت.
class AppNavRail extends StatelessWidget {
  const AppNavRail({super.key, required this.currentIndex, required this.onTap, this.extended = false});

  final int currentIndex;
  final ValueChanged<int> onTap;
  final bool extended;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(border: BorderDirectional(end: BorderSide(color: AppColors.border))),
      child: NavigationRail(
        selectedIndex: currentIndex,
        onDestinationSelected: (i) {
          AppHaptics.select();
          onTap(i);
        },
        extended: extended,
        labelType: extended ? NavigationRailLabelType.none : NavigationRailLabelType.all,
        minExtendedWidth: 200,
        groupAlignment: -0.85,
        leading: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.lg),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: AppColors.brandContainer, borderRadius: BorderRadius.circular(AppRadius.sm)),
            child: const Icon(Icons.badge_rounded, color: AppColors.brand),
          ),
        ),
        destinations: [
          for (final d in kMainDestinations)
            NavigationRailDestination(icon: Icon(d.icon), selectedIcon: Icon(d.activeIcon), label: Text(d.label)),
        ],
      ),
    );
  }
}
