// =========================================================================
// متابعة سلف الموظفين وأقساطهم وكشوف Excel (للإدارة)
// =========================================================================
// البيانات: data/repositories/loan_repository.dart
// التصفية والإحصاءات: core/logic/loan_rules.dart
// =========================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/logic/loan_rules.dart';
import '../../../core/models/models.dart';
import '../../../core/routes/app_router.dart';
import '../../../core/services/excel_export_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/repositories/loan_repository.dart';
import '../../../data/repositories/role_repository.dart';
import '../../shared/widgets/glass_background.dart';
import 'widgets/create_loan_sheet.dart';
import 'widgets/loan_card.dart';
import 'widgets/loan_details_sheet.dart';
import 'widgets/loans_overview_widgets.dart';

class AdminLoansManagementScreen extends StatefulWidget {
  const AdminLoansManagementScreen({super.key});

  @override
  State<AdminLoansManagementScreen> createState() => _AdminLoansManagementScreenState();
}

class _AdminLoansManagementScreenState extends State<AdminLoansManagementScreen> {
  final _repo = LoanRepository();
  final _searchController = TextEditingController();

  bool _isLoading = true;
  bool _isExporting = false;
  String _query = '';
  String _branchId = 'all';
  LoanStatusFilter _status = LoanStatusFilter.all;
  LoansOverview _data = const LoansOverview(loans: [], branches: [], employees: []);

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toast(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message, style: const TextStyle(fontFamily: 'Cairo')), backgroundColor: color),
    );
  }

  Future<void> _init() async {
    final allowed = await RoleRepository().isAdminOrManager().catchError((Object _) => false);
    if (!mounted) return;
    if (!allowed) {
      _toast('عذراً، هذه الشاشة مخصصة لحسابات الإدارة والموارد البشرية فقط ⚠️', AppTheme.dangerRed);
      context.go(AppRoutes.employeeHome);
      return;
    }
    await _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final data = await _repo.loadOverview();
      if (mounted) setState(() => _data = data);
    } catch (e) {
      debugPrint('خطأ في تحميل بيانات السلف: $e');
      _toast('فشل تحميل السلف: $e', AppTheme.dangerRed);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _export(LoanRecord record) async {
    setState(() => _isExporting = true);
    try {
      final path = await ExcelExportService.generateLoanStatementExcel(record);
      if (mounted) {
        await showExcelExportedDialog(context, employeeName: record.loan.employeeName ?? 'الموظف', filePath: path);
      }
    } catch (e) {
      debugPrint('خطأ في تصدير ملف Excel: $e');
      _toast('فشل تصدير ملف Excel: $e', AppTheme.dangerRed);
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _createLoan() async {
    final created = await showCreateLoanSheet(context, employees: _data.employees, repo: _repo);
    if (created ?? false) {
      _toast('تمت إضافة واعتماد السلفة وتوليد الأقساط بنجاح ✅', AppTheme.successGreen);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final loans = filterLoans(_data.loans, query: _query, branchId: _branchId, status: _status);

    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: FloatingActionButton.extended(
          heroTag: 'create_loan_admin_fab',
          backgroundColor: AppTheme.primaryTeal,
          foregroundColor: Colors.white,
          elevation: 4,
          icon: const Icon(Icons.add_circle_outline_rounded),
          label: const Text('إضافة سلفة لموظف ➕', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13)),
          onPressed: _createLoan,
        ),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text(
            'متابعة سلف وأقساط الموظفين 💼',
            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: AppTheme.neonCyan),
              tooltip: 'تحديث البيانات',
              onPressed: _load,
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(165),
            child: LoansFilterBar(
              searchController: _searchController,
              query: _query,
              branches: _data.branches,
              branchId: _branchId,
              status: _status,
              onQueryChanged: (v) => setState(() => _query = v),
              onBranchChanged: (v) => setState(() => _branchId = v),
              onStatusChanged: (v) => setState(() => _status = v),
            ),
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AppTheme.neonCyan))
            : RefreshIndicator(
                onRefresh: _load,
                color: AppTheme.neonCyan,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    LoansKpiPanel(kpis: LoanKpis.of(_data.loans, branchId: _branchId)),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'قائمة المستلفين (${loans.length})',
                          style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                        ),
                        if (_isExporting)
                          const Row(
                            children: [
                              SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.successGreen)),
                              SizedBox(width: 6),
                              Text('جاري إنشاء Excel...', style: TextStyle(fontFamily: 'Cairo', fontSize: 11, color: AppTheme.successGreen)),
                            ],
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (loans.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          children: [
                            Icon(Icons.search_off_rounded, size: 64, color: Colors.white.withValues(alpha: 0.3)),
                            const SizedBox(height: 16),
                            const Text(
                              'لا توجد سجلات سلف مطابقة للبحث أو الفلتر المختار',
                              style: TextStyle(fontFamily: 'Cairo', fontSize: 13, color: Colors.white60),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    else
                      for (final record in loans)
                        LoanCard(
                          key: ValueKey(record.loan.id),
                          record: record,
                          onOpen: () => showLoanDetailsSheet(context, record, onExport: () => _export(record)),
                          onExport: () => _export(record),
                        ),
                  ],
                ),
              ),
      ),
    );
  }
}
