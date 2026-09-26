// =========================================================================
// HR Pro — أوقات دوام الأفرع: الأيام، البداية والنهاية، السماحية والتذكير
// =========================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../core/routes/app_router.dart';
import '../../core/services/supabase_service.dart';
import '../shared/ui/ui.dart';

class BranchScheduleScreen extends StatefulWidget {
  const BranchScheduleScreen({super.key});

  @override
  State<BranchScheduleScreen> createState() => _BranchScheduleScreenState();
}

class _BranchScheduleScreenState extends State<BranchScheduleScreen> {
  bool _isLoading = true;
  bool _hasError = false;
  List<Map<String, dynamic>> _branches = [];


  @override
  void initState() {
    super.initState();
    _loadBranches();
  }

  Future<void> _loadBranches() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    final user = SupabaseService.currentUser;
    if (user == null) {
      if (mounted) Navigator.pop(context);
      return;
    }

    try {
      final employeeRes = await SupabaseService.client
          .from('employees')
          .select('role')
          .eq('id', user.id)
          .maybeSingle();

      if (employeeRes == null || (employeeRes['role'] != 'admin' && employeeRes['role'] != 'manager')) {
        if (mounted) Navigator.pop(context);
        return;
      }

      // جلب بيانات الأفرع وجداول العمل بالتوازي
      final results = await Future.wait([
        SupabaseService.client
            .from('branches')
            .select('id, name')
            .order('name'),
        SupabaseService.client
            .from('work_schedules')
            .select()
            .isFilter('employee_id', null)
            .isFilter('department_id', null)
            .not('branch_id', 'is', null)
      ]);

      final zones = [for (final z in results[0] as List<dynamic>) Map<String, dynamic>.from(z as Map)];
      final schedules = [for (final s in results[1] as List<dynamic>) Map<String, dynamic>.from(s as Map)];

      // دمج البيانات
      final List<Map<String, dynamic>> merged = [];
      for (final zone in zones) {
        final schedule = schedules.firstWhere(
          (s) => s['branch_id'] == zone['id'],
          orElse: () => <String, dynamic>{},
        );
        merged.add({
          'zone_id': zone['id'],
          'zone_name': zone['name'],
          'has_schedule': schedule.isNotEmpty,
          'schedule': schedule,
        });
      }

      setState(() {
        _branches = merged;
        _hasError = false;
      });
    } catch (e) {
      debugPrint('خطأ في تحميل الأفرع: $e');
      if (mounted) setState(() => _hasError = true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _editSchedule(Map<String, dynamic> branch) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _ScheduleEditor(branch: branch),
    );
    if (saved == true && mounted) {
      AppSnack.success(context, 'حُفظ جدول الدوام');
      unawaited(_loadBranches());
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> content;
    if (_isLoading && _branches.isEmpty) {
      content = const [SkeletonList(count: 3, itemHeight: 140)];
    } else if (_hasError && _branches.isEmpty) {
      content = [ErrorView(onRetry: _loadBranches)];
    } else if (_branches.isEmpty) {
      content = [
        EmptyView(
          title: 'لا توجد أفرع',
          message: 'أضف الأفرع ومواقعها أولاً، ثم حدد أوقات دوامها هنا.',
          icon: Icons.store_rounded,
          actionLabel: 'إدارة الأفرع',
          onAction: () => context.push(AppRoutes.adminBranchManagement),
        ),
      ];
    } else {
      final missing = _branches.where((b) => b['has_schedule'] != true).length;
      content = [
        if (missing > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.md),
            child: AppCard(
              tone: AppTone.warning,
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: AppColors.warning),
                  const SizedBox(width: AppSpace.md),
                  Expanded(child: Text('$missing ${missing == 1 ? 'فرع' : 'أفرع'} بدون جدول دوام — التأخير والغياب لا يُحسب لموظفيها.', style: AppText.bodySm.copyWith(color: AppColors.textPrimary))),
                ],
              ),
            ),
          ),
        for (var i = 0; i < _branches.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.md),
            child: FadeSlideIn(index: i, child: _branchCard(_branches[i])),
          ),
      ];
    }

    return AppPage(
      title: 'أوقات الدوام',
      onRefresh: _loadBranches,
      actions: [
        IconButton(
          icon: const Icon(Icons.map_rounded),
          tooltip: 'مواقع الأفرع',
          onPressed: () => context.push(AppRoutes.adminBranchManagement),
        ),
      ],
      slivers: [SliverList.list(children: content)],
    );
  }

  Widget _branchCard(Map<String, dynamic> branch) {
    final hasSchedule = branch['has_schedule'] == true;
    final schedule = branch['schedule'] as Map<String, dynamic>;
    final days = [for (final d in (schedule['work_days'] as List<dynamic>? ?? const [])) (d as num).toInt()];
    return AppCard(
      onTap: () => _editSchedule(branch),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ToneIcon(hasSchedule ? Icons.store_rounded : Icons.schedule_rounded, tone: hasSchedule ? AppTone.success : AppTone.warning),
              const SizedBox(width: AppSpace.md),
              Expanded(child: Text((branch['zone_name'] ?? 'فرع').toString(), style: AppText.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis)),
              if (hasSchedule)
                const StatusBadge('مُعدّ', tone: AppTone.success, dot: true)
              else
                AppButton(label: 'إعداد', icon: Icons.add_rounded, size: AppButtonSize.small, onPressed: () => _editSchedule(branch)),
            ],
          ),
          if (hasSchedule) ...[
            const SizedBox(height: AppSpace.md),
            Wrap(
              spacing: AppSpace.lg,
              runSpacing: AppSpace.xs,
              children: [
                _Info(Icons.login_rounded, 'الدخول', Fmt.timeOfDay(schedule['check_in_time']?.toString())),
                _Info(Icons.logout_rounded, 'الخروج', Fmt.timeOfDay(schedule['check_out_time']?.toString())),
                _Info(Icons.timer_outlined, 'السماحية', '${schedule['grace_period_minutes'] ?? 15} د'),
                _Info(Icons.notifications_active_outlined, 'التذكير بعد', '${schedule['reminder_minutes_after'] ?? 5} د'),
              ],
            ),
            const SizedBox(height: AppSpace.md),
            _DaysRow(days: days),
          ],
        ],
      ),
    );
  }
}

class _Info extends StatelessWidget {
  const _Info(this.icon, this.label, this.value);
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.textMuted),
          const SizedBox(width: AppSpace.xs),
          Text('$label ', style: AppText.caption),
          Text(value, style: AppText.bodySm.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
        ],
      );
}

/// أيام الأسبوع (0 = الأحد ... 6 = السبت) كدوائر صغيرة.
class _DaysRow extends StatelessWidget {
  const _DaysRow({required this.days});
  final List<int> days;
  static const _short = ['أحد', 'اثنين', 'ثلاثاء', 'أربعاء', 'خميس', 'جمعة', 'سبت'];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpace.xs,
      runSpacing: AppSpace.xs,
      children: [
        for (var d = 0; d < 7; d++)
          StatusBadge(_short[d], tone: days.contains(d) ? AppTone.brand : AppTone.neutral),
      ],
    );
  }
}

/// نافذة تعديل جدول دوام فرع.
class _ScheduleEditor extends StatefulWidget {
  const _ScheduleEditor({required this.branch});
  final Map<String, dynamic> branch;

  @override
  State<_ScheduleEditor> createState() => _ScheduleEditorState();
}

class _ScheduleEditorState extends State<_ScheduleEditor> {
  static const _dayNames = ['الأحد', 'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'];

  late final Map<String, dynamic> _schedule = widget.branch['schedule'] as Map<String, dynamic>;
  late final bool _hasSchedule = widget.branch['has_schedule'] == true;
  late final List<int> _workDays = _hasSchedule
      ? [for (final d in (_schedule['work_days'] as List<dynamic>? ?? const [0, 1, 2, 3, 4, 6])) (d as num).toInt()]
      : [0, 1, 2, 3, 4, 6]; // كل الأيام ما عدا الجمعة (5)
  late TimeOfDay _start = _parse(_schedule['check_in_time']?.toString(), const TimeOfDay(hour: 8, minute: 0));
  late TimeOfDay _end = _parse(_schedule['check_out_time']?.toString(), const TimeOfDay(hour: 16, minute: 0));
  late int _grace = (_schedule['grace_period_minutes'] as num? ?? 15).toInt();
  late int _reminder = (_schedule['reminder_minutes_after'] as num? ?? 5).toInt();
  bool _saving = false;

  static TimeOfDay _parse(String? s, TimeOfDay fallback) {
    final p = s?.split(':');
    if (p == null || p.length < 2) return fallback;
    return TimeOfDay(hour: int.tryParse(p[0]) ?? fallback.hour, minute: int.tryParse(p[1]) ?? fallback.minute);
  }

  static String _db(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';
  static String _label(TimeOfDay t) => Fmt.time(DateTime(2000, 1, 1, t.hour, t.minute));

  int get _minutes => (_end.hour * 60 + _end.minute) - (_start.hour * 60 + _start.minute);

  Future<void> _pick(bool start) async {
    final picked = await showTimePicker(context: context, initialTime: start ? _start : _end, helpText: start ? 'بداية الدوام' : 'نهاية الدوام');
    if (picked != null) setState(() => start ? _start = picked : _end = picked);
  }

  Future<void> _save() async {
    if (_minutes <= 0) {
      AppSnack.error(context, 'وقت البداية لازم يكون قبل وقت النهاية');
      return;
    }
    if (_workDays.isEmpty) {
      AppSnack.error(context, 'اختر يوم عمل واحد على الأقل');
      return;
    }
    setState(() => _saving = true);
    try {
      final data = {
        'branch_id': widget.branch['zone_id'],
        'name': 'دوام فرع ${widget.branch['zone_name']}',
        'work_days': _workDays..sort(),
        'check_in_time': _db(_start),
        'check_out_time': _db(_end),
        'grace_period_minutes': _grace,
        'reminder_minutes_after': _reminder,
      };
      Future<void> write(Map<String, dynamic> row) => _hasSchedule
          ? SupabaseService.client.from('work_schedules').update(row).eq('id', _schedule['id'] as Object)
          : SupabaseService.client.from('work_schedules').insert(row);
      try {
        await write(data);
      } on PostgrestException catch (e) {
        // قاعدة بيانات قديمة بدون عمود التذكير (قبل migration 20260926000000): نحفظ الباقي
        if (!e.message.contains('reminder_minutes_after')) rethrow;
        await write(Map.of(data)..remove('reminder_minutes_after'));
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint('خطأ في حفظ الجدول: $e');
      if (mounted) {
        AppSnack.error(context, 'تعذّر الحفظ: $e');
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hours = _minutes > 0 ? '${_minutes ~/ 60} س${_minutes % 60 > 0 ? ' ${_minutes % 60} د' : ''}' : '—';
    return Padding(
      padding: EdgeInsets.fromLTRB(AppSpace.xl, 0, AppSpace.xl, AppSpace.xl + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('دوام ${widget.branch['zone_name']}', style: AppText.title),
            Text(_hasSchedule ? 'تعديل الجدول الحالي' : 'جدول جديد', style: AppText.caption),
            const SizedBox(height: AppSpace.lg),
            Text('أيام العمل', style: AppText.bodySm.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: AppSpace.sm),
            Wrap(
              spacing: AppSpace.sm,
              children: [
                for (var d = 0; d < 7; d++)
                  FilterChip(
                    label: Text(_dayNames[d]),
                    selected: _workDays.contains(d),
                    showCheckmark: false,
                    selectedColor: AppColors.brandContainer,
                    labelStyle: AppText.bodySm.copyWith(
                      color: _workDays.contains(d) ? AppColors.onBrandContainer : AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                    onSelected: (on) {
                      AppHaptics.select();
                      setState(() => on ? _workDays.add(d) : _workDays.remove(d));
                    },
                  ),
              ],
            ),
            const SizedBox(height: AppSpace.lg),
            Row(
              children: [
                Expanded(child: AppPickerField(label: 'بداية الدوام', value: _label(_start), icon: Icons.login_rounded, onTap: () => _pick(true))),
                const SizedBox(width: AppSpace.md),
                Expanded(child: AppPickerField(label: 'نهاية الدوام', value: _label(_end), icon: Icons.logout_rounded, onTap: () => _pick(false))),
              ],
            ),
            const SizedBox(height: AppSpace.sm),
            Text('مدة الدوام: $hours', style: AppText.caption.copyWith(color: _minutes > 0 ? AppColors.textMuted : AppColors.danger)),
            const SizedBox(height: AppSpace.lg),
            AppChoiceChips<int>(
              label: 'سماحية التأخير',
              scrollable: true,
              value: _grace,
              options: [for (final m in const [0, 5, 10, 15, 20, 30]) (m, m == 0 ? 'بدون' : '$m د', null)],
              onChanged: (v) => setState(() => _grace = v),
            ),
            const SizedBox(height: AppSpace.md),
            AppChoiceChips<int>(
              label: 'تذكير البصمة بعد',
              scrollable: true,
              value: _reminder,
              options: [for (final m in const [5, 10, 15, 30]) (m, '$m د', null)],
              onChanged: (v) => setState(() => _reminder = v),
            ),
            const SizedBox(height: AppSpace.xs),
            const Text('يوصل للموظف إشعار إذا ما بصم بعد بداية أو نهاية الدوام بهذه المدة.', style: AppText.caption),
            const SizedBox(height: AppSpace.xl),
            AppButton(label: 'حفظ الجدول', icon: Icons.check_rounded, size: AppButtonSize.large, expand: true, loading: _saving, onPressed: _save),
          ],
        ),
      ),
    );
  }
}
