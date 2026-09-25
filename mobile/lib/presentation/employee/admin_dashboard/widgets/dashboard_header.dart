import 'package:flutter/material.dart';

import '../../../../core/models/models.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/arabic_format.dart';
import '../../../../data/repositories/admin_dashboard_repository.dart';
import '../../../shared/widgets/glass_container.dart';

/// الإحصائيات الأفقية: حاضر، غائب، مخالفات.
class DashboardStatsRow extends StatelessWidget {
  const DashboardStatsRow({super.key, required this.present, required this.absent, required this.violations});

  final int present;
  final int absent;
  final int violations;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)))),
      child: Row(
        children: [
          Expanded(child: _StatCard('حاضر اليوم', '$present', AppTheme.successGreen, Icons.done_all_rounded)),
          const SizedBox(width: 8),
          Expanded(child: _StatCard('غائب اليوم', '$absent', AppTheme.dangerRed, Icons.close_rounded)),
          const SizedBox(width: 8),
          Expanded(child: _StatCard('مخالفات أمنية', '$violations', AppTheme.warningOrange, Icons.security_rounded)),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard(this.title, this.value, this.color, this.icon);

  final String title;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      borderRadius: 14,
      opacity: 0.12,
      borderColor: color.withValues(alpha: 0.35),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 8.5, color: Colors.white60, fontFamily: 'Cairo'),
                ),
                const SizedBox(height: 2),
                Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// فلاتر اللوحة: الفرع، الموظف، التاريخ، وزر إعادة الضبط.
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

  static const _textStyle = TextStyle(fontFamily: 'Cairo', color: Colors.white, fontSize: 11);

  BoxDecoration _box(Color color) => BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      );

  Widget _dropdown({
    required String value,
    required Color color,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String> onSelect,
  }) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: _box(color),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          // قيمة غير موجودة في القائمة (فرع/موظف محذوف) تُعرض كـ "الكل"
          value: items.any((i) => i.value == value) ? value : 'all',
          isExpanded: true,
          dropdownColor: const Color(0xFF1A1F3A),
          icon: Icon(Icons.arrow_drop_down_rounded, color: color),
          style: _textStyle,
          items: items,
          onChanged: (v) => onSelect(v ?? 'all'),
        ),
      ),
    );
  }

  Future<void> _pickDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: filter.date ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('ar'),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(primary: AppTheme.neonCyan, surface: Color(0xFF1A1F3A)),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      onChanged(DashboardFilter(branchId: filter.branchId, employeeId: filter.employeeId, date: picked));
    }
  }

  @override
  Widget build(BuildContext context) {
    final branchEmployees = employees.where((e) => filter.branchId == 'all' || e.branchId == filter.branchId);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: _dropdown(
                  value: filter.branchId,
                  color: AppTheme.neonCyan,
                  items: [
                    const DropdownMenuItem(value: 'all', child: Text('جميع الفروع')),
                    for (final b in branches) DropdownMenuItem(value: b.id, child: Text(b.name)),
                  ],
                  onSelect: (branchId) {
                    // الموظف المختار من فرع آخر يُلغى اختياره
                    final emp = employees.where((e) => e.id == filter.employeeId).firstOrNull;
                    final keepEmployee = branchId == 'all' || emp == null || emp.branchId == branchId;
                    onChanged(DashboardFilter(
                      branchId: branchId,
                      employeeId: keepEmployee ? filter.employeeId : 'all',
                      date: filter.date,
                    ));
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _dropdown(
                  value: filter.employeeId,
                  color: AppTheme.successGreen,
                  items: [
                    const DropdownMenuItem(value: 'all', child: Text('جميع الموظفين')),
                    for (final e in branchEmployees) DropdownMenuItem(value: e.id, child: Text(e.fullName)),
                  ],
                  onSelect: (employeeId) =>
                      onChanged(DashboardFilter(branchId: filter.branchId, employeeId: employeeId, date: filter.date)),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => _pickDate(context),
                  child: Container(
                    height: 34,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: _box(AppTheme.warningOrange),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(filter.date == null ? 'تصفية حسب التاريخ' : formatDateSlash(filter.date!), style: _textStyle),
                        Icon(
                          filter.date == null ? Icons.calendar_today_rounded : Icons.edit_calendar_rounded,
                          color: AppTheme.warningOrange,
                          size: 14,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (filter.isActive) ...[
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => onChanged(const DashboardFilter()),
                  child: Container(
                    height: 34,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: AppTheme.dangerRed.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.dangerRed.withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.filter_alt_off_rounded, color: Colors.white, size: 14),
                        SizedBox(width: 4),
                        Text(
                          'إعادة ضبط',
                          style: TextStyle(fontFamily: 'Cairo', color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
