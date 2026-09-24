// =========================================================================
// نظام HR Pro v6.0 - شريط التنقل السفلي (Premium Bottom Nav)
// إعادة تصميم: انيميشن أنعم، haptic feedback، ألوان الثيم، تباين أفضل
// وتلميحات (labels) لجميع العناصر بأحجام موحّدة (بدون توسيع مزعج).
// =========================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_theme.dart';

class PremiumBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final void Function(int) onTap;

  const PremiumBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  static const _items = <_NavBarItem>[
    _NavBarItem(icon: Icons.home_outlined, activeIcon: Icons.home_rounded, label: 'الرئيسية'),
    _NavBarItem(icon: Icons.fingerprint, activeIcon: Icons.fingerprint, label: 'الدوام'),
    _NavBarItem(icon: Icons.calendar_today_outlined, activeIcon: Icons.calendar_today_rounded, label: 'الإجازات'),
    _NavBarItem(icon: Icons.monetization_on_outlined, activeIcon: Icons.monetization_on_rounded, label: 'السلف'),
    _NavBarItem(icon: Icons.settings_outlined, activeIcon: Icons.settings_rounded, label: 'الإعدادات'),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(
          AppTheme.space4, 0, AppTheme.space4, AppTheme.space3,
        ),
        padding: const EdgeInsets.symmetric(horizontal: AppTheme.space2, vertical: AppTheme.space2),
        decoration: BoxDecoration(
          color: isDark
              ? AppTheme.darkSurface.withValues(alpha: 0.94)
              : Colors.white.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(AppTheme.radiusXl),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : AppTheme.lightBorder,
          ),
          boxShadow: AppTheme.shadowLg(isDark),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: List.generate(_items.length, (index) {
            final isSelected = index == currentIndex;
            return Expanded(
              child: _NavButton(
                item: _items[index],
                isSelected: isSelected,
                isDark: isDark,
                onTap: () {
                  if (!isSelected) HapticFeedback.selectionClick();
                  onTap(index);
                },
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final _NavBarItem item;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;

  const _NavButton({
    required this.item,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = isDark ? AppTheme.primaryTealLight : AppTheme.primaryTeal;
    final inactiveColor = isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppTheme.motionNormal,
          curve: AppTheme.curveEmphasized,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            color: isSelected ? activeColor.withValues(alpha: 0.12) : Colors.transparent,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSwitcher(
                duration: AppTheme.motionFast,
                transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
                child: Icon(
                  isSelected ? item.activeIcon : item.icon,
                  key: ValueKey(isSelected),
                  color: isSelected ? activeColor : inactiveColor,
                  size: 24,
                ),
              ),
              const SizedBox(height: 4),
              AnimatedDefaultTextStyle(
                duration: AppTheme.motionFast,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 10,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                  color: isSelected ? activeColor : inactiveColor,
                ),
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              AnimatedContainer(
                duration: AppTheme.motionNormal,
                margin: const EdgeInsets.only(top: 4),
                height: 3,
                width: isSelected ? 20 : 0,
                decoration: BoxDecoration(
                  color: activeColor,
                  borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavBarItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;

  const _NavBarItem({required this.icon, required this.activeIcon, required this.label});
}
