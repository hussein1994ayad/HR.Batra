// =========================================================================
// HR Pro — خلفية الصفحة (للتوافق مع الشاشات القديمة)
// =========================================================================
// خلفية داكنة هادئة موحّدة مع SafeArea. بدون دوائر ملوّنة متوهجة.
// =========================================================================

import 'package:flutter/material.dart';

import '../../../core/design/design.dart';

class GlassBackground extends StatelessWidget {
  final Widget child;

  const GlassBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(bottom: false, child: child),
    );
  }
}
