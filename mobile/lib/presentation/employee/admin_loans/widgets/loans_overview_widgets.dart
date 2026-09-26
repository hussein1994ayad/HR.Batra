import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/logic/loan_rules.dart';
import '../../../../core/models/models.dart';
import '../../../../core/services/excel_export_service.dart';
import '../../../shared/ui/ui.dart';

/// البحث بالاسم، فلتر الفرع، ورقاقات الحالة.
class LoansFilterBar extends StatelessWidget {
  const LoansFilterBar({
    super.key,
    required this.searchController,
    required this.query,
    required this.branches,
    required this.branchId,
    required this.status,
    required this.onQueryChanged,
    required this.onBranchChanged,
    required this.onStatusChanged,
  });

  final TextEditingController searchController;
  final String query;
  final List<BranchModel> branches;
  final String branchId;
  final LoanStatusFilter status;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String> onBranchChanged;
  final ValueChanged<LoanStatusFilter> onStatusChanged;

  /// ارتفاع الشريط عند وضعه أسفل AppBar.
  static const double height = 164;

  @override
  Widget build(BuildContext context) {
    final branchName = branches.where((b) => b.id == branchId).firstOrNull?.name;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.page),
          child: ContentWidth(
            child: TextField(
              controller: searchController,
              onChanged: onQueryChanged,
              textInputAction: TextInputAction.search,
              style: AppText.body,
              decoration: InputDecoration(
                hintText: 'ابحث باسم الموظف',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'مسح البحث',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          searchController.clear();
                          onQueryChanged('');
                        },
                      ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        AppFilterBar(
          children: [
            AppFilterPill(
              icon: Icons.store_rounded,
              label: branchName ?? 'كل الفروع',
              active: branchId != 'all',
              onTap: () async {
                final id = await showAppOptions(
                  context,
                  title: 'الفرع',
                  current: branchId,
                  options: [('all', 'كل الفروع'), for (final b in branches) (b.id, b.name)],
                );
                if (id != null) onBranchChanged(id);
              },
            ),
          ],
        ),
        const SizedBox(height: AppSpace.xs),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.page),
          child: AppChoiceChips<LoanStatusFilter>(
            scrollable: true,
            value: status,
            onChanged: onStatusChanged,
            options: const [
              (LoanStatusFilter.all, 'الكل', null),
              (LoanStatusFilter.active, 'نشطة', null),
              (LoanStatusFilter.pending, 'طلبات معلقة', null),
              (LoanStatusFilter.completed, 'مسددة', null),
            ],
          ),
        ),
      ],
    );
  }
}

/// مؤشرات السلف: الممنوح، المسدد، المتبقي، وعدد السلف النشطة.
class LoansKpiPanel extends StatelessWidget {
  const LoansKpiPanel({super.key, required this.kpis});

  final LoanKpis kpis;

  @override
  Widget build(BuildContext context) {
    return ResponsiveGrid(
      minItemWidth: 120,
      children: [
        KpiTile(label: 'إجمالي الممنوح', value: kpis.total, icon: Icons.account_balance_wallet_rounded, format: Fmt.iqd),
        KpiTile(label: 'المسدد', value: kpis.paid, icon: Icons.task_alt_rounded, tone: AppTone.success, format: Fmt.iqd),
        KpiTile(label: 'المتبقي بذمة الموظفين', value: kpis.remaining, icon: Icons.hourglass_bottom_rounded, tone: AppTone.danger, format: Fmt.iqd),
        KpiTile(label: 'سلف نشطة', value: kpis.activeCount, icon: Icons.people_alt_rounded, tone: AppTone.info, format: (v) => '${v.round()} موظف'),
      ],
    );
  }
}

/// نجاح تصدير كشف Excel: فتح، مشاركة، أو نسخ المسار.
Future<void> showExcelExportedDialog(BuildContext context, {required String employeeName, required String filePath}) {
  return showAppSheet<void>(
    context,
    title: 'كشف Excel جاهز',
    builder: (ctx) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('كشف حساب سلفة $employeeName مع التسديدات وجدول الأقساط.', style: AppText.bodySm),
        const SizedBox(height: AppSpace.md),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
          child: Row(
            children: [
              const ToneIcon(Icons.table_chart_rounded, tone: AppTone.success, size: 36),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Text(
                  filePath.split(Platform.pathSeparator).last,
                  style: AppText.bodySm.copyWith(color: AppColors.textPrimary),
                  overflow: TextOverflow.ellipsis,
                  textDirection: TextDirection.ltr,
                ),
              ),
              IconButton(
                tooltip: 'نسخ المسار',
                icon: const Icon(Icons.copy_rounded, size: 18),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: filePath));
                  if (ctx.mounted) AppSnack.info(ctx, 'نُسخ مسار الملف');
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.lg),
        AppButton(
          label: 'فتح الملف',
          icon: Icons.open_in_new_rounded,
          expand: true,
          onPressed: () {
            Navigator.pop(ctx);
            ExcelExportService.openExcelFile(filePath);
          },
        ),
        const SizedBox(height: AppSpace.sm),
        AppButton.secondary(
          label: 'مشاركة',
          icon: Icons.ios_share_rounded,
          expand: true,
          onPressed: () {
            Navigator.pop(ctx);
            ExcelExportService.shareExcelFile(filePath, text: 'كشف حساب سلفة الموظف: $employeeName');
          },
        ),
      ],
    ),
  );
}
