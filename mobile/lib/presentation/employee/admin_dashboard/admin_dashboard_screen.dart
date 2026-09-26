// =========================================================================
// لوحة إدارة الموارد البشرية للمدراء والأدمن
// =========================================================================
// البيانات: data/repositories/admin_dashboard_repository.dart
// الإجراءات: data/repositories/admin_actions_repository.dart
// =========================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/models.dart';
import '../../../core/routes/app_router.dart';
import '../../../core/utils/error_text.dart';
import '../../../data/repositories/admin_actions_repository.dart';
import '../../../data/repositories/admin_dashboard_repository.dart';
import '../../../data/repositories/role_repository.dart';
import '../../shared/ui/ui.dart';
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
    final tone = color == AppColors.danger
        ? AppTone.danger
        : color == AppColors.success
            ? AppTone.success
            : AppTone.warning;
    AppSnack.show(context, message.replaceAll(RegExp(r'\s*[]+'), ''), tone: tone);
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
      _toast('فشل تنفيذ العملية: ${errorText(e)}', AppColors.danger);
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


  static const _tools = <(IconData, String, String, AppTone)>[
    (Icons.location_searching_rounded, 'التتبع الحي', AppRoutes.adminTracking, AppTone.brand),
    (Icons.bar_chart_rounded, 'تقارير الحضور', AppRoutes.adminAttendanceReport, AppTone.info),
    (Icons.account_balance_wallet_rounded, 'السلف و Excel', AppRoutes.adminLoans, AppTone.warning),
    (Icons.people_alt_rounded, 'الموظفون', AppRoutes.adminEmployeeManagement, AppTone.success),
    (Icons.store_rounded, 'الفروع', AppRoutes.adminBranchManagement, AppTone.accent),
    (Icons.schedule_rounded, 'أوقات الدوام', AppRoutes.adminBranchSchedule, AppTone.accent),
    (Icons.campaign_rounded, 'التعاميم', AppRoutes.adminAnnouncement, AppTone.info),
    (Icons.delete_sweep_rounded, 'المحذوفات', AppRoutes.adminTrash, AppTone.neutral),
    (Icons.cloud_queue_rounded, 'التخزين', AppRoutes.adminStorage, AppTone.neutral),
  ];

  void _openTools() {
    showAppSheet<void>(
      context,
      title: 'أدوات الإدارة',
      builder: (ctx) => ResponsiveGrid(
        minItemWidth: 96,
        spacing: AppSpace.sm,
        children: [
          for (final (icon, label, route, tone) in _tools)
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: AppSpace.md, horizontal: AppSpace.xs),
              semanticLabel: label,
              onTap: () {
                Navigator.pop(ctx);
                context.push(route);
              },
              child: ExcludeSemantics(
                child: Column(
                  children: [
                    ToneIcon(icon, tone: tone),
                    const SizedBox(height: AppSpace.sm),
                    Text(label, textAlign: TextAlign.center, maxLines: 2, style: AppText.caption.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _snapshot;
    final pending = s.leaves.length + s.loans.length + s.devices.length;
    final tabs = [
      ('القرارات', s.decisions.length),
      ('الإجازات', s.leaves.length),
      ('السلف', s.loans.length),
      ('الأجهزة', s.devices.length),
      ('الأمان', s.securityLogs.length),
    ];

    return Scaffold(
      backgroundColor: AppColors.bg,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(AppRoutes.adminAnnouncement),
        icon: const Icon(Icons.campaign_rounded),
        label: const Text('تعميم جديد'),
      ),
      body: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          SliverAppBar(
            pinned: true,
            title: const Text('لوحة الإدارة'),
            actions: [
              IconButton(tooltip: 'تحديث', icon: const Icon(Icons.refresh_rounded), onPressed: _load),
              IconButton(tooltip: 'أدوات الإدارة', icon: const Icon(Icons.apps_rounded), onPressed: _openTools),
              const SizedBox(width: AppSpace.xs),
            ],
          ),
          SliverToBoxAdapter(
            child: ContentWidth(
              maxWidth: 1000,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(AppSpace.page, AppSpace.xs, AppSpace.page, AppSpace.md),
                child: _isLoading && s.present == 0 && s.absent == 0
                    ? const Row(
                        children: [
                          Expanded(child: Skeleton(height: 96, radius: AppRadius.md)),
                          SizedBox(width: AppSpace.md),
                          Expanded(child: Skeleton(height: 96, radius: AppRadius.md)),
                        ],
                      )
                    : DashboardStatsRow(present: s.present, absent: s.absent, violations: s.securityLogs.length, pending: pending),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: DashboardFiltersBar(
              filter: _filter,
              branches: _lookups.branches,
              employees: _lookups.employees.where((e) => e.isActive).toList(),
              onChanged: _setFilter,
            ),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _TabBarHeader(
              TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  for (final (label, count) in tabs)
                    Tab(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(label),
                          if (count > 0) ...[
                            const SizedBox(width: AppSpace.xs),
                            Badge(label: Text('$count'), backgroundColor: AppColors.surface3, textColor: AppColors.textPrimary),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
        body: _isLoading
            ? const Padding(padding: EdgeInsets.all(AppSpace.page), child: SkeletonList(count: 4, itemHeight: 110))
            : RefreshIndicator.adaptive(
                onRefresh: _load,
                notificationPredicate: (n) => n.depth <= 1,
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
                        deduct ? 'تم تطبيق الخصم' : 'تم الإعفاء من الخصم',
                        deduct ? AppColors.warning : AppColors.success,
                      ),
                    ),
                    LeavesTab(
                      leaves: s.leaves,
                      busyKey: _busyKey,
                      onDecide: (leave, approve) => _run(
                        leave.id,
                        () => _actions.decideLeave(leave.id, approve: approve),
                        approve ? 'قُبل طلب الإجازة' : 'رُفض طلب الإجازة',
                        approve ? AppColors.success : AppColors.danger,
                      ),
                    ),
                    LoansTab(
                      loans: s.loans,
                      busyKey: _busyKey,
                      onDecide: (loan, approve) => _run(
                        loan.id,
                        () => approve ? _actions.approveLoan(loan) : _actions.rejectLoan(loan.id),
                        approve ? 'اعتُمدت السلفة وتولّدت الأقساط' : 'رُفض طلب السلفة',
                        approve ? AppColors.success : AppColors.danger,
                      ),
                    ),
                    DevicesTab(
                      devices: s.devices,
                      busyKey: _busyKey,
                      onDecide: (device, approve) => _run(
                        device.id,
                        () => approve ? _actions.approveDevice(device) : _actions.rejectDevice(device.id),
                        approve ? 'اعتُمد الجهاز' : 'رُفض الجهاز وأُزيل',
                        approve ? AppColors.success : AppColors.danger,
                      ),
                    ),
                    SecurityTab(logs: s.securityLogs),
                  ],
                ),
              ),
      ),
    );
  }
}

class _TabBarHeader extends SliverPersistentHeaderDelegate {
  _TabBarHeader(this.tabBar);
  final TabBar tabBar;

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) =>
      ColoredBox(color: AppColors.bg, child: tabBar);

  @override
  bool shouldRebuild(covariant _TabBarHeader oldDelegate) => oldDelegate.tabBar != tabBar;
}
