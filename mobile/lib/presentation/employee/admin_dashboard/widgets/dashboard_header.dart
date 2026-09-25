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

  Future<String?> _pick(BuildContext context, String title, List<(String id, String label)> options, String current) {
    return showAppSheet<String>(
      context,
      title: title,
      builder: (ctx) => _SearchableOptions(options: options, current: current),
    );
  }

  @override
  Widget build(BuildContext context) {
    final branchEmployees = employees.where((e) => filter.branchId == 'all' || e.branchId == filter.branchId).toList();
    final branchName = branches.where((b) => b.id == filter.branchId).firstOrNull?.name;
    final employeeName = employees.where((e) => e.id == filter.employeeId).firstOrNull?.fullName;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.page),
      child: Row(
        children: [
          _FilterPill(
            icon: Icons.event_rounded,
            label: filter.date == null ? 'اختر التاريخ' : Fmt.dateWithDay(filter.date),
            active: filter.date != null,
            onTap: () => _pickDate(context),
          ),
          _FilterPill(
            icon: Icons.store_rounded,
            label: branchName ?? 'كل الفروع',
            active: filter.branchId != 'all',
            onTap: () async {
              final branchId = await _pick(context, 'الفرع', [('all', 'كل الفروع'), for (final b in branches) (b.id, b.name)], filter.branchId);
              if (branchId == null) return;
              // الموظف المختار من فرع آخر يُلغى اختياره
              final emp = employees.where((e) => e.id == filter.employeeId).firstOrNull;
              final keepEmployee = branchId == 'all' || emp == null || emp.branchId == branchId;
              onChanged(DashboardFilter(branchId: branchId, employeeId: keepEmployee ? filter.employeeId : 'all', date: filter.date));
            },
          ),
          _FilterPill(
            icon: Icons.person_rounded,
            label: employeeName ?? 'كل الموظفين',
            active: filter.employeeId != 'all',
            onTap: () async {
              final employeeId = await _pick(
                context,
                'الموظف',
                [('all', 'كل الموظفين'), for (final e in branchEmployees) (e.id, e.fullName)],
                filter.employeeId,
              );
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
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({required this.icon, required this.label, required this.active, required this.onTap});

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: AppSpace.sm),
      child: ActionChip(
        avatar: Icon(icon, size: 16, color: active ? AppColors.onBrandContainer : AppColors.textSecondary),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(constraints: const BoxConstraints(maxWidth: 160), child: Text(label, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 2),
            Icon(Icons.expand_more_rounded, size: 16, color: active ? AppColors.onBrandContainer : AppColors.textMuted),
          ],
        ),
        labelStyle: AppText.bodySm.copyWith(color: active ? AppColors.onBrandContainer : AppColors.textPrimary, fontWeight: FontWeight.w700),
        backgroundColor: active ? AppColors.brandContainer : AppColors.surface2,
        side: BorderSide(color: active ? AppColors.brand.withValues(alpha: 0.5) : AppColors.border),
        onPressed: onTap,
      ),
    );
  }
}

/// قائمة اختيار مع بحث (للموظفين والفروع).
class _SearchableOptions extends StatefulWidget {
  const _SearchableOptions({required this.options, required this.current});
  final List<(String id, String label)> options;
  final String current;

  @override
  State<_SearchableOptions> createState() => _SearchableOptionsState();
}

class _SearchableOptionsState extends State<_SearchableOptions> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final items = widget.options.where((o) => _q.isEmpty || o.$2.contains(_q)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.options.length > 8) ...[
          TextField(
            decoration: const InputDecoration(hintText: 'بحث', prefixIcon: Icon(Icons.search_rounded)),
            onChanged: (v) => setState(() => _q = v.trim()),
          ),
          const SizedBox(height: AppSpace.sm),
        ],
        for (final o in items)
          AppListTile(
            dense: true,
            title: o.$2,
            trailing: o.$1 == widget.current ? const Icon(Icons.check_rounded, color: AppColors.brand) : null,
            onTap: () => Navigator.pop(context, o.$1),
          ),
      ],
    );
  }
}
