// =========================================================================
// HR Pro - bottom navigation (Material 3 NavigationBar)
// =========================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_theme.dart';

class PremiumBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const PremiumBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  static const _items = [
    (icon: Icons.home_outlined, selected: Icons.home_rounded, label: 'الرئيسية'),
    (icon: Icons.fingerprint_rounded, selected: Icons.fingerprint_rounded, label: 'الدوام'),
    (icon: Icons.event_note_outlined, selected: Icons.event_note_rounded, label: 'الإجازات'),
    (icon: Icons.account_balance_wallet_outlined, selected: Icons.account_balance_wallet_rounded, label: 'السلف'),
    (icon: Icons.settings_outlined, selected: Icons.settings_rounded, label: 'الإعدادات'),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
        ),
      ),
      child: NavigationBar(
        selectedIndex: currentIndex,
        animationDuration: const Duration(milliseconds: 350),
        onDestinationSelected: (index) {
          if (index != currentIndex) HapticFeedback.selectionClick();
          onTap(index);
        },
        destinations: [
          for (final item in _items)
            NavigationDestination(
              icon: Icon(item.icon),
              selectedIcon: Icon(item.selected),
              label: item.label,
              tooltip: '',
            ),
        ],
      ),
    );
  }
}
