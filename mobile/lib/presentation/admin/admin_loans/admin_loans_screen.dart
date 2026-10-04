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
import '../../../data/repositories/loan_repository.dart';
import '../../../data/repositories/role_repository.dart';
import '../../shared/ui/ui.dart';
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
    AppSnack.show(context, message, tone: color == AppColors.danger ? AppTone.danger : AppTone.success);
  }

  Future<void> _init() async {
    final allowed = await RoleRepository().isAdminOrManager().catchError((Object _) => false);
    if (!mounted) return;
    if (!allowed) {
      _toast('عذراً، هذه الشاشة مخصصة لحسابات الإدارة والموارد البشرية فقط', AppColors.danger);
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
      _toast('فشل تحميل السلف: $e', AppColors.danger);
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
      _toast('فشل تصدير ملف Excel: $e', AppColors.danger);
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _createLoan() async {
    final created = await showCreateLoanSheet(context, employees: _data.employees, repo: _repo);
    if (created ?? false) {
      _toast('تمت إضافة واعتماد السلفة وتولّدت الأقساط', AppColors.success);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final loans = filterLoans(_data.loans, query: _query, branchId: _branchId, status: _status);

    final List<Widget> list;
    if (_isLoading && _data.loans.isEmpty) {
      list = const [SkeletonList(header: true, count: 3, itemHeight: 140)];
    } else if (loans.isEmpty) {
      list = [
        EmptyView(
          title: _data.loans.isEmpty ? 'لا توجد سلف بعد' : 'لا نتائج',
          message: _data.loans.isEmpty ? 'طلبات السلف والسلف المباشرة تظهر هنا.' : 'غيّر البحث أو الفلتر.',
          icon: Icons.account_balance_wallet_rounded,
          compact: true,
        ),
      ];
    } else {
      list = [
        for (var i = 0; i < loans.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.md),
            child: FadeSlideIn(
              index: i,
              child: LoanCard(
                key: ValueKey(loans[i].loan.id),
                record: loans[i],
                onOpen: () => showLoanDetailsSheet(context, loans[i], onExport: () => _export(loans[i])),
                onExport: () => _export(loans[i]),
              ),
            ),
          ),
      ];
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'create_loan_admin_fab',
        icon: const Icon(Icons.add_rounded),
        label: const Text('سلفة لموظف'),
        onPressed: _createLoan,
      ),
      appBar: AppBar(
        title: const Text('سلف الموظفين'),
        actions: [
          if (_isExporting)
            const Padding(
              padding: EdgeInsets.all(AppSpace.md),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          IconButton(icon: const Icon(Icons.refresh_rounded), tooltip: 'تحديث', onPressed: _load),
          const SizedBox(width: AppSpace.xs),
        ],
      ),
      body: RefreshIndicator.adaptive(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(0, AppSpace.sm, 0, 96),
          children: [
            LoansFilterBar(
              searchController: _searchController,
              query: _query,
              branches: _data.branches,
              branchId: _branchId,
              status: _status,
              onQueryChanged: (v) => setState(() => _query = v),
              onBranchChanged: (v) => setState(() => _branchId = v),
              onStatusChanged: (v) => setState(() => _status = v),
            ),
            const SizedBox(height: AppSpace.md),
            if (!(_isLoading && _data.loans.isEmpty)) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.page),
                child: ContentWidth(
                  maxWidth: 1000,
                  child: LoansKpiPanel(kpis: LoanKpis.of(_data.loans, branchId: _branchId)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.page),
                child: SectionHeader('المستلفون (${loans.length})'),
              ),
            ],
            for (final w in list)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.page),
                child: ContentWidth(child: w),
              ),
          ],
        ),
      ),
    );
  }
}
