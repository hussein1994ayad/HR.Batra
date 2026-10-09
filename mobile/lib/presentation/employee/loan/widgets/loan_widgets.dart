// أجزاء عرض شاشة السلف: كارت التعهد الموقّع وكارت السلفة بالسجل (مع جدول الأقساط).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/models/models.dart';
import '../../../../core/services/storage_links.dart';
import '../../../shared/ui/ui.dart';

/// صورة التعهد الخطي الموقّع (إلزامية قبل الإرسال).
class LoanPledgeCard extends StatelessWidget {
  const LoanPledgeCard({super.key, required this.file, required this.onPick});

  final File? file;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final done = file != null;
    return AppCard(
      tone: done ? AppTone.success : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ToneIcon(done ? Icons.task_alt_rounded : Icons.draw_rounded, tone: done ? AppTone.success : AppTone.warning),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('التعهد الخطي الموقّع', style: AppText.subtitle),
                    Text(done ? 'تم إرفاق الصورة' : 'مطلوب — وقّع التعهد وصوّره بوضوح', style: AppText.caption),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          if (done)
            Row(
              children: [
                ClipRRect(
                  borderRadius: AppRadius.control,
                  child: Image.file(file!, width: 64, height: 64, fit: BoxFit.cover, cacheWidth: 192),
                ),
                const SizedBox(width: AppSpace.md),
                Expanded(child: AppButton.secondary(label: 'إعادة التصوير', icon: Icons.camera_alt_rounded, size: AppButtonSize.small, onPressed: onPick)),
              ],
            )
          else
            AppButton.secondary(label: 'تصوير التعهد', icon: Icons.camera_alt_rounded, expand: true, onPressed: onPick),
        ],
      ),
    );
  }
}

class MyLoanCard extends StatelessWidget {
  const MyLoanCard({super.key, required this.loan, required this.onCancel});
  final LoanModel loan;
  final ValueChanged<LoanModel> onCancel;

  @override
  Widget build(BuildContext context) {
    final amount = loan.amount;
    final remaining = loan.remainingAmount;
    final installmentAmount = loan.installmentAmount;
    final status = loan.status;
    // مرتبة حسب تاريخ الاستحقاق داخل LoanModel
    final installments = loan.installments;
    final paid = amount - remaining;
    final pledge = loan.pledgeUrl;
    final rejection = loan.rejectionReason;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const ToneIcon(Icons.account_balance_wallet_rounded, tone: AppTone.warning),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(Fmt.iqd(amount), style: AppText.titleSm),
                    Text('طُلبت ${Fmt.relative(loan.createdAt)}', style: AppText.caption),
                  ],
                ),
              ),
              StatusBadge.request(status),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          KeyValueRow('القسط الشهري', Fmt.iqd(installmentAmount)),
          KeyValueRow('عدد الأقساط', '${loan.installmentCount}'),
          if (status == 'approved') ...[
            KeyValueRow('المتبقي', Fmt.iqd(remaining), valueColor: AppColors.brand, bold: true),
            const SizedBox(height: AppSpace.xs),
            AppProgressBar(value: amount > 0 ? paid / amount : 0, tone: AppTone.success),
            const SizedBox(height: AppSpace.xs),
            Text('سُدّد ${Fmt.iqd(paid)} من ${Fmt.iqd(amount)}', style: AppText.caption),
          ],
          if (rejection != null && rejection.isNotEmpty) ...[
            const SizedBox(height: AppSpace.sm),
            Text('سبب الرفض: $rejection', style: AppText.bodySm.copyWith(color: AppColors.danger)),
          ],
          if (status == 'approved' && installments.isNotEmpty)
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: Text('جدول الأقساط (${installments.where((i) => i.isPaid).length}/${installments.length} مدفوع)', style: AppText.label),
                children: [
                  for (var i = 0; i < installments.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
                      child: Row(
                        children: [
                          SizedBox(width: 28, child: Text('${i + 1}', style: AppText.caption)),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('قسط رواتب ${Fmt.monthOf(installments[i].payrollMonth)}', style: AppText.bodySm),
                                if (installments[i].originLabel != null)
                                  Text(installments[i].originLabel!, style: AppText.caption.copyWith(color: AppTone.warning.color)),
                              ],
                            ),
                          ),
                          Text(Fmt.iqd(installments[i].amount), style: AppText.bodySm.copyWith(color: AppColors.textPrimary)),
                          const SizedBox(width: AppSpace.sm),
                          installments[i].isPaid
                              ? const StatusBadge('مدفوع', tone: AppTone.success)
                              : const StatusBadge('قادم'),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            children: [
              if (pledge != null && pledge.isNotEmpty)
                AppButton.ghost(
                  label: 'عرض التعهد',
                  icon: Icons.attach_file_rounded,
                  size: AppButtonSize.small,
                  onPressed: () async {
                    final url = Uri.tryParse(await StorageLinks.resolve(pledge));
                    final opened = url != null && await launchUrl(url, mode: LaunchMode.externalApplication).catchError((_) => false);
                    if (!opened && context.mounted) AppSnack.error(context, 'تعذّر فتح التعهد');
                  },
                ),
              if (status == 'pending')
                AppButton.ghost(
                  label: 'إلغاء الطلب',
                  icon: Icons.close_rounded,
                  size: AppButtonSize.small,
                  onPressed: () => onCancel(loan),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
