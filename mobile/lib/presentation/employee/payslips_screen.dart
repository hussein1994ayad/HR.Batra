// =========================================================================
// HR Pro — كشوف رواتبي: آخر راتب، مخطط 6 أشهر، تفاصيل كل كشف وتصدير PDF
// =========================================================================

import 'dart:async';

import 'package:flutter/material.dart';


import '../../core/services/pdf_export_service.dart';
import '../../core/services/supabase_service.dart';
import '../shared/ui/ui.dart';

class PayslipsScreen extends StatefulWidget {
  const PayslipsScreen({super.key});

  @override
  State<PayslipsScreen> createState() => _PayslipsScreenState();
}

class _PayslipsScreenState extends State<PayslipsScreen> {
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
      final data = await SupabaseService.client
          .from('system_settings')
          .select('value')
          .eq('key', 'payroll_policy')
          .maybeSingle();

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
  Map<String, String> _getCycleDates(String monthStr) {
    try {
      final parts = monthStr.split('-');
      final int year = int.parse(parts[0]);
      final int month = int.parse(parts[1]);

      // Get last day of selected month
      final lastDaySelected = DateTime(year, month + 1, 0).day;

      if (_cycleStartDay <= _cycleEndDay) {
        // Same calendar month cycle
        final actualStartDay = _cycleStartDay < lastDaySelected ? _cycleStartDay : lastDaySelected;
        final actualEndDay = _cycleEndDay < lastDaySelected ? _cycleEndDay : lastDaySelected;

        final String startStr = "$year-${month.toString().padLeft(2, '0')}-${actualStartDay.toString().padLeft(2, '0')}";
        final String endStr = "$year-${month.toString().padLeft(2, '0')}-${actualEndDay.toString().padLeft(2, '0')}";
        return {'start': startStr, 'end': endStr};
      } else {
        // Cross-month cycle (starts in previous month, ends in selected month)
        final lastDayPrev = DateTime(year, month, 0).day;
        final prevMonthDate = DateTime(year, month - 1);
        final int prevYear = prevMonthDate.year;
        final int prevMonthNum = prevMonthDate.month;

        final actualStartDay = _cycleStartDay < lastDayPrev ? _cycleStartDay : lastDayPrev;
        final actualEndDay = _cycleEndDay < lastDaySelected ? _cycleEndDay : lastDaySelected;

        final String startStr = "$prevYear-${prevMonthNum.toString().padLeft(2, '0')}-${actualStartDay.toString().padLeft(2, '0')}";
        final String endStr = "$year-${month.toString().padLeft(2, '0')}-${actualEndDay.toString().padLeft(2, '0')}";
        return {'start': startStr, 'end': endStr};
      }
    } catch (e) {
      return {'start': '', 'end': ''};
    }
  }

  Future<void> _loadPayslips() async {
    setState(() => _isLoading = true);
    final user = SupabaseService.currentUser;
    if (user == null) return;

    try {
      final results = await Future.wait([
        SupabaseService.client
            .from('salary_slips')
            .select()
            .eq('employee_id', user.id)
            .eq('status', 'published')
            .order('work_month', ascending: false),
        SupabaseService.client
            .from('employees')
            .select('full_name, branch_id, branches(name)')
            .eq('id', user.id)
            .maybeSingle(),
      ]);

      Map<String, dynamic>? preview;
      try {
        final p = await SupabaseService.client.rpc<dynamic>('get_my_payroll_preview');
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
        final lines = await SupabaseService.client
            .from('salary_slip_lines')
            .select()
            .eq('salary_slip_id', slipId)
            .order('event_date', ascending: true);
        if (!mounted) return;
        setState(() => _slipsDetails[slipId] = slipLinesToDetails(List<Map<String, dynamic>>.from(lines)));
      } catch (e) {
        debugPrint('خطأ في تحميل تفاصيل الكشف: $e');
      }
      return;
    }

    final cycle = _getCycleDates(workMonth);
    if (cycle['start']!.isEmpty || cycle['end']!.isEmpty) return;

    try {
      final detailsData = await SupabaseService.client
          .from('bonuses_deductions')
          .select()
          .eq('employee_id', user.id)
          .gte('issue_date', cycle['start']!)
          .lte('issue_date', cycle['end']!)
          .order('issue_date', ascending: true);

      if (!mounted) return;
      final rows = List<Map<String, dynamic>>.from(detailsData).where((d) {
        final linked = d['salary_slip_id']?.toString();
        if (linked != null) return linked == slipId;
        final created = DateTime.tryParse((d['created_at'] ?? '').toString());
        return slipCreated == null || created == null || !created.isAfter(slipCreated);
      }).toList();
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

  static (int month, int year) _monthOf(String workMonth) {
    final p = workMonth.split('-');
    return (p.length > 1 ? int.tryParse(p[1]) ?? 1 : 1, int.tryParse(p.first) ?? DateTime.now().year);
  }

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
          return _SlipDetails(
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

const _lineLabels = {
  'absence': 'غياب',
  'late': 'تأخير',
  'early_leave': 'خروج مبكر',
  'unpaid_leave': 'إجازة بدون راتب',
  'overtime': 'ساعات إضافية',
  'manual_deduction': 'خصم',
  'bonus': 'مكافأة',
  'allowance': 'مخصصات',
  'adjustment': 'تسوية',
};

/// أسطر كشف المحرّك (salary_slip_lines) بنفس شكل تفاصيل الكشف القديمة
/// (reason / amount / issue_date / type) — أقساط السلف لها سطرها الخاص في الكشف،
/// والإجازات المدفوعة بلا مبلغ لا تظهر.
List<Map<String, dynamic>> slipLinesToDetails(List<Map<String, dynamic>> lines) => [
      for (final l in lines)
        if (l['line_type'] != 'loan' && ((l['amount'] as num?) ?? 0) > 0)
          {
            'reason': _lineReason(l),
            'amount': l['amount'],
            'issue_date': l['event_date'],
            'type': ((l['direction'] as num?) ?? -1) > 0 ? 'bonus' : 'deduction',
          },
    ];

String _lineReason(Map<String, dynamic> l) {
  final type = (l['line_type'] ?? '').toString();
  final label = _lineLabels[type] ?? 'بند';
  final minutes = ((l['minutes'] as num?) ?? 0).round();
  final notes = (l['notes'] ?? '').toString().trim();
  final base = type == 'bonus' || type == 'manual_deduction' || type == 'adjustment'
      ? (notes.isNotEmpty ? notes : label)
      : minutes > 0
          ? '$label $minutes دقيقة'
          : label;
  final carried = (l['carried_from'] ?? '').toString();
  return carried.isEmpty ? base : '$base (مرحّل من $carried)';
}

/// راتب الشهر الحالي قبل الاعتماد: الأساسي، الإضافات، الخصومات، الأقساط، والمتوقع،
/// مع كل حركة وحالتها (بانتظار قرار الإدارة / محتسبة / معفى منها).
class CurrentPayrollCard extends StatelessWidget {
  const CurrentPayrollCard({super.key, required this.preview});
  final Map<String, dynamic> preview;

  static double _n(Object? v) => (v as num?)?.toDouble() ?? double.tryParse(v?.toString() ?? '') ?? 0;

  static const _labels = {
    'absence': 'غياب',
    'late': 'تأخير',
    'early_leave': 'خروج مبكر',
    'missing_punch': 'بصمة ناقصة',
    'unpaid_leave': 'إجازة بدون راتب',
    'paid_leave': 'إجازة مدفوعة',
    'overtime': 'ساعات إضافية',
    'manual_deduction': 'خصم',
    'bonus': 'مكافأة',
    'adjustment': 'تسوية',
  };

  static String _status(Object? s) => switch (s) {
        'pending' => 'بانتظار القرار',
        'ignored' => 'معفى',
        _ => 'محتسب',
      };

  @override
  Widget build(BuildContext context) {
    final s = Map<String, dynamic>.from((preview['summary'] as Map?) ?? const {});
    final period = Map<String, dynamic>.from((preview['period'] as Map?) ?? const {});
    final events = [for (final e in (preview['events'] as List? ?? const [])) Map<String, dynamic>.from(e as Map)];
    final month = (period['period_month'] ?? '').toString().split('-');
    final m = month.length == 2 ? int.tryParse(month[1]) ?? 1 : 1;
    final y = int.tryParse(month.first) ?? DateTime.now().year;
    final issued = s['slip'] != null;
    final pending = events.where((e) => e['status'] == 'pending' && e['event_type'] != 'missing_punch').length;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const ToneIcon(Icons.pending_actions_rounded, tone: AppTone.info),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('راتب ${Fmt.monthNumber(m, y)}', style: AppText.subtitle),
                    Text(issued ? 'اعتُمد الكشف' : 'قبل الاعتماد · قد يتغير حتى نهاية المسير', style: AppText.caption),
                  ],
                ),
              ),
              if (pending > 0) StatusBadge('$pending بانتظار قرار', tone: AppTone.warning),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          KeyValueRow('الراتب الأساسي', Fmt.iqd(_n(s['basic']))),
          if (_n(s['earnings']) > 0) KeyValueRow('مكافآت وإضافي', '+${Fmt.iqd(_n(s['earnings']))}', valueColor: AppColors.success),
          if (_n(s['deductions']) > 0) KeyValueRow('غياب وتأخير وخصومات', '-${Fmt.iqd(_n(s['deductions']))}', valueColor: AppColors.danger),
          if (_n(s['loans']) > 0) KeyValueRow('قسط السلفة', '-${Fmt.iqd(_n(s['loans']))}', valueColor: AppColors.danger),
          const Divider(height: AppSpace.xl),
          KeyValueRow('الصافي المتوقع', Fmt.iqd(_n(s['net'])), valueColor: AppColors.brand, bold: true),
          if (events.isNotEmpty) ...[
            const SizedBox(height: AppSpace.md),
            Text('الحركات', style: AppText.label.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: AppSpace.xs),
            for (final e in events)
              KeyValueRow(
                '${_labels[e['event_type']] ?? e['event_type']}'
                '${_n(e['minutes']) > 0 ? ' ${_n(e['minutes']).round()} د' : ''}'
                ' · ${Fmt.date(DateTime.tryParse(e['event_date']?.toString() ?? ''))} · ${_status(e['status'])}',
                _n(e['amount']) <= 0 ? '—' : '${_n(e['direction']) > 0 ? '+' : '-'}${Fmt.iqd(_n(e['amount']))}',
                valueColor: e['status'] == 'ignored'
                    ? AppColors.textMuted
                    : _n(e['direction']) > 0
                        ? AppColors.success
                        : AppColors.danger,
              ),
          ],
        ],
      ),
    );
  }
}

class _SlipDetails extends StatelessWidget {
  const _SlipDetails({required this.slip, required this.details, required this.exporting, required this.onExport});

  final Map<String, dynamic> slip;
  final List<Map<String, dynamic>>? details;
  final bool exporting;
  final VoidCallback onExport;

  static double _n(Object? v) => (v as num?)?.toDouble() ?? 0.0;

  @override
  Widget build(BuildContext context) {
    final basic = _n(slip['basic_salary']);
    final allowances = _n(slip['allowances']);
    final deductions = _n(slip['deductions']);
    final loans = _n(slip['loans_deduction']);
    final net = _n(slip['net_salary']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KeyValueRow('الراتب الأساسي', Fmt.iqd(basic)),
        if (allowances > 0) KeyValueRow('مكافآت وزيادات', '+${Fmt.iqd(allowances)}', valueColor: AppColors.success),
        if (deductions > 0) KeyValueRow('غيابات وخصومات', '-${Fmt.iqd(deductions)}', valueColor: AppColors.danger),
        if (loans > 0) KeyValueRow('قسط السلفة', '-${Fmt.iqd(loans)}', valueColor: AppColors.danger),
        const Divider(height: AppSpace.xl),
        KeyValueRow('الصافي', Fmt.iqd(net), valueColor: AppColors.brand, bold: true),
        const SizedBox(height: AppSpace.md),
        Text('تفاصيل المكافآت والخصومات', style: AppText.label.copyWith(color: AppColors.textSecondary)),
        const SizedBox(height: AppSpace.sm),
        if (details == null)
          const Skeleton(height: 40)
        else if (details!.isEmpty)
          const Text('لا توجد مكافآت أو خصومات استثنائية بهذه الدورة.', style: AppText.caption)
        else
          for (final item in details!)
            KeyValueRow(
              '${item['reason'] ?? ''} · ${Fmt.date(DateTime.tryParse(item['issue_date']?.toString() ?? ''))}',
              '${item['type'] == 'bonus' ? '+' : '-'}${Fmt.iqd(_n(item['amount']))}',
              valueColor: item['type'] == 'bonus' ? AppColors.success : AppColors.danger,
            ),
        const SizedBox(height: AppSpace.xl),
        AppButton(label: 'تحميل الكشف PDF', icon: Icons.picture_as_pdf_rounded, expand: true, loading: exporting, onPressed: onExport),
      ],
    );
  }
}
