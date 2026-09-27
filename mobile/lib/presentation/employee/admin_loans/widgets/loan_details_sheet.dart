import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/logic/loan_rules.dart';
import '../../../../core/models/models.dart';
import '../../../../core/services/storage_links.dart';
import '../../../shared/ui/ui.dart';
import 'loan_card.dart';

/// التفاصيل الكاملة للسلفة في نافذة سفلية قابلة للسحب.
Future<void> showLoanDetailsSheet(BuildContext context, LoanRecord record, {required VoidCallback onExport}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      expand: false,
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

  @override
  Widget build(BuildContext context) {
    final loan = record.loan;
    final progress = loanProgress(loan);
    final paidCount = loan.installments.where((i) => i.isPaid).length;
    final salary = loan.employeeSalary ?? 0;
    final pledge = loan.pledgeUrl ?? '';
    final badge = loanBadge(loan);
    final name = loan.employeeName ?? 'موظف';

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(AppSpace.xl, 0, AppSpace.xl, AppSpace.x3),
      children: [
        Row(
          children: [
            EmployeeAvatar(url: record.avatarUrl, radius: 28, name: name),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: AppText.title),
                  Text('${record.branchName} · ${record.departmentName}', style: AppText.caption),
                  if (salary > 0) Text('الراتب ${Fmt.iqd(salary)}', style: AppText.caption.copyWith(color: AppColors.brand)),
                ],
              ),
            ),
            StatusBadge(badge.label, tone: badge.tone, dot: true),
          ],
        ),
        const SizedBox(height: AppSpace.lg),
        ResponsiveGrid(
          minItemWidth: 110,
          spacing: AppSpace.sm,
          children: [
            KpiTile(label: 'أصل السلفة', value: loan.amount, format: Fmt.iqd, tone: AppTone.neutral),
            KpiTile(label: 'المدفوع', value: loan.paidAmount > 0 ? loan.paidAmount : 0, format: Fmt.iqd, tone: AppTone.success),
            KpiTile(label: 'المتبقي', value: loan.remainingAmount, format: Fmt.iqd, tone: AppTone.danger),
          ],
        ),
        const SizedBox(height: AppSpace.md),
        AppProgressBar(value: progress, tone: progress >= 1 ? AppTone.success : AppTone.brand),
        const SizedBox(height: AppSpace.xs),
        Text('سُدّد $paidCount من ${loan.installmentCount} أقساط · ${(progress * 100).round()}%', style: AppText.caption),
        const SizedBox(height: AppSpace.lg),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.sm),
          child: Column(
            children: [
              KeyValueRow('تاريخ الطلب', loan.createdAt == null ? '—' : Fmt.date(loan.createdAt, withYear: true), icon: Icons.event_rounded),
              KeyValueRow('القسط الشهري', Fmt.iqd(loan.installmentAmount), icon: Icons.payments_rounded),
              KeyValueRow('مدة السداد', Fmt.monthCount(loan.installmentCount), icon: Icons.timelapse_rounded),
              KeyValueRow('ملاحظات', record.notes ?? '—', icon: Icons.notes_rounded),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.md),
        AppButton(label: 'تصدير كشف Excel', icon: Icons.file_download_rounded, variant: AppButtonVariant.success, expand: true, onPressed: onExport),
        const SectionHeader('التعهد الخطي'),
        if (pledge.isNotEmpty)
          _PledgePreview(url: pledge, employeeName: name)
        else
          const AppCard(child: Text('لم يُرفق تعهد مع هذه السلفة.', style: AppText.bodySm)),
        SectionHeader('جدول الأقساط (${loan.installments.length})'),
        if (loan.installments.isEmpty)
          const AppCard(child: Text('لم تتولّد أقساط لهذه السلفة بعد.', style: AppText.bodySm))
        else
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
            child: Column(
              children: [
                for (final (i, inst) in loan.installments.indexed) _InstallmentTile(index: i, installment: inst),
              ],
            ),
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
    if (!ok && context.mounted) AppSnack.error(context, 'تعذّر فتح صورة التعهد');
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            label: 'تكبير صورة التعهد',
            child: InkWell(
              onTap: () => showFullScreenImage(context, url, 'تعهد سلفة: $employeeName'),
              child: SizedBox(
                height: 180,
                child: SignedNetworkImage(
                  url,
                  fit: BoxFit.cover,
                  cacheWidth: 900,
                  errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image_rounded, color: AppColors.textDisabled, size: 40)),
                  loadingBuilder: (_, child, progress) => progress == null ? child : const Skeleton(height: 180, radius: 0),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpace.sm),
            child: AppButton.ghost(label: 'فتح أو تنزيل التعهد', icon: Icons.open_in_new_rounded, onPressed: () => _openExternal(context)),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: paid ? AppColors.successContainer : AppColors.surface2, shape: BoxShape.circle),
            child: Text('${index + 1}', style: AppText.caption.copyWith(color: paid ? AppColors.success : AppColors.textSecondary, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(Fmt.date(installment.dueDate, withYear: true), style: AppText.bodySm.copyWith(color: AppColors.textPrimary)),
                if (paid && installment.paidAt != null)
                  Text('سُدّد ${Fmt.date(installment.paidAt, withYear: true)}${installment.isCash ? ' نقداً' : ''}', style: AppText.caption.copyWith(color: AppColors.success)),
              ],
            ),
          ),
          Text(Fmt.iqd(installment.amount), style: AppText.bodySm.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
          const SizedBox(width: AppSpace.sm),
          paid ? const StatusBadge('مسدد', tone: AppTone.success) : const StatusBadge('متبقي', tone: AppTone.warning),
        ],
      ),
    );
  }
}

/// صورة بملء الشاشة مع تكبير وتصغير.
Future<void> showFullScreenImage(BuildContext context, String imageUrl, String caption) {
  return showDialog<void>(
    context: context,
    barrierColor: AppColors.scrim,
    builder: (dialogContext) => Dialog.fullscreen(
      backgroundColor: AppColors.bg,
      child: Stack(
        children: [
          InteractiveViewer(
            minScale: 0.5,
            maxScale: 4.0,
            child: Center(
              child: SignedNetworkImage(
                imageUrl,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Center(child: Text('تعذّر تحميل الصورة', style: AppText.body)),
              ),
            ),
          ),
          SafeArea(
            child: Row(
              children: [
                IconButton(tooltip: 'إغلاق', icon: const Icon(Icons.close_rounded, size: 28), onPressed: () => Navigator.pop(dialogContext)),
                Expanded(child: Text(caption, style: AppText.subtitle, overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
