import 'package:flutter/material.dart';

import '../../../../core/models/models.dart';
import '../../../../data/repositories/admin_dashboard_repository.dart';
import '../../../shared/ui/ui.dart';

/// مؤشرات اليوم: حاضر، غائب، طلبات معلقة، مخالفات.
class DashboardStatsRow extends StatelessWidget {
  const DashboardStatsRow({super.key, required this.present, required this.absent, required this.violations, this.pending = 0});

  final int present;
  final int absent;
  final int violations;
  final int pending;

  @override
  Widget build(BuildContext context) {
    return ResponsiveGrid(
      minItemWidth: 140,
      children: [
        KpiTile(label: 'حاضر اليوم', value: present, icon: Icons.how_to_reg_rounded, tone: AppTone.success),
        KpiTile(label: 'غائب اليوم', value: absent, icon: Icons.person_off_rounded, tone: AppTone.danger),
        KpiTile(label: 'طلبات بانتظارك', value: pending, icon: Icons.pending_actions_rounded, tone: AppTone.warning),
        KpiTile(label: 'مخالفات أمنية', value: violations, icon: Icons.gpp_maybe_rounded, tone: violations > 0 ? AppTone.danger : AppTone.neutral),
      ],
    );
  }
}

/// فلاتر اللوحة: الفرع، الموظف، التاريخ، وإعادة الضبط — كرقاقات تفتح قوائم اختيار.
class DashboardFiltersBar extends StatelessWidget {
  const DashboardFiltersBar({
    super.key,
    required this.filter,
    required this.branches,
    required this.employees,
    required this.onChanged,
  });

  final DashboardFilter filter;
  final List<BranchModel> branches;
  final List<DashboardEmployee> employees;
  final ValueChanged<DashboardFilter> onChanged;

  Future<void> _pickDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: filter.date ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('ar'),
      helpText: 'اختر اليوم',
    );
    if (picked != null) {
      onChanged(DashboardFilter(branchId: filter.branchId, employeeId: filter.employeeId, date: picked));
    }
  }

  @override
  Widget build(BuildContext context) {
    final branchEmployees = employees.where((e) => filter.branchId == 'all' || e.branchId == filter.branchId).toList();
    final branchName = branches.where((b) => b.id == filter.branchId).firstOrNull?.name;
    final employeeName = employees.where((e) => e.id == filter.employeeId).firstOrNull?.fullName;

    return AppFilterBar(
      children: [
          AppFilterPill(
            icon: Icons.event_rounded,
            label: filter.date == null ? 'اختر التاريخ' : Fmt.dateWithDay(filter.date),
            active: filter.date != null,
            onTap: () => _pickDate(context),
          ),
          AppFilterPill(
            icon: Icons.store_rounded,
            label: branchName ?? 'كل الفروع',
            active: filter.branchId != 'all',
            onTap: () async {
              final branchId = await showAppOptions(context, title: 'الفرع', current: filter.branchId, options: [('all', 'كل الفروع'), for (final b in branches) (b.id, b.name)]);
              if (branchId == null) return;
              // الموظف المختار من فرع آخر يُلغى اختياره
              final emp = employees.where((e) => e.id == filter.employeeId).firstOrNull;
              final keepEmployee = branchId == 'all' || emp == null || emp.branchId == branchId;
              onChanged(DashboardFilter(branchId: branchId, employeeId: keepEmployee ? filter.employeeId : 'all', date: filter.date));
            },
          ),
          AppFilterPill(
            icon: Icons.person_rounded,
            label: employeeName ?? 'كل الموظفين',
            active: filter.employeeId != 'all',
            onTap: () async {
              final employeeId = await showAppOptions(context, title: 'الموظف', current: filter.employeeId, options: [('all', 'كل الموظفين'), for (final e in branchEmployees) (e.id, e.fullName)]);
              if (employeeId != null) onChanged(DashboardFilter(branchId: filter.branchId, employeeId: employeeId, date: filter.date));
            },
          ),
          if (filter.isActive)
            TextButton.icon(
              onPressed: () => onChanged(const DashboardFilter()),
              icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
              label: const Text('إعادة ضبط'),
            ),
        ],
    );
  }
}

