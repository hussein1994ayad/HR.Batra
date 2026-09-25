import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../shared/widgets/glass_container.dart';

/// شارة ملونة صغيرة (نوع الطلب أو حالته).
class StatusBadge extends StatelessWidget {
  const StatusBadge(this.text, {super.key, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
    );
  }
}

/// بطاقة طلب: اسم الموظف، عنصر في الطرف (شارة أو مبلغ)، التفاصيل، وأزرار القرار.
class RequestCard extends StatelessWidget {
  const RequestCard({
    super.key,
    required this.title,
    required this.accent,
    required this.children,
    this.trailing,
    this.actions,
    this.opacity = 0.08,
    this.glow = false,
  });

  final String title;
  final Color accent;
  final Widget? trailing;
  final List<Widget> children;
  final Widget? actions;
  final double opacity;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      borderRadius: 20,
      opacity: opacity,
      borderColor: accent.withValues(alpha: glow ? 0.35 : 0.25),
      boxShadow: glow ? [BoxShadow(color: accent.withValues(alpha: 0.12), blurRadius: 10)] : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white, fontFamily: 'Cairo'),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(color: Colors.white10, height: 1),
          ),
          ...children,
          if (actions != null) ...[const SizedBox(height: 16), actions!],
        ],
      ),
    );
  }
}

/// زرا قبول/رفض بعرض متساوٍ.
class DecisionButtons extends StatelessWidget {
  const DecisionButtons({
    super.key,
    required this.onApprove,
    required this.onReject,
    this.approveLabel = 'موافقة',
    this.rejectLabel = 'رفض',
    this.busy = false,
  });

  final VoidCallback onApprove;
  final VoidCallback onReject;
  final String approveLabel;
  final String rejectLabel;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
    const label = TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold);
    return Row(
      children: [
        Expanded(
          child: ElevatedButton(
            onPressed: busy ? null : onApprove,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.successGreen,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: shape,
            ),
            child: Text(approveLabel, style: label),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton(
            onPressed: busy ? null : onReject,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.dangerRed,
              side: const BorderSide(color: AppTheme.dangerRed),
              shape: shape,
            ),
            child: Text(rejectLabel, style: label),
          ),
        ),
      ],
    );
  }
}
