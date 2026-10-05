import 'package:flutter/material.dart';

import '../../../../core/logic/loan_rules.dart';
import '../../../../core/models/models.dart';
import '../../../shared/ui/ui.dart';

/// شارة حالة السلفة (معلقة، مسددة، مرفوضة، نشطة).
({String label, AppTone tone}) loanBadge(LoanModel loan) {
  if (loan.isPending) return (label: 'طلب معلق', tone: AppTone.warning);
  if (loan.isRejected) return (label: 'مرفوضة', tone: AppTone.danger);
  if (loan.remainingAmount <= 0) return (label: 'مسددة', tone: AppTone.success);
  return (label: 'نشطة', tone: AppTone.brand);
}

/// صورة الموظف (أو الحروف الأولى).
class EmployeeAvatar extends StatelessWidget {
  const EmployeeAvatar({super.key, this.url, this.radius = 20, this.name = ''});

  final String? url;
  final double radius;
  final String name;

  @override
  Widget build(BuildContext context) => AppAvatar(name: name, url: url, size: radius * 2);
}

class LoanCard extends StatelessWidget {
  const LoanCard({super.key, required this.record, required this.onOpen, required this.onExport});

  final LoanRecord record;
  final VoidCallback onOpen;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final loan = record.loan;
    final progress = loanProgress(loan);
    final paidCount = loan.installments.where((i) => i.isPaid).length;
    final badge = loanBadge(loan);
    final name = loan.employeeName ?? 'موظف';

    return AppCard(
      onTap: onOpen,
      semanticLabel: 'سلفة $name، ${badge.label}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              EmployeeAvatar(url: record.avatarUrl, name: name),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: AppText.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(record.branchName, style: AppText.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              StatusBadge(badge.label, tone: badge.tone, dot: true),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          Row(
            children: [
              Expanded(child: _Amount('المبلغ', loan.amount, AppColors.textPrimary)),
              Expanded(child: _Amount('المسدد', loan.paidAmount > 0 ? loan.paidAmount : 0, AppColors.success)),
              Expanded(child: _Amount('المتبقي', loan.remainingAmount, loan.remainingAmount > 0 ? AppColors.danger : AppColors.textMuted)),
            ],
          ),
          if (!loan.isPending && !loan.isRejected) ...[
            const SizedBox(height: AppSpace.md),
            AppProgressBar(value: progress, tone: progress >= 1 ? AppTone.success : AppTone.brand, height: 6),
            const SizedBox(height: AppSpace.xs),
            Row(
              children: [
                Expanded(child: Text('$paidCount من ${loan.installmentCount} أقساط · ${(progress * 100).round()}%', style: AppText.caption)),
                TextButton.icon(
                  onPressed: onExport,
                  style: TextButton.styleFrom(foregroundColor: AppColors.success, minimumSize: const Size(48, 40)),
                  icon: const Icon(Icons.file_download_outlined, size: 18),
                  label: const Text('Excel'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Amount extends StatelessWidget {
  const _Amount(this.label, this.value, this.color);
  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppText.caption),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(Fmt.iqd(value), style: AppText.subtitle.copyWith(color: color, fontFeatures: const [FontFeature.tabularFigures()])),
          ),
        ],
      );
}
