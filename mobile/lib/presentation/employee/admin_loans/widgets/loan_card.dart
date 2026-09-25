import 'package:flutter/material.dart';

import '../../../../core/constants/constants.dart';
import '../../../../core/logic/loan_rules.dart';
import '../../../../core/models/models.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../shared/widgets/glass_container.dart';

/// شارة حالة السلفة (معلقة، مسددة، مرفوضة، نشطة).
({String label, Color color}) loanBadge(LoanModel loan) {
  if (loan.isPending) return (label: 'طلب معلق ⏳', color: Colors.amber);
  if (loan.isRejected) return (label: 'مرفوضة ❌', color: AppTheme.dangerRed);
  if (loan.remainingAmount <= 0) return (label: 'مسددة بالكامل 🏁', color: AppTheme.successGreen);
  return (label: 'سلفة نشطة 💸', color: AppTheme.neonCyan);
}

/// صورة الموظف أو أيقونة بديلة.
class EmployeeAvatar extends StatelessWidget {
  const EmployeeAvatar({super.key, this.url, this.radius = 20});

  final String? url;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final hasUrl = url != null && url!.isNotEmpty;
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppTheme.primaryTeal.withValues(alpha: 0.2),
      backgroundImage: hasUrl ? NetworkImage(url!) : null,
      child: hasUrl ? null : Icon(Icons.person_rounded, color: AppTheme.neonCyan, size: radius),
    );
  }
}

class LoanCard extends StatelessWidget {
  const LoanCard({super.key, required this.record, required this.onOpen, required this.onExport});

  final LoanRecord record;
  final VoidCallback onOpen;
  final VoidCallback onExport;

  Widget _amount(String label, double value, Color color, CrossAxisAlignment align) => Column(
        crossAxisAlignment: align,
        children: [
          Text(label, style: const TextStyle(fontFamily: 'Cairo', fontSize: 10, color: Colors.white60)),
          Text(
            AppConstants.formatMoney(value),
            style: TextStyle(fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final loan = record.loan;
    final progress = loanProgress(loan);
    final paidCount = loan.installments.where((i) => i.isPaid).length;
    final badge = loanBadge(loan);

    return GlassContainer(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      borderRadius: 18,
      opacity: 0.06,
      borderColor: Colors.white12,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                EmployeeAvatar(url: record.avatarUrl),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        loan.employeeName ?? 'موظف غير معروف',
                        style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                      ),
                      Text(record.branchName, style: const TextStyle(fontFamily: 'Cairo', fontSize: 10, color: Colors.white60)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: badge.color.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
                  child: Text(
                    badge.label,
                    style: TextStyle(fontFamily: 'Cairo', fontSize: 10, fontWeight: FontWeight.bold, color: badge.color),
                  ),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Divider(color: Colors.white10, height: 1),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _amount('المبلغ الكلي', loan.amount, Colors.white, CrossAxisAlignment.start),
                _amount('المسدد', loan.paidAmount > 0 ? loan.paidAmount : 0, AppTheme.successGreen, CrossAxisAlignment.center),
                _amount('المتبقي بذمته', loan.remainingAmount, const Color(0xFFF87171), CrossAxisAlignment.end),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 6,
                          backgroundColor: Colors.white10,
                          valueColor: AlwaysStoppedAnimation<Color>(progress >= 1.0 ? AppTheme.successGreen : AppTheme.neonCyan),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'الأقساط المسددة: $paidCount من ${loan.installmentCount} أقساط (${(progress * 100).toStringAsFixed(0)}%)',
                        style: const TextStyle(fontFamily: 'Cairo', fontSize: 10, color: Colors.white60),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                InkWell(
                  onTap: onExport,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.successGreen.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.successGreen.withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.file_download_outlined, color: AppTheme.successGreen, size: 15),
                        SizedBox(width: 4),
                        Text(
                          'Excel',
                          style: TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.successGreen),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
