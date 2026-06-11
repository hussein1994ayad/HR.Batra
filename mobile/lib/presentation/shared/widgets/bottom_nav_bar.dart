// =========================================================================
// نظام HR Pro v6.0 - شريط التنقل السفلي الفاخر (Premium Bottom Navigation Bar)
// =========================================================================

import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class PremiumBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;

  const PremiumBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // قائمة العناصر (أيقونات + تسميات)
    final items = [
      _NavBarItem(icon: Icons.home_rounded, label: 'الرئيسية'),
      _NavBarItem(icon: Icons.fingerprint_rounded, label: 'الدوام'),
      _NavBarItem(icon: Icons.calendar_today_rounded, label: 'الإجازات'),
      _NavBarItem(icon: Icons.monetization_on_rounded, label: 'السلف'),
      _NavBarItem(icon: Icons.settings_rounded, label: 'الإعدادات'),
    ];

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        decoration: BoxDecoration(
          color: Colors.transparent,
          boxShadow: [
            BoxShadow(
              color: (isDark ? AppTheme.cyberPurple : AppTheme.primaryTeal).withOpacity(isDark ? 0.2 : 0.08),
              blurRadius: 24,
              spreadRadius: 2,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              decoration: BoxDecoration(
                color: isDark 
                    ? const Color(0xFF0F172A).withOpacity(0.4)
                    : Colors.white.withOpacity(0.5),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: isDark 
                      ? Colors.white.withOpacity(0.12)
                      : Colors.white.withOpacity(0.4),
                  width: 1.2,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: List.generate(items.length, (index) {
                  final isSelected = index == currentIndex;
                  final item = items[index];
                  
                  return GestureDetector(
                    onTap: () => onTap(index),
                    behavior: HitTestBehavior.opaque,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                      padding: EdgeInsets.symmetric(
                        vertical: 10, 
                        horizontal: isSelected ? 16 : 10,
                      ),
                      decoration: isSelected
                          ? BoxDecoration(
                              gradient: AppTheme.cyberGradient,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.neonCyan.withAlpha(100),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                )
                              ],
                            )
                          : const BoxDecoration(
                              color: Colors.transparent,
                            ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            item.icon,
                            color: isSelected 
                                ? Colors.white 
                                : (isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary),
                            size: isSelected ? 22 : 24,
                          ),
                          if (isSelected) ...[
                            const SizedBox(width: 6),
                            Text(
                              item.label,
                              style: const TextStyle(
                                fontSize: 11,
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavBarItem {
  final IconData icon;
  final String label;

  _NavBarItem({required this.icon, required this.label});
}
