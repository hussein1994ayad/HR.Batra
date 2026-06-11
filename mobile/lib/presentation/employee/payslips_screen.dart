// =========================================================================
// نظام HR Pro v6.0 - شاشة كشوف الرواتب الشهرية للموظف (Monthly Payslips Screen)
// =========================================================================

import 'package:flutter/material.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';

class PayslipsScreen extends StatefulWidget {
  const PayslipsScreen({super.key});

  @override
  State<PayslipsScreen> createState() => _PayslipsScreenState();
}

class _PayslipsScreenState extends State<PayslipsScreen> {
  bool _isLoading = true;
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

      // تاريخ البداية: يوم البداية من الشهر السابق
      final prevMonthDate = DateTime(year, month - 1, _cycleStartDay);
      final String startStr = "${prevMonthDate.year}-${prevMonthDate.month.toString().padLeft(2, '0')}-${_cycleStartDay.toString().padLeft(2, '0')}";

      // تاريخ النهاية: يوم النهاية من الشهر الحالي
      final String endStr = "$year-${month.toString().padLeft(2, '0')}-${_cycleEndDay.toString().padLeft(2, '0')}";
      
      return {'start': startStr, 'end': endStr};
    } catch (e) {
      return {'start': '', 'end': ''};
    }
  }

  Future<void> _loadPayslips() async {
    setState(() => _isLoading = true);
    final user = SupabaseService.currentUser;
    if (user == null) return;

    try {
      final data = await SupabaseService.client
          .from('salary_slips')
          .select('*')
          .eq('employee_id', user.id)
          .eq('status', 'published')
          .order('work_month', ascending: false);

      setState(() {
        _slips = List<Map<String, dynamic>>.from(data);
      });
    } catch (e) {
      debugPrint('خطأ في تحميل كشوف الرواتب: $e');
    } finally {
      setState(() => _isLoading = false);
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

      setState(() {
        _slipsDetails[slipId] = List<Map<String, dynamic>>.from(detailsData);
      });
    } catch (e) {
      debugPrint('خطأ في تحميل تفاصيل المكافآت والخصومات: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
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
    final String slipId = slip['id'];
    final String workMonth = slip['work_month'] ?? '0000-00';
    final double basic = (slip['basic_salary'] as num).toDouble();
    final double allowances = (slip['allowances'] as num).toDouble();
    final double deductions = (slip['deductions'] as num).toDouble();
    final double loans = (slip['loans_deduction'] as num).toDouble();
    final double net = (slip['net_salary'] as num).toDouble();

    final String arabicMonth = _getArabicMonthName(workMonth);

    return ExpansionTile(
      title: Text(
        'كشف راتب شهر: $arabicMonth',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontFamily: 'Cairo',
          fontSize: 14,
        ),
      ),
      subtitle: Text(
        'صافي الراتب: ${net.toStringAsFixed(0)} د.ع',
        style: const TextStyle(
          color: AppTheme.neonCyan,
          fontWeight: FontWeight.bold,
          fontFamily: 'Cairo',
          fontSize: 12,
        ),
      ),
      collapsedShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: AppTheme.neonCyan.withOpacity(0.2)),
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppTheme.neonCyan),
      ),
      backgroundColor: const Color(0xFF1E293B).withOpacity(0.35),
      collapsedBackgroundColor: const Color(0xFF1E293B).withOpacity(0.15),
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
                    '${net.toStringAsFixed(0)} د.ع',
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
                            final double amount = (item['amount'] as num).toDouble();
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
                                    '${isBonus ? "+" : "-"}${amount.toStringAsFixed(0)} د.ع',
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
            '${isDeduction ? "-" : "+"}${val.toStringAsFixed(0)} د.ع',
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

  String _getArabicMonthName(String monthStr) {
    try {
      final parts = monthStr.split('-');
      final int month = int.parse(parts[1]);
      final List<String> arabicMonths = [
        'كانون الثاني', 'شباط', 'آذار', 'نيسان', 'أيار', 'حزيران',
        'تموز', 'آب', 'أيلول', 'تشرين الأول', 'تشرين الثاني', 'كانون الأول'
      ];
      return "${arabicMonths[month - 1]} ${parts[0]}";
    } catch (_) {
      return monthStr;
    }
  }
}
