import 'package:flutter/material.dart';

import '../../../shared/ui/ui.dart';

/// بطاقة طلب: اسم الموظف مع صورة، عنصر في الطرف (شارة أو مبلغ)، التفاصيل، وأزرار القرار.
class RequestCard extends StatelessWidget {
  const RequestCard({
    super.key,
    required this.title,
    required this.tone,
    required this.children,
    this.subtitle,
    this.trailing,
    this.actions,
    this.highlight = false,
  });

  final String title;
  final String? subtitle;
  final AppTone tone;
  final Widget? trailing;
  final List<Widget> children;
  final Widget? actions;

  /// بطاقة بخلفية ملوّنة (للتنبيهات الأمنية).
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: AppCard(
        tone: highlight ? tone : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                AppAvatar(name: title, size: 40, tone: tone),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: AppText.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                      if (subtitle != null) Text(subtitle!, style: AppText.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: AppSpace.sm), trailing!],
              ],
            ),
            const SizedBox(height: AppSpace.md),
            ...children,
            if (actions != null) ...[const SizedBox(height: AppSpace.md), actions!],
          ],
        ),
      ),
    );
  }
}

/// زرا قبول/رفض بعرض متساوٍ. الرفض يطلب تأكيداً.
class DecisionButtons extends StatelessWidget {
  const DecisionButtons({
    super.key,
    required this.onApprove,
    required this.onReject,
    this.approveLabel = 'موافقة',
    this.rejectLabel = 'رفض',
    this.confirmRejectTitle,
    this.busy = false,
  });

  final VoidCallback onApprove;
  final VoidCallback onReject;
  final String approveLabel;
  final String rejectLabel;

  /// إن وُجد: يظهر تأكيد قبل الرفض بهذا العنوان.
  final String? confirmRejectTitle;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: AppButton(
            label: approveLabel,
            icon: Icons.check_rounded,
            variant: AppButtonVariant.success,
            loading: busy,
            onPressed: onApprove,
          ),
        ),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: AppButton.secondary(
            label: rejectLabel,
            icon: Icons.close_rounded,
            onPressed: busy
                ? null
                : () async {
                    if (confirmRejectTitle != null) {
                      final ok = await showAppConfirm(context, title: confirmRejectTitle!, confirmLabel: rejectLabel, destructive: true);
                      if (!ok) return;
                    }
                    onReject();
                  },
          ),
        ),
      ],
    );
  }
}
