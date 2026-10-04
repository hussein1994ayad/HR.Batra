// =========================================================================
// HR Pro — تقارير الحضور
// =========================================================================
// فلاتر (الفترة، الفرع، الموظف، الحالة)، مؤشرات سريعة، وسجل يوم بيوم لكل موظف:
// حاضر / متأخر / خروج مبكر / غائب / مجاز (مع نوع الإجازة). فتح موقع البصمة على
// الخريطة، تعديل الأوقات، وتصدير الفترة إلى Excel مرتباً يوماً بيوم.
// =========================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/logic/attendance_report.dart';
import '../../core/models/models.dart';
import '../../core/services/excel_export_service.dart';
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
  bool _exporting = false;
  DateTimeRange _selectedDateRange = DateTimeRange(start: DateTime.now(), end: DateTime.now());

  String? _selectedBranchId = 'all';
  String? _selectedEmployeeId = 'all';
  ReportStatus? _statusFilter;

  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _employeesList = [];
  List<WorkScheduleModel> _schedules = [];
  Map<String, String> _leaveTypeNames = {};
  List<ReportRow> _rows = [];

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
        SupabaseService.client
            .from('employees')
            .select('id, full_name, employee_code, branch_id, department_id, join_date, is_active')
            .order('full_name'),
        SupabaseService.client.from('work_schedules').select(),
        SupabaseService.client.from('system_settings').select('value').eq('key', 'leave_policy').maybeSingle(),
      ]);
      if (mounted) {
        _branches = List<Map<String, dynamic>>.from(results[0] as Iterable<dynamic>);
        _employeesList = List<Map<String, dynamic>>.from(results[1] as Iterable<dynamic>);
        _schedules = rowsOf(results[2]).map(WorkScheduleModel.fromMap).toList();
        final types = rowOf(results[3])?['value'] is Map ? (rowOf(results[3])!['value'] as Map)['active_types'] : null;
        _leaveTypeNames = {
          if (types is List)
            for (final t in types)
              if (t is Map && t['id'] != null) t['id'].toString(): 'إجازة ${t['name'].toString().replaceFirst(RegExp(r'^إجازة\s*'), '')}',
        };
      }
    } catch (e) {
      debugPrint('Error loading report lookups: $e');
    }
    unawaited(_loadRecords());
  }

  String _branchName(String? id) => _branches.where((b) => b['id'] == id).firstOrNull?['name']?.toString() ?? '';

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
  static String _iso(DateTime d) => d.toIso8601String().split('T')[0];

  Future<void> _loadRecords() async {
    setState(() => _isLoading = true);
    try {
      final from = _day(_selectedDateRange.start);
      final to = _day(_selectedDateRange.end);

      final employees = [
        for (final e in _employeesList)
          if (e['is_active'] != false &&
              (_selectedEmployeeId == 'all' || e['id'] == _selectedEmployeeId) &&
              (_selectedBranchId == 'all' || e['branch_id'] == _selectedBranchId))
            ReportEmployee(
              id: e['id'].toString(),
              name: (e['full_name'] ?? 'موظف').toString(),
              code: (e['employee_code'] ?? '').toString(),
              branchId: e['branch_id']?.toString(),
              departmentId: e['department_id']?.toString(),
              branchName: _branchName(e['branch_id']?.toString()),
              joinDate: DateTime.tryParse((e['join_date'] ?? '').toString()),
            ),
      ];
      final ids = employees.isEmpty ? ['00000000-0000-0000-0000-000000000000'] : [for (final e in employees) e.id];

      // الصفحات تضمن جلب كل السجلات حتى لو تجاوزت حدّ 1000 سطر لكل طلب
      final attendanceRows = <Map<String, dynamic>>[];
      for (var offset = 0;; offset += 1000) {
        final page = await SupabaseService.client
            .from('attendance')
            .select('id, employee_id, check_in_time, check_out_time, check_in_lat, check_in_lng, check_out_lat, check_out_lng, status, work_date')
            .inFilter('employee_id', ids)
            .gte('work_date', _iso(from))
            .lte('work_date', _iso(to))
            .order('work_date')
            .range(offset, offset + 999);
        attendanceRows.addAll(rowsOf(page));
        if (page.length < 1000) break;
      }

      final leaveRows = rowsOf(await SupabaseService.client
          .from('leave_requests')
          .select('employee_id, start_date, end_date, leave_type, is_hourly, is_paid, start_hour, end_hour')
          .eq('status', 'approved')
          .inFilter('employee_id', ids)
          .lte('start_date', DateTime(to.year, to.month, to.day, 23, 59, 59).toUtc().toIso8601String())
          .gte('end_date', from.toUtc().toIso8601String()));

      final holidayRows = rowsOf(await SupabaseService.client
          .from('official_holidays')
          .select('holiday_date, name')
          .gte('holiday_date', _iso(from))
          .lte('holiday_date', _iso(to)));

      String hhmm(Object? t) => t == null ? '' : t.toString().substring(0, t.toString().length >= 5 ? 5 : t.toString().length);

      final rows = buildDailyReport(
        from: from,
        to: to,
        today: DateTime.now(),
        employees: employees,
        schedules: _schedules,
        holidays: {
          for (final h in holidayRows)
            if (DateTime.tryParse(h.str('holiday_date') ?? '') != null) DateTime.parse(h.str('holiday_date')!): h.str('name') ?? 'عطلة',
        },
        attendance: [
          for (final a in attendanceRows)
            ReportAttendance(
              id: a.str('id') ?? '',
              employeeId: a.str('employee_id') ?? '',
              date: DateTime.parse(a.str('work_date')!),
              status: a.str('status') ?? 'present',
              checkIn: a.date('check_in_time'),
              checkOut: a.date('check_out_time'),
              checkInLat: a.dbl('check_in_lat'),
              checkInLng: a.dbl('check_in_lng'),
              checkOutLat: a.dbl('check_out_lat'),
              checkOutLng: a.dbl('check_out_lng'),
            ),
        ],
        leaves: [
          for (final l in leaveRows)
            if (l.date('start_date') != null && l.date('end_date') != null)
              ReportLeave(
                employeeId: l.str('employee_id') ?? '',
                from: l.date('start_date')!,
                to: l.date('end_date')!,
                typeName: _leaveTypeNames[l.str('leave_type')] ?? leaveTypeArabic(l.str('leave_type')),
                isHourly: l.boolean('is_hourly') ?? false,
                isPaid: l.boolean('is_paid') ?? true,
                startHour: hhmm(l['start_hour']),
                endHour: hhmm(l['end_hour']),
              ),
        ],
      );

      if (mounted) {
        setState(() {
          _rows = rows;
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

  Future<void> _exportExcel() async {
    if (_rows.isEmpty) {
      AppSnack.info(context, 'لا توجد بيانات للتصدير');
      return;
    }
    setState(() => _exporting = true);
    try {
      final branch = _selectedBranchId == 'all' ? 'كل الفروع' : _branchName(_selectedBranchId);
      final employee = _employeesList.where((e) => e['id'] == _selectedEmployeeId).firstOrNull?['full_name']?.toString();
      final path = await ExcelExportService.generateAttendanceReportExcel(
        rows: _rows,
        from: _selectedDateRange.start,
        to: _selectedDateRange.end,
        scopeLabel: employee ?? branch,
      );
      if (!mounted) return;
      await ExcelExportService.openExcelFile(path);
      if (!mounted) return;
      unawaited(showAppSheet<void>(
        context,
        title: 'التقرير جاهز',
        builder: (ctx) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('حُفظت نسخة Excel في مجلد التنزيلات: ورقة "يوم بيوم" وورقة "ملخص الموظفين".', style: AppText.bodySm),
            const SizedBox(height: AppSpace.lg),
            AppButton(
              label: 'فتح التقرير',
              icon: Icons.visibility_rounded,
              expand: true,
              onPressed: () {
                Navigator.pop(ctx);
                ExcelExportService.openExcelFile(path);
              },
            ),
            const SizedBox(height: AppSpace.sm),
            AppButton.secondary(
              label: 'مشاركة',
              icon: Icons.ios_share_rounded,
              expand: true,
              onPressed: () {
                Navigator.pop(ctx);
                ExcelExportService.shareExcelFile(path, text: 'تقرير الحضور والغياب - HR Pro');
              },
            ),
          ],
        ),
      ));
    } catch (e) {
      debugPrint('Excel export failed: $e');
      if (mounted) AppSnack.error(context, 'تعذّر إنشاء ملف Excel');
    } finally {
      if (mounted) setState(() => _exporting = false);
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

  static int _statusOrder(ReportStatus s) => switch (s) {
        ReportStatus.absent => 0,
        ReportStatus.late => 1,
        ReportStatus.earlyLeave => 2,
        ReportStatus.leave => 3,
        ReportStatus.present => 4,
        ReportStatus.dayOff => 5,
      };

  @override
  Widget build(BuildContext context) {
    final working = _rows.where((r) => r.status != ReportStatus.dayOff).toList();
    final totals = reportTotals(working);
    final visible = working.where((r) => _statusFilter == null || r.status == _statusFilter).toList()
      ..sort((a, b) {
        final d = b.date.compareTo(a.date);
        if (d != 0) return d;
        final s = _statusOrder(a.status).compareTo(_statusOrder(b.status));
        return s != 0 ? s : a.employee.name.compareTo(b.employee.name);
      });
    final multiDay = !DateUtils.isSameDay(_selectedDateRange.start, _selectedDateRange.end);
    final branchName = _branches.where((b) => b['id'] == _selectedBranchId).firstOrNull?['name']?.toString();
    final employeeName = _employeesList.where((e) => e['id'] == _selectedEmployeeId).firstOrNull?['full_name']?.toString();

    final List<Widget> list;
    if (_isLoading && _rows.isEmpty) {
      list = const [SkeletonList(itemHeight: 96)];
    } else if (_hasError && _rows.isEmpty) {
      list = [ErrorView(onRetry: _loadRecords)];
    } else if (visible.isEmpty) {
      list = const [EmptyView(title: 'لا توجد سجلات', message: 'غيّر الفترة أو الفلاتر.', icon: Icons.event_busy_rounded, compact: true)];
    } else {
      list = [];
      DateTime? lastDay;
      for (var i = 0; i < visible.length; i++) {
        final row = visible[i];
        if (multiDay && (lastDay == null || !DateUtils.isSameDay(lastDay, row.date))) {
          final dayRows = visible.where((r) => DateUtils.isSameDay(r.date, row.date));
          final dayTotals = reportTotals(dayRows);
          list.add(SectionHeader(
            Fmt.dateWithDay(row.date),
            trailing: Text(
              'حاضر ${dayTotals.attended} · غائب ${dayTotals.absent} · مجاز ${dayTotals.leave}',
              style: AppText.caption,
            ),
            padding: EdgeInsets.only(top: lastDay == null ? 0 : AppSpace.lg, bottom: AppSpace.sm),
          ));
        }
        lastDay = row.date;
        list.add(Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.sm),
          child: FadeSlideIn(index: i < 20 ? i : 20, child: _recordCard(row)),
        ));
      }
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('تقارير الحضور'),
        actions: [
          IconButton(
            tooltip: 'تصدير Excel',
            onPressed: _exporting || _isLoading ? null : _exportExcel,
            icon: _exporting
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.table_view_rounded, color: AppColors.brand),
          ),
        ],
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
                  KpiTile(label: 'حضور', value: totals.attended, icon: Icons.how_to_reg_rounded, tone: AppTone.success),
                  KpiTile(label: 'متأخر', value: totals.late, icon: Icons.schedule_rounded, tone: AppTone.warning),
                  KpiTile(label: 'غياب', value: totals.absent, icon: Icons.person_off_rounded, tone: AppTone.danger),
                  KpiTile(label: 'مجاز', value: totals.leave, icon: Icons.beach_access_rounded, tone: AppTone.info),
                  KpiTile(label: 'نسبة الحضور', value: totals.rate, icon: Icons.percent_rounded, format: (v) => '${v.round()}%'),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            AppChoiceChips<ReportStatus?>(
              scrollable: true,
              value: _statusFilter,
              onChanged: (v) => setState(() => _statusFilter = v),
              options: const [
                (null, 'الكل', null),
                (ReportStatus.present, 'حاضر', null),
                (ReportStatus.late, 'متأخر', null),
                (ReportStatus.earlyLeave, 'خروج مبكر', null),
                (ReportStatus.absent, 'غائب', null),
                (ReportStatus.leave, 'مجاز', null),
              ],
            ),
            const SizedBox(height: AppSpace.md),
            for (final w in list) ContentWidth(child: w),
          ],
        ),
      ),
    );
  }

  Widget _recordCard(ReportRow r) {
    final att = r.attendance;
    final tone = switch (r.status) {
      ReportStatus.present => AppTone.success,
      ReportStatus.late => AppTone.warning,
      ReportStatus.earlyLeave => AppTone.warning,
      ReportStatus.leave => AppTone.info,
      _ => AppTone.danger,
    };
    final name = r.employee.name;
    final showTimes = att != null && r.status.attended;

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
                      '${r.employee.code.isEmpty ? '' : '${r.employee.code} · '}${Fmt.dateWithDay(r.date)}',
                      style: AppText.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              StatusBadge(r.status.arabic, tone: tone, dot: true),
            ],
          ),
          if (r.note.isNotEmpty) ...[
            const SizedBox(height: AppSpace.sm),
            Row(
              children: [
                Icon(r.leave != null ? Icons.beach_access_rounded : Icons.info_outline_rounded, size: 16, color: AppColors.textMuted),
                const SizedBox(width: AppSpace.xs),
                Expanded(child: Text(r.note, style: AppText.bodySm)),
              ],
            ),
          ],
          if (showTimes) ...[
            const SizedBox(height: AppSpace.sm),
            Row(
              children: [
                Expanded(child: _TimeButton(icon: Icons.login_rounded, label: 'حضور', time: att.checkIn, onMap: () => _openMap(att.checkInLat, att.checkInLng))),
                const SizedBox(width: AppSpace.sm),
                Expanded(child: _TimeButton(icon: Icons.logout_rounded, label: 'انصراف', time: att.checkOut, onMap: () => _openMap(att.checkOutLat, att.checkOutLng))),
                IconButton(
                  tooltip: 'تعديل الأوقات',
                  icon: const Icon(Icons.edit_calendar_rounded, color: AppColors.brand),
                  onPressed: () => _editTimeDialog({
                    'id': att.id,
                    'employee_name': name,
                    'work_date': _iso(r.date),
                    'check_in': att.checkIn?.toIso8601String(),
                    'check_out': att.checkOut?.toIso8601String(),
                  }),
                ),
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
