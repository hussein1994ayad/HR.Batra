import 'package:flutter/material.dart';

import '../../../core/design/design.dart';
import '../ui/app_states.dart';

/// حالة فارغة مختصرة (نص فقط) — تغليف لـ EmptyView.
class EmptyState extends StatelessWidget {
  const EmptyState(this.text, {super.key, this.icon = Icons.verified_rounded, this.tone = AppTone.success});

  final String text;
  final IconData icon;
  final AppTone tone;

  @override
  Widget build(BuildContext context) => EmptyView(title: text, icon: icon, tone: tone, compact: true);
}
