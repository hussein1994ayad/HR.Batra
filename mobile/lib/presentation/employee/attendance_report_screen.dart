// =========================================================================
// HR Pro — تقارير الحضور
// =========================================================================
// فلاتر (الفترة، الفرع، الموظف، الحالة)، مؤشرات سريعة، وسجل لكل موظف مع
// فتح موقع البصمة على الخريطة وتعديل الأوقات. الموظف بلا سجل = غائب.
// =========================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/services/supabase_service.dart';
import '../shared/ui/ui.dart';

class AttendanceReportScreen extends StatefulWidget {
  const AttendanceReportScreen({super.key});

  @override
  State<AttendanceReportScreen> createState() => _AttendanceReportScreenState();
}

class _AttendanceReportScreenState extends State<AttendanceReportScreen> {
  bool _isLoading = true;
  bool _hasError = false;
  DateTimeRange _selectedDateRange = DateTimeRange(start: DateTime.now(), end: DateTime.now());

  String? _selectedBranchId = 'all';
  String? _selectedEmployeeId = 'all';
  String _statusFilter = 'all';

  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _employeesList = [];
  List<Map<String, dynamic>> _records = [];

  static const _absent = 'غائب';

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    final user = SupabaseService.currentUser;
    if (user == null) {
      if (mounted) Navigator.pop(context);
      return;
    }

    try {
      final employeeRes = await SupabaseService.client.from('employees').select('role').eq('id', user.id).maybeSingle();

      if (employeeRes == null || (employeeRes['role'] != 'admin' && employeeRes['role'] != 'manager')) {
        if (mounted) Navigator.pop(context);
        return;
      }

      final results = await Future.wait<dynamic>([
        SupabaseService.client.from('branches').select('id, name').order('name'),
        SupabaseService.client.from('employees').select('id, full_name, employee_code, branch_id, is_active').order('full_name'),
      ]);
      if (mounted) {
        _branches = List<Map<String, dynamic>>.from(results[0] as Iterable<dynamic>);
        _employeesList = List<Map<String, dynamic>>.from(results[1] as Iterable<dynamic>);
      }
    } catch (e) {
      debugPrint('Error loading branches/employees: $e');
    }
    unawaited(_loadRecords());
  }

  Future<void> _loadRecords() async {
    setState(() => _isLoading = true);
    try {
      final startStr = _selectedDateRange.start.toIso8601String().split('T')[0];
      final endStr = _selectedDateRange.end.toIso8601String().split('T')[0];

      var query = SupabaseService.client
          .from('attendance')
          .select('id, check_in_time, check_out_time, check_in_lat, check_in_lng, check_out_lat, check_out_lng, status, work_date, employees!inner(id, full_name, employee_code, branch_id)')
          .gte('work_date', startStr)
          .lte('work_date', endStr);

      if (_selectedEmployeeId != null && _selectedEmployeeId != 'all') {
        query = query.eq('employee_id', _selectedEmployeeId!);
      }
      if (_selectedBranchId != null && _selectedBranchId != 'all') {
        query = query.eq('employees.branch_id', _selectedBranchId!);
      }

      final data = await query.order('work_date', ascending: false).order('check_in_time', ascending: false).limit(300);
      final List<Map<String, dynamic>> processed = [];
      final Set<String> employeesWithRecords = {};

      for (final record in data) {
        final emp = record['employees'];
        if (emp is! Map) continue;
        employeesWithRecords.add(emp['id'].toString());
        final status = switch (record['status']) {
          'late' => 'تأخير',
          'absent' => _absent,
          'half_day' => 'نصف يوم',
          _ => 'حاضر',
        };
        processed.add({
          'id': record['id'],
          'employee_name': emp['full_name'],
          'employee_code': emp['employee_code'],
          'check_in': record['check_in_time'],
          'check_out': record['check_out_time'],
          'check_in_lat': record['check_in_lat'],
          'check_in_lng': record['check_in_lng'],
          'check_out_lat': record['check_out_lat'],
          'check_out_lng': record['check_out_lng'],
          'work_date': record['work_date'],
          'status': status,
        });
      }

      // الموظف النشط بلا أي سجل في الفترة = غائب
      for (final emp in _employeesList) {
        if (emp['is_active'] == false) continue;
        if (_selectedEmployeeId != null && _selectedEmployeeId != 'all' && emp['id'] != _selectedEmployeeId) continue;
        if (_selectedBranchId != null && _selectedBranchId != 'all' && emp['branch_id'] != _selectedBranchId) continue;
        if (!employeesWithRecords.contains(emp['id'].toString())) {
          processed.add({
            'id': 'virtual_${emp['id']}',
            'employee_name': emp['full_name'],
            'employee_code': emp['employee_code'] ?? '',
            'work_date': endStr,
            'status': _absent,
          });
        }
      }

      processed.sort((a, b) {
        if (a['status'] == _absent && b['status'] != _absent) return 1;
        if (a['status'] != _absent && b['status'] == _absent) return -1;
        return (a['employee_name'] ?? '').toString().compareTo((b['employee_name'] ?? '').toString());
      });

      if (mounted) {
        setState(() {
          _records = processed;
          _hasError = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading attendance: $e');
      if (mounted) setState(() => _hasError = true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: _selectedDateRange,
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
      helpText: 'اختر الفترة',
    );
    if (picked != null) {
      setState(() => _selectedDateRange = picked);
      unawaited(_loadRecords());
    }
  }

  Future<void> _pickBranch() async {
    final id = await showAppOptions(
      context,
      title: 'الفرع',
      current: _selectedBranchId,
      options: [('all', 'كل الفروع'), for (final b in _branches) (b['id'] as String, b['name'].toString())],
    );
    if (id == null) return;
    setState(() {
      _selectedBranchId = id;
      // الموظف المختار من فرع آخر يُلغى اختياره
      if (_selectedEmployeeId != 'all') {
        final emp = _employeesList.where((e) => e['id'] == _selectedEmployeeId).firstOrNull;
        if (emp != null && id != 'all' && emp['branch_id'] != id) _selectedEmployeeId = 'all';
      }
    });
    unawaited(_loadRecords());
  }

  Future<void> _pickEmployee() async {
    final list = _employeesList.where((e) => _selectedBranchId == 'all' || e['branch_id'] == _selectedBranchId);
    final id = await showAppOptions(
      context,
      title: 'الموظف',
      current: _selectedEmployeeId,
      options: [('all', 'كل الموظفين'), for (final e in list) (e['id'] as String, e['full_name'].toString())],
    );
    if (id == null) return;
    setState(() => _selectedEmployeeId = id);
    unawaited(_loadRecords());
  }

  Future<void> _openMap(Object? lat, Object? lng) async {
    if (lat is! num || lng is! num) {
      AppSnack.info(context, 'لا توجد إحداثيات لهذه البصمة');
      return;
    }
    final url = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) AppSnack.error(context, 'تعذّر فتح الخرائط');
    }
  }

  static TimeOfDay? _timeOf(Object? v) {
    if (v == null) return null;
    final dt = DateTime.tryParse(v.toString())?.toLocal();
    if (dt != null) return TimeOfDay(hour: dt.hour, minute: dt.minute);
    final p = v.toString().split(':');
    if (p.length < 2) return null;
    final h = int.tryParse(p[0]);
    final m = int.tryParse(p[1]);
    return h == null || m == null ? null : TimeOfDay(hour: h, minute: m);
  }

  Future<void> _editTimeDialog(Map<String, dynamic> record) async {
    TimeOfDay? newCheckIn = _timeOf(record['check_in']);
    TimeOfDay? newCheckOut = _timeOf(record['check_out']);
    String label(TimeOfDay? t) => t == null ? 'لم يُحدد' : Fmt.time(DateTime(2000, 1, 1, t.hour, t.minute));

    final save = await showAppSheet<bool>(
      context,
      title: 'تعديل أوقات ${record['employee_name']}',
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('يوم ${Fmt.dateWithDay(DateTime.tryParse(record['work_date'].toString()))}', style: AppText.bodySm),
            const SizedBox(height: AppSpace.md),
            Row(
              children: [
                Expanded(
                  child: AppPickerField(
                    label: 'الحضور',
                    icon: Icons.login_rounded,
                    value: label(newCheckIn),
                    onTap: () async {
                      final t = await showTimePicker(context: ctx, initialTime: newCheckIn ?? const TimeOfDay(hour: 8, minute: 0));
                      if (t != null) setSheet(() => newCheckIn = t);
                    },
                  ),
                ),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: AppPickerField(
                    label: 'الانصراف',
                    icon: Icons.logout_rounded,
                    value: label(newCheckOut),
                    onTap: () async {
                      final t = await showTimePicker(context: ctx, initialTime: newCheckOut ?? const TimeOfDay(hour: 16, minute: 0));
                      if (t != null) setSheet(() => newCheckOut = t);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.xl),
            AppButton(label: 'حفظ', icon: Icons.check_rounded, expand: true, onPressed: () => Navigator.pop(ctx, true)),
          ],
        ),
      ),
    );
    if (save == true) {
      unawaited(_saveEditedTime(record['id'] as String, record['work_date'] as String, newCheckIn, newCheckOut));
    }
  }

  Future<void> _saveEditedTime(String recordId, String workDateStr, TimeOfDay? checkIn, TimeOfDay? checkOut) async {
    setState(() => _isLoading = true);
    try {
      final Map<String, dynamic> updates = {};
      final dt = DateTime.parse(workDateStr);
      if (checkIn != null) {
        updates['check_in_time'] = DateTime(dt.year, dt.month, dt.day, checkIn.hour, checkIn.minute).toUtc().toIso8601String();
      }
      if (checkOut != null) {
        updates['check_out_time'] = DateTime(dt.year, dt.month, dt.day, checkOut.hour, checkOut.minute).toUtc().toIso8601String();
      }

      if (updates.isNotEmpty) {
        await SupabaseService.client.from('attendance').update(updates).eq('id', recordId);
        if (mounted) {
          AppSnack.success(context, 'حُدّثت الأوقات');
          unawaited(_loadRecords());
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Error updating time: $e');
      if (mounted) {
        AppSnack.error(context, 'تعذّر التحديث');
        setState(() => _isLoading = false);
      }
    }
  }

  String get _rangeLabel {
    final s = _selectedDateRange.start;
    final e = _selectedDateRange.end;
    final today = DateTime.now();
    if (DateUtils.isSameDay(s, e)) return DateUtils.isSameDay(s, today) ? 'اليوم' : Fmt.date(s);
    return '${Fmt.date(s)} - ${Fmt.date(e)}';
  }

  @override
  Widget build(BuildContext context) {
    final present = _records.where((r) => r['status'] == 'حاضر').length;
    final late = _records.where((r) => r['status'] == 'تأخير').length;
    final absent = _records.where((r) => r['status'] == _absent).length;
    final rate = _records.isEmpty ? 0 : ((_records.length - absent) / _records.length * 100).round();
    final visible = _statusFilter == 'all' ? _records : _records.where((r) => r['status'] == _statusFilter).toList();
    final branchName = _branches.where((b) => b['id'] == _selectedBranchId).firstOrNull?['name']?.toString();
    final employeeName = _employeesList.where((e) => e['id'] == _selectedEmployeeId).firstOrNull?['full_name']?.toString();

    final List<Widget> list;
    if (_isLoading && _records.isEmpty) {
      list = const [SkeletonList(itemHeight: 96)];
    } else if (_hasError && _records.isEmpty) {
      list = [ErrorView(onRetry: _loadRecords)];
    } else if (visible.isEmpty) {
      list = const [EmptyView(title: 'لا توجد سجلات', message: 'غيّر الفترة أو الفلاتر.', icon: Icons.event_busy_rounded, compact: true)];
    } else {
      list = [
        for (var i = 0; i < visible.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: FadeSlideIn(index: i, child: _recordCard(visible[i])),
          ),
      ];
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('تقارير الحضور'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: AppFilterBar(
              children: [
                AppFilterPill(icon: Icons.date_range_rounded, label: _rangeLabel, active: true, onTap: _selectDateRange),
                AppFilterPill(icon: Icons.store_rounded, label: branchName ?? 'كل الفروع', active: _selectedBranchId != 'all', onTap: _pickBranch),
                AppFilterPill(icon: Icons.person_rounded, label: employeeName ?? 'كل الموظفين', active: _selectedEmployeeId != 'all', onTap: _pickEmployee),
              ],
            ),
          ),
        ),
      ),
      body: RefreshIndicator.adaptive(
        onRefresh: _loadRecords,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpace.page, AppSpace.md, AppSpace.page, AppSpace.x4),
          children: [
            ContentWidth(
              maxWidth: 1000,
              child: ResponsiveGrid(
                minItemWidth: 120,
                children: [
                  KpiTile(label: 'حاضر', value: present, icon: Icons.how_to_reg_rounded, tone: AppTone.success),
                  KpiTile(label: 'متأخر', value: late, icon: Icons.schedule_rounded, tone: AppTone.warning),
                  KpiTile(label: 'غائب', value: absent, icon: Icons.person_off_rounded, tone: AppTone.danger),
                  KpiTile(label: 'نسبة الحضور', value: rate, icon: Icons.percent_rounded, format: (v) => '${v.round()}%'),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            AppChoiceChips<String>(
              scrollable: true,
              value: _statusFilter,
              onChanged: (v) => setState(() => _statusFilter = v),
              options: const [('all', 'الكل', null), ('حاضر', 'حاضر', null), ('تأخير', 'متأخر', null), ('نصف يوم', 'نصف يوم', null), (_absent, 'غائب', null)],
            ),
            const SizedBox(height: AppSpace.md),
            for (final w in list) ContentWidth(child: w),
          ],
        ),
      ),
    );
  }

  Widget _recordCard(Map<String, dynamic> r) {
    final status = r['status'].toString();
    final isAbsent = status == _absent;
    final tone = switch (status) {
      'حاضر' => AppTone.success,
      'تأخير' => AppTone.warning,
      'نصف يوم' => AppTone.info,
      _ => AppTone.danger,
    };
    final checkIn = DateTime.tryParse(r['check_in']?.toString() ?? '');
    final checkOut = DateTime.tryParse(r['check_out']?.toString() ?? '');
    final name = (r['employee_name'] ?? 'موظف').toString();

    return AppCard(
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AppAvatar(name: name, size: 40, tone: tone),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: AppText.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(
                      '${(r['employee_code'] ?? '').toString().isEmpty ? '' : '${r['employee_code']} · '}${Fmt.dateWithDay(DateTime.tryParse(r['work_date']?.toString() ?? ''))}',
                      style: AppText.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              StatusBadge(status, tone: tone, dot: true),
            ],
          ),
          if (!isAbsent) ...[
            const SizedBox(height: AppSpace.sm),
            Row(
              children: [
                Expanded(child: _TimeButton(icon: Icons.login_rounded, label: 'حضور', time: checkIn, onMap: () => _openMap(r['check_in_lat'], r['check_in_lng']))),
                const SizedBox(width: AppSpace.sm),
                Expanded(child: _TimeButton(icon: Icons.logout_rounded, label: 'انصراف', time: checkOut, onMap: () => _openMap(r['check_out_lat'], r['check_out_lng']))),
                IconButton(tooltip: 'تعديل الأوقات', icon: const Icon(Icons.edit_calendar_rounded, color: AppColors.brand), onPressed: () => _editTimeDialog(r)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// وقت البصمة مع زر لفتح موقعها على الخريطة.
class _TimeButton extends StatelessWidget {
  const _TimeButton({required this.icon, required this.label, required this.time, required this.onMap});
  final IconData icon;
  final String label;
  final DateTime? time;
  final VoidCallback onMap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: time != null,
      label: '$label ${time == null ? 'غير مسجل' : Fmt.time(time)}',
      child: InkWell(
        onTap: time == null ? null : onMap,
        borderRadius: AppRadius.control,
        child: Container(
          constraints: const BoxConstraints(minHeight: AppSpace.touch),
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
          decoration: const BoxDecoration(color: AppColors.surface2, borderRadius: AppRadius.control),
          child: ExcludeSemantics(
            child: Row(
              children: [
                Icon(icon, size: 16, color: AppColors.textMuted),
                const SizedBox(width: AppSpace.xs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(label, style: AppText.overline),
                      Text(time == null ? '--:--' : Fmt.time(time), style: AppText.bodySm.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                if (time != null) const Icon(Icons.place_outlined, size: 16, color: AppColors.brand),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
