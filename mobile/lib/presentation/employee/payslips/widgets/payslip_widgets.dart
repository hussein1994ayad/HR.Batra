// أجزاء عرض كشوف الرواتب: كارت مسير الشهر الحالي وتفاصيل الكشف المعتمد.

import 'package:flutter/material.dart';

import '../../../shared/ui/ui.dart';

/// راتب الشهر الحالي قبل الاعتماد: الأساسي، الإضافات، الخصومات، الأقساط، والمتوقع،
/// مع كل حركة وحالتها (بانتظار قرار الإدارة / محتسبة / معفى منها).
class CurrentPayrollCard extends StatelessWidget {
  const CurrentPayrollCard({super.key, required this.preview});
  final Map<String, dynamic> preview;

  static double _n(Object? v) => (v as num?)?.toDouble() ?? double.tryParse(v?.toString() ?? '') ?? 0;

  static const _labels = {
    'absence': 'غياب',
    'late': 'تأخير',
    'early_leave': 'خروج مبكر',
    'missing_punch': 'بصمة ناقصة',
    'unpaid_leave': 'إجازة بدون راتب',
    'paid_leave': 'إجازة مدفوعة',
    'overtime': 'ساعات إضافية',
    'manual_deduction': 'خصم',
    'bonus': 'مكافأة',
    'adjustment': 'تسوية',
  };

  static String _status(Object? s) => switch (s) {
        'pending' => 'بانتظار القرار',
        'ignored' => 'معفى',
        _ => 'محتسب',
      };

  @override
  Widget build(BuildContext context) {
    final s = Map<String, dynamic>.from((preview['summary'] as Map?) ?? const {});
    final period = Map<String, dynamic>.from((preview['period'] as Map?) ?? const {});
    final events = [for (final e in (preview['events'] as List? ?? const [])) Map<String, dynamic>.from(e as Map)];
    final month = (period['period_month'] ?? '').toString().split('-');
    final m = month.length == 2 ? int.tryParse(month[1]) ?? 1 : 1;
    final y = int.tryParse(month.first) ?? DateTime.now().year;
    final issued = s['slip'] != null;
    final pending = events.where((e) => e['status'] == 'pending' && e['event_type'] != 'missing_punch').length;

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
          KeyValueRow('الراتب الأساسي', Fmt.iqd(_n(s['basic']))),
          if (_n(s['earnings']) > 0) KeyValueRow('مكافآت وإضافي', '+${Fmt.iqd(_n(s['earnings']))}', valueColor: AppColors.success),
          if (_n(s['deductions']) > 0) KeyValueRow('غياب وتأخير وخصومات', '-${Fmt.iqd(_n(s['deductions']))}', valueColor: AppColors.danger),
          if (_n(s['loans']) > 0) KeyValueRow('قسط السلفة', '-${Fmt.iqd(_n(s['loans']))}', valueColor: AppColors.danger),
          const Divider(height: AppSpace.xl),
          KeyValueRow('الصافي المتوقع', Fmt.iqd(_n(s['net'])), valueColor: AppColors.brand, bold: true),
          if (events.isNotEmpty) ...[
            const SizedBox(height: AppSpace.md),
            Text('الحركات', style: AppText.label.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: AppSpace.xs),
            for (final e in events)
              KeyValueRow(
                '${_labels[e['event_type']] ?? e['event_type']}'
                '${_n(e['minutes']) > 0 ? ' ${_n(e['minutes']).round()} د' : ''}'
                ' · ${Fmt.date(DateTime.tryParse(e['event_date']?.toString() ?? ''))} · ${_status(e['status'])}',
                _n(e['amount']) <= 0 ? '—' : '${_n(e['direction']) > 0 ? '+' : '-'}${Fmt.iqd(_n(e['amount']))}',
                valueColor: e['status'] == 'ignored'
                    ? AppColors.textMuted
                    : _n(e['direction']) > 0
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

  final Map<String, dynamic> slip;
  final List<Map<String, dynamic>>? details;
  final bool exporting;
  final VoidCallback onExport;

  static double _n(Object? v) => (v as num?)?.toDouble() ?? 0.0;

  @override
  Widget build(BuildContext context) {
    final basic = _n(slip['basic_salary']);
    final allowances = _n(slip['allowances']);
    final deductions = _n(slip['deductions']);
    final loans = _n(slip['loans_deduction']);
    final net = _n(slip['net_salary']);
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
              '${item['reason'] ?? ''} · ${Fmt.date(DateTime.tryParse(item['issue_date']?.toString() ?? ''))}',
              '${item['type'] == 'bonus' ? '+' : '-'}${Fmt.iqd(_n(item['amount']))}',
              valueColor: item['type'] == 'bonus' ? AppColors.success : AppColors.danger,
            ),
        const SizedBox(height: AppSpace.xl),
        AppButton(label: 'تحميل الكشف PDF', icon: Icons.picture_as_pdf_rounded, expand: true, loading: exporting, onPressed: onExport),
      ],
    );
  }
}
