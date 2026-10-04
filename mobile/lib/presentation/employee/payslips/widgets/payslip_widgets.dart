// أجزاء عرض كشوف الرواتب: كارت مسير الشهر الحالي وتفاصيل الكشف المعتمد.

import 'package:flutter/material.dart';

import '../../../../core/models/models.dart';
import '../../../shared/ui/ui.dart';

/// راتب الشهر الحالي قبل الاعتماد: الأساسي، الإضافات، الخصومات، الأقساط، والمتوقع،
/// مع كل حركة وحالتها (بانتظار قرار الإدارة / محتسبة / معفى منها).
class CurrentPayrollCard extends StatelessWidget {
  const CurrentPayrollCard({super.key, required this.preview});
  final PayrollPreview preview;

  static String _status(Object? s) => switch (s) {
        'pending' => 'بانتظار القرار',
        'ignored' => 'معفى',
        _ => 'محتسب',
      };

  @override
  Widget build(BuildContext context) {
    final events = preview.events;
    final month = preview.periodMonth.split('-');
    final m = month.length == 2 ? int.tryParse(month[1]) ?? 1 : 1;
    final y = int.tryParse(month.first) ?? DateTime.now().year;
    final issued = preview.issued;
    final pending = events.where((e) => e.status == 'pending' && e.eventType != 'missing_punch').length;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const ToneIcon(Icons.pending_actions_rounded, tone: AppTone.info),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('راتب ${Fmt.monthNumber(m, y)}', style: AppText.subtitle),
                    Text(issued ? 'اعتُمد الكشف' : 'قبل الاعتماد · قد يتغير حتى نهاية المسير', style: AppText.caption),
                  ],
                ),
              ),
              if (pending > 0) StatusBadge('$pending بانتظار قرار', tone: AppTone.warning),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          KeyValueRow('الراتب الأساسي', Fmt.iqd(preview.basic)),
          if (preview.earnings > 0) KeyValueRow('مكافآت وإضافي', '+${Fmt.iqd(preview.earnings)}', valueColor: AppColors.success),
          if (preview.deductions > 0) KeyValueRow('غياب وتأخير وخصومات', '-${Fmt.iqd(preview.deductions)}', valueColor: AppColors.danger),
          if (preview.loans > 0) KeyValueRow('قسط السلفة', '-${Fmt.iqd(preview.loans)}', valueColor: AppColors.danger),
          const Divider(height: AppSpace.xl),
          KeyValueRow('الصافي المتوقع', Fmt.iqd(preview.net), valueColor: AppColors.brand, bold: true),
          if (events.isNotEmpty) ...[
            const SizedBox(height: AppSpace.md),
            Text('الحركات', style: AppText.label.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: AppSpace.xs),
            for (final e in events)
              KeyValueRow(
                '${kPayrollEventLabels[e.eventType] ?? e.eventType}'
                '${e.minutes > 0 ? ' ${e.minutes.round()} د' : ''}'
                ' · ${Fmt.date(DateTime.tryParse(e.eventDate ?? ''))} · ${_status(e.status)}',
                e.amount <= 0 ? '—' : '${e.direction > 0 ? '+' : '-'}${Fmt.iqd(e.amount)}',
                valueColor: e.status == 'ignored'
                    ? AppColors.textMuted
                    : e.direction > 0
                        ? AppColors.success
                        : AppColors.danger,
              ),
          ],
        ],
      ),
    );
  }
}

class SlipDetailsView extends StatelessWidget {
  const SlipDetailsView({super.key, required this.slip, required this.details, required this.exporting, required this.onExport});

  final SalarySlipModel slip;
  final List<PayslipDetail>? details;
  final bool exporting;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final basic = slip.basicSalary;
    final allowances = slip.allowances;
    final deductions = slip.deductions;
    final loans = slip.loansDeduction;
    final net = slip.netSalary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KeyValueRow('الراتب الأساسي', Fmt.iqd(basic)),
        if (allowances > 0) KeyValueRow('مكافآت وزيادات', '+${Fmt.iqd(allowances)}', valueColor: AppColors.success),
        if (deductions > 0) KeyValueRow('غيابات وخصومات', '-${Fmt.iqd(deductions)}', valueColor: AppColors.danger),
        if (loans > 0) KeyValueRow('قسط السلفة', '-${Fmt.iqd(loans)}', valueColor: AppColors.danger),
        const Divider(height: AppSpace.xl),
        KeyValueRow('الصافي', Fmt.iqd(net), valueColor: AppColors.brand, bold: true),
        const SizedBox(height: AppSpace.md),
        Text('تفاصيل المكافآت والخصومات', style: AppText.label.copyWith(color: AppColors.textSecondary)),
        const SizedBox(height: AppSpace.sm),
        if (details == null)
          const Skeleton(height: 40)
        else if (details!.isEmpty)
          const Text('لا توجد مكافآت أو خصومات استثنائية بهذه الدورة.', style: AppText.caption)
        else
          for (final item in details!)
            KeyValueRow(
              '${item.reason ?? ''} · ${Fmt.date(DateTime.tryParse(item.issueDate ?? ''))}',
              '${item.isBonus ? '+' : '-'}${Fmt.iqd(item.amount ?? 0)}',
              valueColor: item.isBonus ? AppColors.success : AppColors.danger,
            ),
        const SizedBox(height: AppSpace.xl),
        AppButton(label: 'تحميل الكشف PDF', icon: Icons.picture_as_pdf_rounded, expand: true, loading: exporting, onPressed: onExport),
      ],
    );
  }
}
