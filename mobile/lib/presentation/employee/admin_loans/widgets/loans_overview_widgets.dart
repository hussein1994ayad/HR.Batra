import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/constants.dart';
import '../../../../core/logic/loan_rules.dart';
import '../../../../core/models/models.dart';
import '../../../../core/services/excel_export_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../shared/widgets/glass_container.dart';

/// البحث بالاسم، قائمة الفروع، وشرائح الحالة.
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

  static const _chips = {
    LoanStatusFilter.all: 'الكل',
    LoanStatusFilter.active: 'سلف نشطة (عليها متبقي)',
    LoanStatusFilter.completed: 'مسددة بالكامل',
    LoanStatusFilter.pending: 'طلبات معلقة',
  };

  @override
  Widget build(BuildContext context) {
    final branchSelected = branchId != 'all';
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
          child: Container(
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white12),
            ),
            child: TextField(
              controller: searchController,
              style: const TextStyle(fontFamily: 'Cairo', color: Colors.white, fontSize: 12),
              onChanged: onQueryChanged,
              decoration: InputDecoration(
                hintText: 'البحث باسم الموظف المستلف...',
                hintStyle: const TextStyle(fontFamily: 'Cairo', color: Colors.white38, fontSize: 11),
                prefixIcon: const Icon(Icons.search_rounded, color: Colors.white60, size: 18),
                suffixIcon: query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear_rounded, color: Colors.white60, size: 16),
                        onPressed: () {
                          searchController.clear();
                          onQueryChanged('');
                        },
                      ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
          child: Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: branchSelected ? AppTheme.neonCyan : Colors.white12, width: branchSelected ? 1.5 : 1.0),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                dropdownColor: const Color(0xFF0F172A),
                value: branches.any((b) => b.id == branchId) ? branchId : 'all',
                icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppTheme.neonCyan, size: 20),
                items: [
                  const DropdownMenuItem(
                    value: 'all',
                    child: Row(
                      children: [
                        Icon(Icons.domain_rounded, color: AppTheme.neonCyan, size: 16),
                        SizedBox(width: 8),
                        Text('🏢 جميع الفروع (كافة الموظفين)',
                            style: TextStyle(fontFamily: 'Cairo', color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  for (final b in branches)
                    DropdownMenuItem(
                      value: b.id,
                      child: Row(
                        children: [
                          const Icon(Icons.storefront_rounded, color: AppTheme.successGreen, size: 16),
                          const SizedBox(width: 8),
                          Text('فرع: ${b.name}', style: const TextStyle(fontFamily: 'Cairo', color: Colors.white, fontSize: 12)),
                        ],
                      ),
                    ),
                ],
                onChanged: (v) => onBranchChanged(v ?? 'all'),
              ),
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              for (final entry in _chips.entries) ...[
                _chip(entry.value, selected: status == entry.key, onTap: () => onStatusChanged(entry.key)),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _chip(String label, {required bool selected, required VoidCallback onTap}) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? AppTheme.primaryTeal : Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? AppTheme.neonCyan : Colors.white12),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 11,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              color: selected ? Colors.white : Colors.white70,
            ),
          ),
        ),
      );
}

/// بطاقات إجمالي السلف والمسدد والمتبقي وعدد السلف النشطة.
class LoansKpiPanel extends StatelessWidget {
  const LoansKpiPanel({super.key, required this.kpis});

  final LoanKpis kpis;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      padding: const EdgeInsets.all(16),
      borderRadius: 22,
      opacity: 0.08,
      borderColor: AppTheme.neonCyan.withValues(alpha: 0.2),
      child: Column(
        children: [
          Row(
            children: [
              _Kpi('إجمالي السلف الممنوحة', AppConstants.formatMoney(kpis.total), Colors.white,
                  Icons.account_balance_wallet_rounded, AppTheme.primaryTeal.withValues(alpha: 0.2)),
              const SizedBox(width: 10),
              _Kpi('إجمالي المبالغ المسددة', AppConstants.formatMoney(kpis.paid), AppTheme.successGreen, Icons.task_alt_rounded,
                  AppTheme.successGreen.withValues(alpha: 0.2)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _Kpi('المتبقي بذمة الموظفين', AppConstants.formatMoney(kpis.remaining), const Color(0xFFF87171),
                  Icons.hourglass_bottom_rounded, const Color(0xFFEF4444).withValues(alpha: 0.2)),
              const SizedBox(width: 10),
              _Kpi('السلف النشطة الجارية', '${kpis.activeCount} موظف', AppTheme.neonCyan, Icons.people_alt_rounded,
                  AppTheme.neonCyan.withValues(alpha: 0.2)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi(this.title, this.value, this.color, this.icon, this.iconBg);

  final String title;
  final String value;
  final Color color;
  final IconData icon;
  final Color iconBg;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 10, color: Colors.white60),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(value, style: TextStyle(fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.bold, color: color)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// نافذة نجاح تصدير كشف Excel مع النسخ والمشاركة والفتح.
Future<void> showExcelExportedDialog(BuildContext context, {required String employeeName, required String filePath}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF0F172A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: AppTheme.successGreen.withValues(alpha: 0.4)),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: AppTheme.successGreen.withValues(alpha: 0.2), shape: BoxShape.circle),
            child: const Icon(Icons.table_chart_rounded, color: AppTheme.successGreen, size: 24),
          ),
          const SizedBox(width: 12),
          const Flexible(
            child: Text('تم تصدير كشف Excel بنجاح! 📊',
                style: TextStyle(fontFamily: 'Cairo', fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'تم إنشاء كشف حساب السلفة الاحترافي الخاص بالموظف ($employeeName) متضمناً كافة التسديدات والملاحظات وجدول الأقساط.',
            style: const TextStyle(fontFamily: 'Cairo', fontSize: 13, color: Colors.white70, height: 1.5),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              children: [
                const Icon(Icons.folder_rounded, color: AppTheme.neonCyan, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    filePath.split(Platform.pathSeparator).last,
                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, color: AppTheme.neonCyan, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: filePath));
            if (!ctx.mounted) return;
            ScaffoldMessenger.of(ctx).showSnackBar(
              const SnackBar(
                content: Text('تم نسخ مسار الملف إلى الحافظة 📋', style: TextStyle(fontFamily: 'Cairo')),
                backgroundColor: AppTheme.primaryTeal,
              ),
            );
          },
          icon: const Icon(Icons.copy_rounded, size: 18, color: Colors.white70),
          label: const Text('نسخ المسار', style: TextStyle(fontFamily: 'Cairo', color: Colors.white70, fontSize: 11)),
        ),
        OutlinedButton.icon(
          onPressed: () {
            Navigator.pop(ctx);
            ExcelExportService.shareExcelFile(filePath, text: 'كشف حساب سلفة الموظف: $employeeName');
          },
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.neonCyan,
            side: const BorderSide(color: AppTheme.neonCyan),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          icon: const Icon(Icons.share_rounded, size: 18),
          label: const Text('مشاركة / واتساب 📤', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 11)),
        ),
        ElevatedButton.icon(
          onPressed: () {
            Navigator.pop(ctx);
            ExcelExportService.openExcelFile(filePath);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.successGreen,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          icon: const Icon(Icons.open_in_new_rounded, size: 18),
          label: const Text('فتح الملف 📊', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 11)),
        ),
      ],
    ),
  );
}
