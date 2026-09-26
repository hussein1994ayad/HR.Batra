import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/constants.dart';
import '../../../../core/logic/loan_rules.dart';
import '../../../../core/models/models.dart';
import '../../../../core/utils/arabic_format.dart';
import '../../../shared/ui/ui.dart';
import 'loan_card.dart';

/// يعرض التفاصيل الكاملة للسلفة في نافذة سفلية قابلة للسحب.
Future<void> showLoanDetailsSheet(BuildContext context, LoanRecord record, {required VoidCallback onExport}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.96,
      builder: (_, scrollController) => _LoanDetails(
        record: record,
        scrollController: scrollController,
        onExport: () {
          Navigator.pop(ctx);
          onExport();
        },
      ),
    ),
  );
}

class _LoanDetails extends StatelessWidget {
  const _LoanDetails({required this.record, required this.scrollController, required this.onExport});

  final LoanRecord record;
  final ScrollController scrollController;
  final VoidCallback onExport;

  static const _title = TextStyle(fontFamily: 'Cairo', fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary);

  @override
  Widget build(BuildContext context) {
    final loan = record.loan;
    final progress = loanProgress(loan);
    final paidCount = loan.installments.where((i) => i.isPaid).length;
    final salary = loan.employeeSalary ?? 0;
    final pledge = loan.pledgeUrl ?? '';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        border: Border.all(color: AppColors.brand.withValues(alpha: 0.3), width: 1.5),
        boxShadow: [BoxShadow(color: AppColors.brand.withValues(alpha: 0.15), blurRadius: 30, spreadRadius: 2)],
      ),
      child: ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          Center(
            child: Container(
              width: 48,
              height: 5,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: AppColors.borderStrong, borderRadius: BorderRadius.circular(10)),
            ),
          ),
          Row(
            children: [
              EmployeeAvatar(url: record.avatarUrl, radius: 28),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      loan.employeeName ?? 'موظف غير معروف',
                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${record.branchName} • ${record.departmentName}',
                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, color: AppColors.textMuted),
                    ),
                    if (salary > 0)
                      Text(
                        'الراتب الشهري: ${AppConstants.formatMoney(salary)}',
                        style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, color: AppColors.brand, fontWeight: FontWeight.w600),
                      ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: onExport,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: AppColors.textPrimary,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                icon: const Icon(Icons.file_download_rounded, size: 18),
                label: const Text('Excel', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _Panel(
            child: Column(
              children: [
                Row(
                  children: [
                    _KpiBox('أصل السلفة', AppConstants.formatMoney(loan.amount), AppColors.textPrimary, Icons.monetization_on_rounded),
                    const SizedBox(width: 10),
                    _KpiBox('المبلغ المدفوع', AppConstants.formatMoney(loan.paidAmount > 0 ? loan.paidAmount : 0),
                        AppColors.success, Icons.check_circle_rounded),
                    const SizedBox(width: 10),
                    _KpiBox('المبلغ المتبقي', AppConstants.formatMoney(loan.remainingAmount), AppColors.danger,
                        Icons.hourglass_top_rounded),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'نسبة السداد: ${(progress * 100).toStringAsFixed(1)}%',
                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'تم تسديد $paidCount من ${loan.installmentCount} أقساط',
                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, color: AppColors.brand, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    backgroundColor: AppColors.border,
                    valueColor: AlwaysStoppedAnimation<Color>(progress >= 1.0 ? AppColors.success : AppColors.brand),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _Panel(
            opacity: 0.03,
            radius: 18,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SheetRow('تاريخ تقديم السلفة', loan.createdAt == null ? '-' : isoDate(loan.createdAt!), Icons.calendar_today_rounded),
                const Divider(color: AppColors.border, height: 16),
                _SheetRow('القسط الشهري المعتمد', '${AppConstants.formatMoney(loan.installmentAmount)} / الشهر', Icons.payments_rounded),
                const Divider(color: AppColors.border, height: 16),
                _SheetRow('مدة السداد', '${loan.installmentCount} أشهر متتالية', Icons.timelapse_rounded),
                const Divider(color: AppColors.border, height: 16),
                _SheetRow('الملاحظات والسبب', record.notes ?? 'لا توجد ملاحظات مسجلة', Icons.notes_rounded),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text(' صورة التعهد الخطي المرفقة بالسلفة', style: _title),
          const SizedBox(height: 10),
          if (pledge.isNotEmpty)
            _PledgePreview(url: pledge, employeeName: loan.employeeName ?? '')
          else
            const _Panel(
              radius: 14,
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: AppColors.textDisabled, size: 20),
                  SizedBox(width: 10),
                  Text('لم يتم إرفاق صورة تعهد خطي مع هذا الطلب.', style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: AppColors.textMuted)),
                ],
              ),
            ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(' جدول الأقساط والتسديدات الشهرية', style: _title),
              Text(
                '${loan.installments.length} أقساط',
                style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, color: AppColors.brand, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (loan.installments.isEmpty)
            const _Panel(
              opacity: 0.03,
              radius: 14,
              child: Center(
                child: Text('لم يتم توليد أقساط لهذه السلفة بعد.', style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: AppColors.textMuted)),
              ),
            )
          else
            for (final (i, inst) in loan.installments.indexed) ...[
              _InstallmentTile(index: i, installment: inst),
              const SizedBox(height: 8),
            ],
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.opacity = 0.04, this.radius = 20});

  final Widget child;
  final double opacity;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.textPrimary.withValues(alpha: opacity),
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: AppColors.border),
        ),
        child: child,
      );
}

class _KpiBox extends StatelessWidget {
  const _KpiBox(this.title, this.value, this.color, this.icon);

  final String title;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.textPrimary.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 6),
            Text(title, style: const TextStyle(fontFamily: 'Cairo', fontSize: 10, color: AppColors.textMuted)),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value, style: TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold, color: color)),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetRow extends StatelessWidget {
  const _SheetRow(this.title, this.value, this.icon);

  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.brand),
        const SizedBox(width: 10),
        Text('$title: ', style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
        Expanded(
          child: Text(value, style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}

class _PledgePreview extends StatelessWidget {
  const _PledgePreview({required this.url, required this.employeeName});

  final String url;
  final String employeeName;

  Future<void> _openExternal(BuildContext context) async {
    final uri = Uri.tryParse(url);
    final ok = uri != null && await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر فتح صورة التعهد', style: TextStyle(fontFamily: 'Cairo'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.textPrimary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.brandStrong.withValues(alpha: 0.3)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          GestureDetector(
            onTap: () => showFullScreenImage(context, url, 'تعهد سلفة: $employeeName'),
            child: Container(
              height: 180,
              width: double.infinity,
              color: AppColors.shadow,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Image.network(
                    url,
                    width: double.infinity,
                    height: 180,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        const Center(child: Icon(Icons.broken_image_rounded, color: AppColors.textDisabled, size: 48)),
                    loadingBuilder: (_, child, progress) =>
                        progress == null ? child : const Padding(padding: EdgeInsets.all(AppSpace.page), child: SkeletonList()),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: AppColors.shadow, borderRadius: BorderRadius.circular(20)),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.zoom_in_rounded, color: AppColors.textPrimary, size: 16),
                        SizedBox(width: 6),
                        Text('انقر لتكبير صورة التعهد', style: TextStyle(fontFamily: 'Cairo', fontSize: 11, color: AppColors.textPrimary)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _openExternal(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brandStrong,
                  foregroundColor: AppColors.textPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.download_rounded, size: 18),
                label: const Text('تحميل وفتح التعهد الخطي',
                    style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InstallmentTile extends StatelessWidget {
  const _InstallmentTile({required this.index, required this.installment});

  final int index;
  final LoanInstallment installment;

  @override
  Widget build(BuildContext context) {
    final paid = installment.isPaid;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: paid ? AppColors.success.withValues(alpha: 0.08) : AppColors.textPrimary.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: paid ? AppColors.success.withValues(alpha: 0.3) : AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: paid ? AppColors.success : AppColors.border, shape: BoxShape.circle),
            child: Text('${index + 1}',
                style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textPrimary)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'تاريخ الاستحقاق: ${isoDate(installment.dueDate)}',
                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
                if (paid && installment.paidAt != null)
                  Text(
                    'تم التسديد بتاريخ: ${isoDate(installment.paidAt!)}${installment.isCash ? ' (نقداً)' : ''}',
                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 10, color: AppColors.success),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                AppConstants.formatMoney(installment.amount),
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: paid ? AppColors.success : AppColors.textPrimary,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                margin: const EdgeInsets.only(top: 2),
                decoration: BoxDecoration(
                  color: (paid ? AppColors.success : AppColors.warning).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  paid ? 'مسدد' : 'متبقي ⏳',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: paid ? AppColors.success : AppColors.warning,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// صورة بملء الشاشة مع تكبير وتصغير.
Future<void> showFullScreenImage(BuildContext context, String imageUrl, String caption) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      backgroundColor: AppColors.onStatus,
      insetPadding: EdgeInsets.zero,
      child: Stack(
        children: [
          InteractiveViewer(
            boundaryMargin: const EdgeInsets.all(20),
            minScale: 0.5,
            maxScale: 4.0,
            child: Center(
              child: Image.network(
                imageUrl,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Center(
                  child: Text('تعذر تحميل الصورة', style: TextStyle(color: AppColors.textPrimary, fontFamily: 'Cairo')),
                ),
              ),
            ),
          ),
          Positioned(
            top: 40,
            right: 20,
            child: IconButton(
              icon: const Icon(Icons.close_rounded, color: AppColors.textPrimary, size: 30),
              onPressed: () => Navigator.pop(dialogContext),
            ),
          ),
          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.onStatus,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.borderStrong),
                ),
                child: Text(caption,
                    style: const TextStyle(fontFamily: 'Cairo', color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
