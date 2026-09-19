// =========================================================================
// نظام HR Pro v6.0 - شاشة كشوف الرواتب الشهرية للموظف (Monthly Payslips Screen)
// =========================================================================

import 'package:flutter/material.dart';
import '../../core/services/pdf_export_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/constants.dart';
import '../shared/widgets/glass_background.dart';

class PayslipsScreen extends StatefulWidget {
  const PayslipsScreen({super.key});

  @override
  State<PayslipsScreen> createState() => _PayslipsScreenState();
}

class _PayslipsScreenState extends State<PayslipsScreen> {
  bool _isLoading = true;
  String? _exportingSlipId;
  Map<String, dynamic>? _employeeProfile;
  List<Map<String, dynamic>> _slips = [];
  Map<String, List<Map<String, dynamic>>> _slipsDetails = {}; // Record of slip_id -> list of details
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
        final prevMonthDate = DateTime(year, month - 1, 1);
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
            .select('*')
            .eq('employee_id', user.id)
            .eq('status', 'published')
            .order('work_month', ascending: false),
        SupabaseService.client
            .from('employees')
            .select('full_name, branch_id, branches(name)')
            .eq('id', user.id)
            .maybeSingle(),
      ]);

      if (!mounted) return;
      setState(() {
        _slips = List<Map<String, dynamic>>.from(results[0] as List);
        if (results[1] != null) {
          _employeeProfile = results[1] as Map<String, dynamic>;
        }
      });
    } catch (e) {
      debugPrint('خطأ في تحميل كشوف الرواتب: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // تحميل تفاصيل المكافآت والخصومات المسجلة للموظف خلال الدورة المالية
  Future<void> _loadSlipDetails(String slipId, String workMonth) async {
    if (_slipsDetails.containsKey(slipId)) return; // محملة مسبقاً

    final user = SupabaseService.currentUser;
    if (user == null) return;

    final cycle = _getCycleDates(workMonth);
    if (cycle['start']!.isEmpty || cycle['end']!.isEmpty) return;

    try {
      final detailsData = await SupabaseService.client
          .from('bonuses_deductions')
          .select('*')
          .eq('employee_id', user.id)
          .gte('issue_date', cycle['start']!)
          .lte('issue_date', cycle['end']!)
          .order('issue_date', ascending: true);

      if (!mounted) return;
      setState(() {
        _slipsDetails[slipId] = List<Map<String, dynamic>>.from(detailsData);
      });
    } catch (e) {
      debugPrint('خطأ في تحميل تفاصيل المكافآت والخصومات: $e');
    }
  }

  // تصدير كشف الراتب الشهري بصيغة PDF
  Future<void> _exportPayslipToPdf(Map<String, dynamic> slip) async {
    final String slipId = slip['id'] ?? '';
    final String workMonth = slip['work_month'] ?? '0000-00';
    setState(() => _exportingSlipId = slipId);

    try {
      // 1. التأكد من تحميل التفاصيل
      if (!_slipsDetails.containsKey(slipId)) {
        await _loadSlipDetails(slipId, workMonth);
      }

      final List<Map<String, dynamic>> details = _slipsDetails[slipId] ?? [];
      final bonuses = details.where((d) => d['type'] == 'bonus').toList();
      final deductions = details.where((d) => d['type'] == 'deduction').toList();

      final String empName = _employeeProfile?['full_name'] ?? 'الموظف';
      final String branchName = _employeeProfile?['branches']?['name'] ?? '';

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

      if (mounted) {
        // فتح الملف مباشرة عبر عارض المستندات
        await PdfExportService.openPdfFile(filePath);

        if (!mounted) return;
        showModalBottomSheet(
          context: context,
          backgroundColor: const Color(0xFF0F172A),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          builder: (ctx) => Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.successGreen.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check_circle_rounded, color: AppTheme.successGreen, size: 24),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('تم إنشاء كشف الراتب بنجاح! 📄', style: TextStyle(fontFamily: 'Cairo', fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                          Text('تم حفظ نسخة رسمية في مجلد المستندات والتنزيلات (Downloads)', style: TextStyle(fontFamily: 'Cairo', fontSize: 11, color: Colors.white60)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          PdfExportService.openPdfFile(filePath);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryTeal,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.visibility_rounded, size: 18),
                        label: const Text('فتح الكشف 📄', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          PdfExportService.sharePdfFile(filePath);
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.neonCyan,
                          side: const BorderSide(color: AppTheme.neonCyan),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.share_rounded, size: 18),
                        label: const Text('مشاركة / واتساب 📤', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('خطأ في تصدير PDF للراتب: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل إنشاء ملف PDF: $e', style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: AppTheme.dangerRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _exportingSlipId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text(
            'كشوف الرواتب الشهرية',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AppTheme.neonCyan))
            : _slips.isEmpty
                ? _buildEmptyState()
                : RefreshIndicator(
                    onRefresh: _loadPayslips,
                    color: AppTheme.neonCyan,
                    child: ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _slips.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 16),
                      itemBuilder: (context, index) {
                        final slip = _slips[index];
                        return _buildSlipCard(slip, isDark);
                      },
                    ),
                  ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long_rounded, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text(
            'لا توجد كشوف رواتب معتمدة لك حالياً ✨',
            style: TextStyle(fontFamily: 'Cairo', fontSize: 13, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _buildSlipCard(Map<String, dynamic> slip, bool isDark) {
    final String slipId = slip['id'] ?? '';
    final String workMonth = slip['work_month'] ?? '0000-00';
    final double basic = (slip['basic_salary'] as num?)?.toDouble() ?? 0.0;
    final double allowances = (slip['allowances'] as num?)?.toDouble() ?? 0.0;
    final double deductions = (slip['deductions'] as num?)?.toDouble() ?? 0.0;
    final double loans = (slip['loans_deduction'] as num?)?.toDouble() ?? 0.0;
    final double net = (slip['net_salary'] as num?)?.toDouble() ?? 0.0;

    final parts = workMonth.split('-');
    final String monthNum = parts.length > 1 ? int.parse(parts[1]).toString() : '0';
    final String year = parts.isNotEmpty ? parts[0] : '2026';
    final String arabicMonth = 'شهر $monthNum / $year';

    return ExpansionTile(
      title: Text(
        'كشف راتب $arabicMonth',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontFamily: 'Cairo',
          fontSize: 14,
        ),
      ),
      subtitle: Text(
        'صافي الراتب: ${AppConstants.formatMoney(net)}',
        style: const TextStyle(
          color: AppTheme.neonCyan,
          fontWeight: FontWeight.bold,
          fontFamily: 'Cairo',
          fontSize: 12,
        ),
      ),
      collapsedShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: AppTheme.neonCyan.withValues(alpha: 0.2)),
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppTheme.neonCyan),
      ),
      backgroundColor: const Color(0xFF1E293B).withValues(alpha: 0.35),
      collapsedBackgroundColor: const Color(0xFF1E293B).withValues(alpha: 0.15),
      iconColor: AppTheme.neonCyan,
      collapsedIconColor: Colors.white70,
      onExpansionChanged: (expanded) {
        if (expanded) {
          _loadSlipDetails(slipId, workMonth);
        }
      },
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Divider(color: Colors.white12),
              
              // 1. جدول البيانات الأساسية
              _buildBreakdownRow('الراتب الأساسي', basic, isDeduction: false),
              _buildBreakdownRow('المكافآت والزيادات (+)', allowances, isDeduction: false, color: AppTheme.successGreen),
              _buildBreakdownRow('الغيابات والخصومات (-)', deductions, isDeduction: true),
              _buildBreakdownRow('خصم السلفة والأقساط (-)', loans, isDeduction: true),
              
              const Divider(color: Colors.white24, height: 24),
              
              // 2. الراتب الصافي
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'الراتب الصافي المستلم:',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    AppConstants.formatMoney(net),
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      color: AppTheme.neonCyan,
                    ),
                  ),
                ],
              ),

              // 3. تفاصيل التسويات (إذا وجدت)
              if (_slipsDetails.containsKey(slipId)) ...[
                const SizedBox(height: 16),
                const Text(
                  'تفاصيل الزيادات والخصومات للدورة المالية:',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: _slipsDetails[slipId]!.isEmpty
                      ? const Center(
                          child: Text(
                            'لم تسجل أي تسويات مالية استثنائية هذا الشهر.',
                            style: TextStyle(fontFamily: 'Cairo', fontSize: 10, color: Colors.grey),
                          ),
                        )
                      : Column(
                          children: _slipsDetails[slipId]!.map((item) {
                            final String type = item['type'] ?? 'bonus';
                            final double amount = (item['amount'] as num?)?.toDouble() ?? 0.0;
                            final String reason = item['reason'] ?? '';
                            final String date = item['issue_date'] ?? '';

                            final bool isBonus = type == 'bonus';

                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      '$reason ($date)',
                                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 10, color: Colors.white70),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Text(
                                    '${isBonus ? "+" : "-"}${AppConstants.formatMoney(amount)}',
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: isBonus ? AppTheme.successGreen : AppTheme.dangerRed,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                ),
              ],

              const SizedBox(height: 16),

              // 4. زر تحميل وطباعة كشف الراتب PDF
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton.icon(
                  onPressed: _exportingSlipId == slipId ? null : () => _exportPayslipToPdf(slip),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryTeal.withValues(alpha: 0.3),
                    foregroundColor: AppTheme.neonCyan,
                    side: const BorderSide(color: AppTheme.neonCyan, width: 1.2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  icon: _exportingSlipId == slipId
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.neonCyan))
                      : const Icon(Icons.picture_as_pdf_rounded, size: 20),
                  label: Text(
                    _exportingSlipId == slipId ? 'جاري إنشاء ملف PDF...' : 'تحميل وطباعة كشف الراتب PDF 📄',
                    style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBreakdownRow(String label, double val, {required bool isDeduction, Color? color}) {
    if (val <= 0) return const SizedBox.shrink();

    final displayColor = color ?? (isDeduction ? AppTheme.dangerRed : Colors.white70);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, color: Colors.white70),
          ),
          Text(
            '${isDeduction ? "-" : "+"}${AppConstants.formatMoney(val)}',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: displayColor,
            ),
          ),
        ],
      ),
    );
  }
}
