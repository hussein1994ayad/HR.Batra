import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import 'glass_container.dart';

/// بطاقة حالة فارغة بأيقونة ونص في منتصف المساحة.
class EmptyState extends StatelessWidget {
  const EmptyState(
    this.text, {
    super.key,
    this.icon = Icons.verified_rounded,
    this.iconColor = AppTheme.successGreen,
  });

  final String text;
  final IconData icon;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GlassContainer(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        margin: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: iconColor, size: 54),
            const SizedBox(height: 16),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Colors.white70, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
            ),
          ],
        ),
      ),
    );
  }
}
