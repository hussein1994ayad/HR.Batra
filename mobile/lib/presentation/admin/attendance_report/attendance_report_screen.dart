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

import '../../../core/logic/attendance_report.dart';
import '../../../core/models/models.dart';
import '../../../core/services/excel_export_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/utils/app_log.dart';
import '../../../data/repositories/attendance_report_repository.dart';
import '../../../data/repositories/role_repository.dart';
import '../../shared/ui/ui.dart';
import 'widgets/edit_times_sheet.dart';
import 'widgets/report_record_card.dart';

class AttendanceReportScreen extends StatefulWidget {
  const AttendanceReportScreen({super.key});

  @override
  State<AttendanceReportScreen> createState() => _AttendanceReportScreenState();
}

class _AttendanceReportScreenState extends State<AttendanceReportScreen> {
  final AttendanceReportRepository _repo = AttendanceReportRepository();
  bool _isLoading = true;
  bool _hasError = false;
  bool _exporting = false;
  DateTimeRange _selectedDateRange = DateTimeRange(start: DateTime.now(), end: DateTime.now());

  String? _selectedBranchId = 'all';
  String? _selectedEmployeeId = 'all';
  ReportStatus? _statusFilter;

  List<BranchModel> _branches = [];
  List<EmployeeRef> _employeesList = [];
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
      if (!await RoleRepository().isAdminOrManager()) {
        if (mounted) Navigator.pop(context);
        return;
      }

      final lookups = await _repo.fetchLookups();
      if (mounted) {
        _branches = lookups.branches;
        _employeesList = lookups.employees;
        _schedules = lookups.schedules;
        _leaveTypeNames = lookups.leaveTypeNames;
      }
    } catch (e) {
      appLog('Error loading report lookups: $e');
    }
    unawaited(_loadRecords());
  }

  String _branchName(String? id) => _branches.where((b) => b.id == id).firstOrNull?.rawName ?? '';

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
  static String _iso(DateTime d) => d.toIso8601String().split('T')[0];

  Future<void> _loadRecords() async {
    setState(() => _isLoading = true);
    try {
      final from = _day(_selectedDateRange.start);
      final to = _day(_selectedDateRange.end);

      final employees = [
        for (final e in _employeesList)
          if (e.isActive != false &&
              (_selectedEmployeeId == 'all' || e.id == _selectedEmployeeId) &&
              (_selectedBranchId == 'all' || e.branchId == _selectedBranchId))
            ReportEmployee(
              id: e.id,
              name: e.fullName ?? 'موظف',
              code: e.employeeCode ?? '',
              branchId: e.branchId,
              departmentId: e.departmentId,
              branchName: _branchName(e.branchId),
              joinDate: e.joinDate,
            ),
      ];
      final ids = employees.isEmpty ? ['00000000-0000-0000-0000-000000000000'] : [for (final e in employees) e.id];

      final attendance = await _repo.fetchAttendance(ids, from: _iso(from), to: _iso(to));

      final leaves = await _repo.fetchApprovedLeaves(ids, from: from, to: to, typeNames: _leaveTypeNames);

      final holidays = await _repo.fetchHolidays(from: _iso(from), to: _iso(to));

      final rows = buildDailyReport(
        from: from,
        to: to,
        today: DateTime.now(),
        employees: employees,
        schedules: _schedules,
        holidays: holidays,
        attendance: attendance,
        leaves: leaves,
      );

      if (mounted) {
        setState(() {
          _rows = rows;
          _hasError = false;
        });
      }
    } catch (e) {
      appLog('Error loading attendance: $e');
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
      final employee = _employeesList.where((e) => e.id == _selectedEmployeeId).firstOrNull?.fullName;
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
      appLog('Excel export failed: $e');
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
      options: [('all', 'كل الفروع'), for (final b in _branches) (b.id, '${b.rawName}')],
    );
    if (id == null) return;
    setState(() {
      _selectedBranchId = id;
      // الموظف المختار من فرع آخر يُلغى اختياره
      if (_selectedEmployeeId != 'all') {
        final emp = _employeesList.where((e) => e.id == _selectedEmployeeId).firstOrNull;
        if (emp != null && id != 'all' && emp.branchId != id) _selectedEmployeeId = 'all';
      }
    });
    unawaited(_loadRecords());
  }

  Future<void> _pickEmployee() async {
    final list = _employeesList.where((e) => _selectedBranchId == 'all' || e.branchId == _selectedBranchId);
    final id = await showAppOptions(
      context,
      title: 'الموظف',
      current: _selectedEmployeeId,
      options: [('all', 'كل الموظفين'), for (final e in list) (e.id, '${e.fullName}')],
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





  Future<void> _editTimeDialog(ReportTimeEdit record) async {
    final times = await showEditTimesSheet(context, record);
    if (times != null) {
      unawaited(_saveEditedTime(record.id, record.workDate, times.checkIn, times.checkOut));
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
        await _repo.updateAttendanceTimes(recordId, updates);
        if (mounted) {
          AppSnack.success(context, 'حُدّثت الأوقات');
          unawaited(_loadRecords());
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      appLog('Error updating time: $e');
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
    final branchName = _branches.where((b) => b.id == _selectedBranchId).firstOrNull?.rawName;
    final employeeName = _employeesList.where((e) => e.id == _selectedEmployeeId).firstOrNull?.fullName;

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
          child: FadeSlideIn(index: i < 20 ? i : 20, child: ReportRecordCard(row: row, onOpenMap: _openMap, onEditTimes: _editTimeDialog)),
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
}
