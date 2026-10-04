// =========================================================================
// HR Pro — إدارة الموظفين
// =========================================================================
// القائمة مع بحث عربي وفلتر الحالة، ملف كل موظف، إضافة موظف (حساب دخول)،
// تعديل المستمسكات، تفعيل/تعطيل الحساب، وفك ربط الجهاز.
// الأجزاء: employee_management/{employee_form_sheet, employee_documents,
// employee_profile_sheet}.dart
// =========================================================================

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/models/models.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/utils/app_log.dart';
import '../../../core/utils/arabic_format.dart';
import '../../../data/repositories/employee_admin_repository.dart';
import '../../../data/repositories/role_repository.dart';
import '../../shared/ui/ui.dart';
import 'employee_documents.dart';
import 'employee_form_sheet.dart';
import 'employee_profile_sheet.dart';

class EmployeeManagementScreen extends StatefulWidget {
  const EmployeeManagementScreen({super.key});

  @override
  State<EmployeeManagementScreen> createState() => _EmployeeManagementScreenState();
}

class _EmployeeManagementScreenState extends State<EmployeeManagementScreen> {
  final EmployeeAdminRepository _repo = EmployeeAdminRepository();
  bool _isLoading = true;
  bool _hasError = false;

  /// تعطيل/تفعيل الحساب للأدمن فقط (القاعدة ترفضه لمدير الفرع)
  bool _isAdmin = false;
  List<ManagedEmployee> _employees = [];
  List<BranchModel> _branches = [];
  String _searchQuery = '';
  String _statusFilter = 'all'; // all | active | inactive
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadEmployees();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadEmployees() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    final user = SupabaseService.currentUser;
    if (user == null) {
      if (mounted) Navigator.pop(context);
      return;
    }

    try {
      final role = await RoleRepository().currentRole();

      if (role != 'admin' && role != 'manager') {
        if (mounted) Navigator.pop(context);
        return;
      }

      final results = await _repo.fetchEmployeesAndBranches();

      if (mounted) {
        setState(() {
          _isAdmin = role == 'admin';
          _employees = results.employees;
          _branches = results.branches;
          _hasError = false;
        });
      }
    } catch (e) {
      appLog('Error loading employees: $e');
      if (mounted) setState(() => _hasError = true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleEmployeeStatus(ManagedEmployee emp) async {
    final isActive = emp.isActive;
    final ok = await showAppConfirm(
      context,
      title: isActive ? 'تعطيل حساب ${emp.fullName}؟' : 'تفعيل حساب ${emp.fullName}؟',
      message: isActive ? 'ما يقدر يسجل دخول أو يبصم حتى تفعّله مرة ثانية.' : 'يرجع يقدر يدخل ويبصم عادي.',
      confirmLabel: isActive ? 'تعطيل' : 'تفعيل',
      destructive: isActive,
    );
    if (!ok || !mounted) return;
    // آخر يوم عمل فعلي: يُحسب راتب المسير الأخير حتى هذا اليوم
    DateTime? lastDay;
    if (isActive) {
      lastDay = await showDatePicker(
        context: context,
        initialDate: DateTime.now(),
        firstDate: DateTime.now().subtract(const Duration(days: 120)),
        lastDate: DateTime.now().add(const Duration(days: 60)),
        helpText: 'آخر يوم عمل',
      );
      if (lastDay == null || !mounted) return;
    }
    try {
      setState(() => _isLoading = true);
      await _repo.setActive(emp.id, active: !isActive, lastDay: lastDay);
      if (mounted) AppSnack.show(context, isActive ? 'عُطّل الحساب' : 'فُعّل الحساب', tone: isActive ? AppTone.warning : AppTone.success);
      unawaited(_loadEmployees());
    } catch (e) {
      appLog('Error toggling status: $e');
      if (mounted) {
        AppSnack.error(context, 'تعذّر تغيير الحالة');
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _unbindDevice(ManagedEmployee emp) async {
    final ok = await showAppConfirm(
      context,
      title: 'فك ربط جهاز ${emp.fullName}؟',
      message: 'راح يقدر يسجل دخول من أول جهاز جديد يستعمله، ويُقفل عليه.',
      confirmLabel: 'فك الربط',
    );
    if (!ok) return;
    final employeeId = emp.id;
    try {
      setState(() => _isLoading = true);
      // مسح تسجيلات الجهاز القديمة ثم قفل الحساب على الجهاز القادم
      await _repo.unbindDevice(employeeId);
      if (mounted) AppSnack.success(context, 'فُكّ ربط الجهاز');
      unawaited(_loadEmployees());
    } catch (e) {
      appLog('Error unbinding device: $e');
      if (mounted) {
        AppSnack.error(context, 'تعذّر فك الربط');
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _addEmployee() async {
    final created = await showEmployeeFormSheet(context, branches: _branches);
    if (created == true && mounted) {
      AppSnack.success(context, 'أُنشئ حساب الموظف');
      unawaited(_loadEmployees());
    }
  }

  Future<void> _editDocuments(ManagedEmployee emp) async {
    final saved = await showEditDocumentsSheet(context, emp);
    if (saved == true && mounted) {
      AppSnack.success(context, 'حُدّثت المستمسكات');
      unawaited(_loadEmployees());
    }
  }

  void _openProfile(ManagedEmployee emp) => showEmployeeProfileSheet(context, emp, onEditDocuments: () => _editDocuments(emp));


  List<ManagedEmployee> get _filtered {
    final q = normalizeArabicForSearch(_searchQuery);
    return _employees.where((e) {
      final active = e.isActive;
      if (_statusFilter == 'active' && !active) return false;
      if (_statusFilter == 'inactive' && active) return false;
      if (q.isEmpty) return true;
      final fields = [
        normalizeArabicForSearch(e.fullName ?? ''),
        (e.email ?? '').toLowerCase(),
        (e.employeeCode ?? '').toLowerCase(),
        (e.phone ?? '').toLowerCase(),
        normalizeArabicForSearch(e.departmentName ?? ''),
        normalizeArabicForSearch(e.branchName ?? ''),
      ];
      return fields.any((f) => f.contains(q));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final activeCount = _employees.where((e) => e.isActive).length;

    final List<Widget> list;
    if (_isLoading && _employees.isEmpty) {
      list = const [SkeletonList(count: 6)];
    } else if (_hasError && _employees.isEmpty) {
      list = [ErrorView(onRetry: _loadEmployees)];
    } else if (filtered.isEmpty) {
      list = [
        EmptyView(
          title: _employees.isEmpty ? 'لا يوجد موظفون' : 'لا نتائج',
          message: _employees.isEmpty ? 'أضف أول موظف من زر "موظف جديد".' : 'جرّب اسماً أو كوداً أو فرعاً آخر.',
          icon: Icons.person_search_rounded,
          compact: true,
        ),
      ];
    } else {
      list = [for (var i = 0; i < filtered.length; i++) FadeSlideIn(index: i, child: _employeeTile(filtered[i]))];
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      floatingActionButton: FloatingActionButton.extended(onPressed: _addEmployee, icon: const Icon(Icons.person_add_rounded), label: const Text('موظف جديد')),
      appBar: AppBar(title: Text('الموظفون${_employees.isEmpty ? '' : ' (${_employees.length})'}')),
      body: RefreshIndicator.adaptive(
        onRefresh: _loadEmployees,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpace.page, AppSpace.sm, AppSpace.page, 96),
          children: [
            ContentWidth(
              child: TextField(
                controller: _search,
                onChanged: (v) => setState(() => _searchQuery = v),
                textInputAction: TextInputAction.search,
                style: AppText.body,
                decoration: InputDecoration(
                  hintText: 'ابحث بالاسم، الكود، الهاتف، الفرع',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searchQuery.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'مسح البحث',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _search.clear();
                            setState(() => _searchQuery = '');
                          },
                        ),
                ),
              ),
            ),
            const SizedBox(height: AppSpace.sm),
            AppChoiceChips<String>(
              scrollable: true,
              value: _statusFilter,
              onChanged: (v) => setState(() => _statusFilter = v),
              options: [
                ('all', 'الكل (${_employees.length})', null),
                ('active', 'نشط ($activeCount)', null),
                ('inactive', 'معطل (${_employees.length - activeCount})', null),
              ],
            ),
            const SizedBox(height: AppSpace.md),
            for (final w in list) Padding(padding: const EdgeInsets.only(bottom: AppSpace.sm), child: ContentWidth(child: w)),
          ],
        ),
      ),
    );
  }

  Widget _employeeTile(ManagedEmployee emp) {
    final isActive = emp.isActive;
    final hasDevice = emp.hasDevice;
    final branch = emp.branchName;
    final name = emp.fullName ?? 'بدون اسم';

    return AppCard(
      padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.md, 0, AppSpace.md),
      onTap: () => _openProfile(emp),
      child: Row(
        children: [
          AppAvatar(name: name, url: emp.avatarUrl, tone: isActive ? AppTone.brand : AppTone.neutral),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: AppText.subtitle.copyWith(color: isActive ? null : AppColors.textMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                  '${emp.employeeCode ?? ''}${branch == null ? '' : ' · $branch'}',
                  style: AppText.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpace.xs),
                Wrap(
                  spacing: AppSpace.xs,
                  runSpacing: AppSpace.xs,
                  children: [
                    StatusBadge(employeeRoleLabel(emp.role), tone: AppTone.accent),
                    if (!isActive) const StatusBadge('معطل', tone: AppTone.danger, dot: true),
                    if (hasDevice) const StatusBadge('جهاز مربوط', tone: AppTone.info, icon: Icons.smartphone_rounded),
                    if (branch == null) const StatusBadge('بدون فرع', tone: AppTone.warning),
                  ],
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'خيارات',
            onSelected: (value) {
              if (value == 'profile') _openProfile(emp);
              if (value == 'docs') _editDocuments(emp);
              if (value == 'toggle') _toggleEmployeeStatus(emp);
              if (value == 'unbind') _unbindDevice(emp);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'profile', child: ListTile(leading: Icon(Icons.badge_rounded), title: Text('الملف'))),
              const PopupMenuItem(value: 'docs', child: ListTile(leading: Icon(Icons.folder_rounded), title: Text('المستمسكات'))),
              if (hasDevice) const PopupMenuItem(value: 'unbind', child: ListTile(leading: Icon(Icons.phonelink_erase_rounded), title: Text('فك ربط الجهاز'))),
              if (_isAdmin)
                PopupMenuItem(
                  value: 'toggle',
                  child: ListTile(
                    leading: Icon(isActive ? Icons.block_rounded : Icons.check_circle_rounded, color: isActive ? AppColors.danger : AppColors.success),
                    title: Text(isActive ? 'تعطيل الحساب' : 'تفعيل الحساب'),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
