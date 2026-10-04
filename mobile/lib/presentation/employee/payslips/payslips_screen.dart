// =========================================================================
// HR Pro — كشوف رواتبي: آخر راتب، مخطط 6 أشهر، تفاصيل كل كشف وتصدير PDF
// =========================================================================

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/services/pdf_export_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../data/repositories/payslips_repository.dart';
import '../../shared/ui/ui.dart';
import 'payslips_logic.dart';
import 'widgets/payslip_widgets.dart';

class PayslipsScreen extends StatefulWidget {
  const PayslipsScreen({super.key});

  @override
  State<PayslipsScreen> createState() => _PayslipsScreenState();
}

class _PayslipsScreenState extends State<PayslipsScreen> {
  final PayslipsRepository _repo = PayslipsRepository();
  bool _isLoading = true;
  bool _hasError = false;
  String? _exportingSlipId;
  Map<String, dynamic>? _employeeProfile;
  List<Map<String, dynamic>> _slips = [];

  /// مسير الشهر الحالي قبل الاعتماد (get_my_payroll_preview)
  Map<String, dynamic>? _preview;
  final Map<String, List<Map<String, dynamic>>> _slipsDetails = {}; // Record of slip_id -> list of details
  int _cycleStartDay = 25;
  int _cycleEndDay = 24;

  @override
  void initState() {
    super.initState();
    _loadPayrollPolicy().then((_) => _loadPayslips());
  }

  Future<void> _loadPayrollPolicy() async {
    try {
      final data = await _repo.fetchPayrollPolicy();

      if (data != null && data['value'] != null) {
        final policy = data['value'] as Map<String, dynamic>;
        if (!mounted) return;
        setState(() {
          _cycleStartDay = policy['cycle_start_day'] != null ? int.parse(policy['cycle_start_day'].toString()) : 25;
          _cycleEndDay = policy['cycle_end_day'] != null ? int.parse(policy['cycle_end_day'].toString()) : 24;
        });
      }
    } catch (e) {
      debugPrint('خطأ في تحميل إعدادات الدورة المالية: $e');
    }
  }

  // الحصول على تواريخ الدورة المالية بناءً على اسم الشهر المالي (YYYY-MM)
  Map<String, String> _getCycleDates(String monthStr) => payslipCycleDates(monthStr, startDay: _cycleStartDay, endDay: _cycleEndDay);

  Future<void> _loadPayslips() async {
    setState(() => _isLoading = true);
    final user = SupabaseService.currentUser;
    if (user == null) return;

    try {
      final results = await _repo.fetchSlipsAndProfile(user.id);

      Map<String, dynamic>? preview;
      try {
        final p = await _repo.fetchPayrollPreview();
        if (p is Map) preview = Map<String, dynamic>.from(p);
      } catch (e) {
        debugPrint('تعذّر تحميل مسير الشهر الحالي: $e');
      }

      if (!mounted) return;
      setState(() {
        _preview = preview;
        _slips = List<Map<String, dynamic>>.from(results[0] as List);
        _hasError = false;
        if (results[1] != null) {
          _employeeProfile = results[1] as Map<String, dynamic>;
        }
      });
    } catch (e) {
      debugPrint('خطأ في تحميل كشوف الرواتب: $e');
      if (mounted) setState(() => _hasError = true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // تحميل تفاصيل المكافآت والخصومات المسجلة للموظف خلال الدورة المالية
  //
  // فقط البنود التي دخلت في هذا الكشف: المرتبطة به (salary_slip_id)، أو اليدوية
  // المسجلة قبل اعتماده. البنود المضافة بعد الاعتماد تخص كشفاً قادماً، وكانت تظهر
  // في الكشف بدون أن تُحسب في صافيه.
  Future<void> _loadSlipDetails(Map<String, dynamic> slip) async {
    final slipId = (slip['id'] ?? '').toString();
    final workMonth = (slip['work_month'] ?? '0000-00').toString();
    final slipCreated = DateTime.tryParse((slip['created_at'] ?? '').toString());
    if (_slipsDetails.containsKey(slipId)) return; // محملة مسبقاً

    final user = SupabaseService.currentUser;
    if (user == null) return;

    // كشوف محرّك الرواتب: التفاصيل محفوظة مع الكشف نفسه سطراً سطراً
    if (slip['computed_by_engine'] == true) {
      try {
        final lines = await _repo.fetchSlipLines(slipId);
        if (!mounted) return;
        setState(() => _slipsDetails[slipId] = slipLinesToDetails(lines));
      } catch (e) {
        debugPrint('خطأ في تحميل تفاصيل الكشف: $e');
      }
      return;
    }

    final cycle = _getCycleDates(workMonth);
    if (cycle['start']!.isEmpty || cycle['end']!.isEmpty) return;

    try {
      final detailsData = await _repo.fetchBonusesDeductions(user.id, start: cycle['start']!, end: cycle['end']!);

      if (!mounted) return;
      final rows = itemsIncludedInSlip(detailsData, slipId: slipId, slipCreated: slipCreated);
      setState(() {
        _slipsDetails[slipId] = rows;
      });
    } catch (e) {
      debugPrint('خطأ في تحميل تفاصيل المكافآت والخصومات: $e');
    }
  }


  // تصدير كشف الراتب PDF ثم عرض خيارات الفتح والمشاركة
  Future<void> _exportPayslipToPdf(Map<String, dynamic> slip) async {
    final String slipId = (slip['id'] ?? '') as String;
    final String workMonth = (slip['work_month'] ?? '0000-00') as String;
    setState(() => _exportingSlipId = slipId);

    try {
      if (!_slipsDetails.containsKey(slipId)) {
        await _loadSlipDetails(slip);
      }

      final List<Map<String, dynamic>> details = _slipsDetails[slipId] ?? [];
      final bonuses = details.where((d) => d['type'] == 'bonus').toList();
      final deductions = details.where((d) => d['type'] == 'deduction').toList();

      final String empName = (_employeeProfile?['full_name'] ?? 'الموظف') as String;
      final branches = _employeeProfile?['branches'];
      final String branchName = branches is Map ? (branches['name'] ?? '').toString() : '';

      final String filePath = await PdfExportService.generatePayslipPdf(
        employeeName: empName,
        branchName: branchName,
        workMonth: workMonth,
        basicSalary: (slip['basic_salary'] as num?)?.toDouble() ?? 0.0,
        allowances: (slip['allowances'] as num?)?.toDouble() ?? 0.0,
        deductions: (slip['deductions'] as num?)?.toDouble() ?? 0.0,
        loansDeduction: (slip['loans_deduction'] as num?)?.toDouble() ?? 0.0,
        netSalary: (slip['net_salary'] as num?)?.toDouble() ?? 0.0,
        bonusesList: bonuses,
        deductionsList: deductions,
      );

      if (!mounted) return;
      await PdfExportService.openPdfFile(filePath);
      if (!mounted) return;
      unawaited(showAppSheet<void>(
        context,
        title: 'الكشف جاهز',
        builder: (ctx) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('حُفظت نسخة PDF في مجلد التنزيلات.', style: AppText.bodySm),
            const SizedBox(height: AppSpace.lg),
            AppButton(
              label: 'فتح الكشف',
              icon: Icons.visibility_rounded,
              expand: true,
              onPressed: () {
                Navigator.pop(ctx);
                PdfExportService.openPdfFile(filePath);
              },
            ),
            const SizedBox(height: AppSpace.sm),
            AppButton.secondary(
              label: 'مشاركة',
              icon: Icons.ios_share_rounded,
              expand: true,
              onPressed: () {
                Navigator.pop(ctx);
                PdfExportService.sharePdfFile(filePath);
              },
            ),
          ],
        ),
      ));
    } catch (e) {
      debugPrint('خطأ في تصدير PDF للراتب: $e');
      if (mounted) AppSnack.error(context, 'تعذّر إنشاء ملف PDF');
    } finally {
      if (mounted) setState(() => _exportingSlipId = null);
    }
  }

  static (int month, int year) _monthOf(String workMonth) => payslipMonthOf(workMonth);

  static double _num(Object? v) => (v as num?)?.toDouble() ?? 0.0;

  Future<void> _openSlip(Map<String, dynamic> slip) async {
    final slipId = (slip['id'] ?? '').toString();
    final workMonth = (slip['work_month'] ?? '0000-00').toString();
    unawaited(_loadSlipDetails(slip));
    final (m, y) = _monthOf(workMonth);
    await showAppSheet<void>(
      context,
      title: 'راتب ${Fmt.monthNumber(m, y)}',
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          // يُعاد الرسم عند وصول التفاصيل
          if (!_slipsDetails.containsKey(slipId)) {
            Future<void>.delayed(const Duration(milliseconds: 300), () {
              if (ctx.mounted) setSheet(() {});
            });
          }
          return SlipDetailsView(
            slip: slip,
            details: _slipsDetails[slipId],
            exporting: _exportingSlipId == slipId,
            onExport: () async {
              await _exportPayslipToPdf(slip);
              if (ctx.mounted) setSheet(() {});
            },
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> body;
    if (_isLoading && _slips.isEmpty) {
      body = const [SkeletonList(header: true, count: 4)];
    } else if (_hasError && _slips.isEmpty) {
      body = [ErrorView(onRetry: _loadPayslips)];
    } else if (_slips.isEmpty) {
      body = [
        if (_preview != null) ...[CurrentPayrollCard(preview: _preview!), const SizedBox(height: AppSpace.lg)],
        const EmptyView(title: 'لا توجد كشوف رواتب بعد', message: 'يظهر كشف الشهر هنا بعد اعتماده من الإدارة.', icon: Icons.receipt_long_rounded),
      ];
    } else {
      final latest = _slips.first;
      final (lm, ly) = _monthOf((latest['work_month'] ?? '').toString());
      final recent = _slips.take(6).toList().reversed.toList();
      body = [
        if (_preview != null) ...[CurrentPayrollCard(preview: _preview!), const SizedBox(height: AppSpace.lg)],
        AppCard(
          padding: const EdgeInsets.all(AppSpace.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('آخر راتب · ${Fmt.monthNumber(lm, ly)}', style: AppText.bodySm),
              const SizedBox(height: AppSpace.xs),
              AnimatedNumber(_num(latest['net_salary']), format: Fmt.iqd, style: AppText.display.copyWith(color: AppColors.brand, fontSize: 30)),
              if (recent.length > 1) ...[
                const SizedBox(height: AppSpace.lg),
                MiniBarChart(
                  values: [for (final s in recent) _num(s['net_salary'])],
                  labels: [for (final s in recent) 'شهر ${_monthOf((s['work_month'] ?? '').toString()).$1}'],
                  height: 72,
                  semanticLabel: 'صافي الراتب لآخر ${recent.length} أشهر',
                ),
              ],
            ],
          ),
        ),
        const SectionHeader('كل الكشوف'),
        for (var i = 0; i < _slips.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: FadeSlideIn(index: i, child: _slipTile(_slips[i])),
          ),
      ];
    }
    return AppPage(
      title: 'كشوف الرواتب',
      onRefresh: _loadPayslips,
      slivers: [SliverList.list(children: body)],
    );
  }

  Widget _slipTile(Map<String, dynamic> slip) {
    final (m, y) = _monthOf((slip['work_month'] ?? '').toString());
    final deductions = _num(slip['deductions']) + _num(slip['loans_deduction']);
    return AppCard(
      padding: EdgeInsets.zero,
      onTap: () => _openSlip(slip),
      child: AppListTile(
        leading: const ToneIcon(Icons.receipt_long_rounded, tone: AppTone.success),
        title: 'راتب ${Fmt.monthNumber(m, y)}',
        subtitle: '${Fmt.months[m - 1]} · ${deductions > 0 ? 'استقطاعات ${Fmt.iqd(deductions)}' : 'بدون استقطاعات'}',
        trailing: Text(Fmt.iqd(_num(slip['net_salary'])), style: AppText.subtitle.copyWith(color: AppColors.brand)),
        onTap: () => _openSlip(slip),
      ),
    );
  }
}
