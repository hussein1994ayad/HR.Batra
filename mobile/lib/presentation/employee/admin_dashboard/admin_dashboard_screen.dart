// =========================================================================
// لوحة إدارة الموارد البشرية للمدراء والأدمن
// =========================================================================
// البيانات: data/repositories/admin_dashboard_repository.dart
// الإجراءات: data/repositories/admin_actions_repository.dart
// =========================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/design.dart';
import '../../../core/models/models.dart';
import '../../../core/routes/app_router.dart';
import '../../../data/repositories/admin_actions_repository.dart';
import '../../../data/repositories/admin_dashboard_repository.dart';
import '../../../data/repositories/role_repository.dart';
import '../../shared/widgets/glass_background.dart';
import 'widgets/dashboard_header.dart';
import 'widgets/dashboard_tabs.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> with SingleTickerProviderStateMixin {
  final _repo = AdminDashboardRepository();
  final _actions = AdminActionsRepository();
  late final TabController _tabController = TabController(length: 5, vsync: this);

  bool _isLoading = true;
  DashboardFilter _filter = const DashboardFilter();
  DashboardLookups _lookups = const DashboardLookups(branches: [], employees: []);
  DashboardSnapshot _snapshot = const DashboardSnapshot();

  /// مفتاح البطاقة التي يُنفّذ قرارها الآن (لتعطيل أزرارها فقط)
  String? _busyKey;

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final role = await RoleRepository().currentRole();
      if (!mounted) return;
      if (role == null) {
        context.go(AppRoutes.login);
        return;
      }
      if (role != 'admin' && role != 'manager') {
        context.go(AppRoutes.employeeHome);
        return;
      }
      _lookups = await _repo.loadLookups();
    } catch (e) {
      debugPrint('Error loading dashboard lookups: $e');
      if (mounted) context.go(AppRoutes.employeeHome);
      return;
    }
    await _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final snapshot = await _repo.loadSnapshot(_filter, _lookups.employees);
      if (mounted) setState(() => _snapshot = snapshot);
    } catch (e) {
      debugPrint('Error loading dashboard: $e');
      _toast('تعذر تحميل بيانات اللوحة: $e', AppColors.danger);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _toast(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message, style: const TextStyle(fontFamily: 'Cairo')), backgroundColor: color),
    );
  }

  /// ينفّذ إجراءً على بطاقة، يعرض النتيجة، ثم يعيد التحميل.
  Future<void> _run(String key, Future<void> Function() action, String success, Color successColor) async {
    setState(() => _busyKey = key);
    try {
      await action();
      _toast(success, successColor);
      await _load();
    } catch (e) {
      debugPrint('Admin action failed: $e');
      _toast('فشل تنفيذ العملية: $e', AppColors.danger);
    } finally {
      if (mounted) setState(() => _busyKey = null);
    }
  }

  void _setFilter(DashboardFilter filter) {
    setState(() => _filter = filter);
    unawaited(_load());
  }

  WorkScheduleModel? _scheduleFor(PendingDecision item) {
    final departmentId = _lookups.employees.where((e) => e.id == item.employeeId).firstOrNull?.departmentId;
    return scheduleForDecision(item, _snapshot.schedules, departmentId);
  }

  @override
  Widget build(BuildContext context) {
    final s = _snapshot;
    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text(
            'لوحة إدارة الموارد البشرية 👑',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: AppColors.textPrimary,
              shadows: [Shadow(color: AppColors.brand, blurRadius: 10)],
            ),
          ),
          actions: [
            _nav(Icons.location_searching_rounded, AppColors.brand, 'خريطة التتبع الحي للموظفين', AppRoutes.adminTracking),
            _nav(Icons.account_balance_wallet_rounded, AppColors.brand, 'متابعة السلف وكشوف Excel', AppRoutes.adminLoans),
            _nav(Icons.bar_chart_rounded, AppColors.brand, 'تقارير الحضور', AppRoutes.adminAttendanceReport),
            _nav(Icons.people_alt_rounded, AppColors.success, 'إدارة الموظفين', AppRoutes.adminEmployeeManagement),
            _nav(Icons.schedule_rounded, AppColors.warning, 'أوقات عمل الأفرع', AppRoutes.adminBranchSchedule),
            _nav(Icons.delete_sweep_rounded, AppColors.accent, 'سلة المحذوفات', AppRoutes.adminTrash),
            _nav(Icons.cloud_queue_rounded, AppColors.brand, 'إحصائيات التخزين', AppRoutes.adminStorage),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(150),
            child: Column(
              children: [
                DashboardFiltersBar(
                  filter: _filter,
                  branches: _lookups.branches,
                  employees: _lookups.employees.where((e) => e.isActive).toList(),
                  onChanged: _setFilter,
                ),
                TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  labelStyle: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 11),
                  unselectedLabelStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 11),
                  indicatorColor: AppColors.brand,
                  labelColor: AppColors.brand,
                  unselectedLabelColor: AppColors.textSecondary,
                  indicatorSize: TabBarIndicatorSize.tab,
                  tabs: [
                    Tab(text: 'القرارات (${s.decisions.length})'),
                    Tab(text: 'الإجازات (${s.leaves.length})'),
                    Tab(text: 'السلف (${s.loans.length})'),
                    Tab(text: 'الأجهزة (${s.devices.length})'),
                    Tab(text: 'الأمان (${s.securityLogs.length})'),
                  ],
                ),
              ],
            ),
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => context.push(AppRoutes.adminAnnouncement),
          backgroundColor: AppColors.accent,
          icon: const Icon(Icons.campaign_rounded, color: AppColors.textPrimary),
          label: const Text('تعميم جديد', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AppColors.brand))
            : RefreshIndicator(
                onRefresh: _load,
                color: AppColors.brand,
                backgroundColor: AppColors.surface1,
                child: Column(
                  children: [
                    DashboardStatsRow(present: s.present, absent: s.absent, violations: s.securityLogs.length),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          DecisionsTab(
                            hasDate: _filter.date != null,
                            decisions: s.decisions,
                            scheduleFor: _scheduleFor,
                            busyKey: _busyKey,
                            onDecide: (item, {required deduct, required reason, required amount}) => _run(
                              item.key,
                              () => _actions.applyDecision(item, deduct: deduct, reason: reason, amount: amount),
                              deduct ? 'تم تطبيق الخصم ⚠️' : 'تم الإعفاء من الخصم ✅',
                              deduct ? AppColors.warning : AppColors.success,
                            ),
                          ),
                          LeavesTab(
                            leaves: s.leaves,
                            busyKey: _busyKey,
                            onDecide: (leave, approve) => _run(
                              leave.id,
                              () => _actions.decideLeave(leave.id, approve: approve),
                              approve ? 'تم قبول طلب الإجازة بنجاح ✅' : 'تم رفض طلب الإجازة ❌',
                              approve ? AppColors.success : AppColors.danger,
                            ),
                          ),
                          LoansTab(
                            loans: s.loans,
                            busyKey: _busyKey,
                            onDecide: (loan, approve) => _run(
                              loan.id,
                              () => approve ? _actions.approveLoan(loan) : _actions.rejectLoan(loan.id),
                              approve ? 'تم اعتماد السلفة وتوليد الأقساط ✅' : 'تم رفض طلب السلفة ❌',
                              approve ? AppColors.success : AppColors.danger,
                            ),
                          ),
                          DevicesTab(
                            devices: s.devices,
                            busyKey: _busyKey,
                            onDecide: (device, approve) => _run(
                              device.id,
                              () => approve ? _actions.approveDevice(device) : _actions.rejectDevice(device.id),
                              approve ? 'تم اعتماد الجهاز بنجاح ✅' : 'تم رفض وإزالة الهاتف المذكور ❌',
                              approve ? AppColors.success : AppColors.danger,
                            ),
                          ),
                          SecurityTab(logs: s.securityLogs),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _nav(IconData icon, Color color, String tooltip, String route) =>
      IconButton(icon: Icon(icon, color: color), tooltip: tooltip, onPressed: () => context.push(route));
}
