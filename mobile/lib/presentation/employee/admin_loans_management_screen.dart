// =========================================================================
// نظام HR Pro v6.0 - شاشة إدارة ومتابعة سلف الموظفين وكشوف Excel للمدراء
// =========================================================================

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import '../../core/constants/constants.dart';
import '../../core/routes/app_router.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/excel_export_service.dart';
import '../../core/services/file_upload_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../shared/widgets/glass_background.dart';
import '../shared/widgets/glass_container.dart';

class AdminLoansManagementScreen extends StatefulWidget {
  const AdminLoansManagementScreen({super.key});

  @override
  State<AdminLoansManagementScreen> createState() => _AdminLoansManagementScreenState();
}

class _AdminLoansManagementScreenState extends State<AdminLoansManagementScreen> {
  bool _isLoading = true;
  bool _isExporting = false;
  String _searchQuery = '';
  String _selectedStatusFilter = 'all'; // 'all', 'active', 'completed', 'pending'
  String? _selectedBranchFilter = 'all';

  List<Map<String, dynamic>> _loansList = [];
  List<Map<String, dynamic>> _branchesList = [];
  List<Map<String, dynamic>> _employeesList = [];

  // إحصائيات عامة
  double _totalLoansAmount = 0.0;
  double _totalPaidAmount = 0.0;
  double _totalRemainingAmount = 0.0;
  int _activeLoansCount = 0;

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadLoansData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // تحميل بيانات السلف والأقساط والفروع
  Future<void> _loadLoansData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    final user = SupabaseService.currentUser;
    if (user == null) {
      if (mounted) context.go(AppRoutes.login);
      return;
    }

    try {
      // 1. التحقق من صلاحية الإدارة (Admin / Manager)
      final empRole = await SupabaseService.client
          .from('employees')
          .select('role')
          .eq('id', user.id)
          .maybeSingle();

      if (empRole == null || (empRole['role'] != 'admin' && empRole['role'] != 'manager')) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('عذراً، هذه الشاشة مخصصة لحسابات الإدارة والموارد البشرية فقط ⚠️', style: TextStyle(fontFamily: 'Cairo')),
              backgroundColor: AppTheme.dangerRed,
            ),
          );
          context.go(AppRoutes.employeeHome);
        }
        return;
      }

      // 2. جلب الفروع والموظفين النشطين
      final results = await Future.wait([
        SupabaseService.client.from('branches').select('id, name').order('name'),
        SupabaseService.client.from('employees').select('id, full_name, monthly_salary_iqd, branch_id, branches(name)').eq('is_active', true).order('full_name'),
      ]);

      _branchesList = List<Map<String, dynamic>>.from(results[0]);
      _employeesList = List<Map<String, dynamic>>.from(results[1]);

      // 3. جلب جميع السلف مع تفاصيل الموظف والأقساط
      final loansData = await SupabaseService.client
          .from('loans')
          .select('''
            *,
            employees!loans_employee_id_fkey(
              id,
              full_name,
              avatar_url,
              monthly_salary_iqd,
              branch_id,
              department_id,
              branches(name),
              departments!employees_department_id_fkey(name)
            ),
            loan_installments(*)
          ''')
          .order('created_at', ascending: false);

      _loansList = List<Map<String, dynamic>>.from(loansData);

      // 4. حساب الإحصائيات العامة
      _calculateKPIs();

    } catch (e) {
      debugPrint('خطأ في تحميل بيانات السلف: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل تحميل السلف: $e', style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: AppTheme.dangerRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _calculateKPIs() {
    double totalAmt = 0.0;
    double remainingAmt = 0.0;
    int activeCount = 0;

    for (var loan in _loansList) {
      final branchId = loan['employees']?['branch_id']?.toString();
      if (_selectedBranchFilter != null && _selectedBranchFilter != 'all' && branchId != _selectedBranchFilter) {
        continue;
      }

      final status = loan['status'] ?? 'pending';
      if (status == 'approved' || status == 'completed') {
        final double amt = (loan['amount'] as num?)?.toDouble() ?? 0.0;
        final double rem = (loan['remaining_amount'] as num?)?.toDouble() ?? 0.0;
        totalAmt += amt;
        remainingAmt += rem;

        if (rem > 0 && status == 'approved') {
          activeCount++;
        }
      }
    }

    _totalLoansAmount = totalAmt;
    _totalRemainingAmount = remainingAmt;
    _totalPaidAmount = totalAmt - remainingAmt > 0 ? (totalAmt - remainingAmt) : 0.0;
    _activeLoansCount = activeCount;
  }

  // فلترة قائمة السلف بناءً على البحث والفرع والحالة
  List<Map<String, dynamic>> get _filteredLoans {
    return _loansList.where((loan) {
      final empName = loan['employees']?['full_name']?.toString().toLowerCase() ?? '';
      final branchId = loan['employees']?['branch_id']?.toString() ?? '';
      final status = loan['status'] ?? 'pending';
      final double remAmt = (loan['remaining_amount'] as num?)?.toDouble() ?? 0.0;

      // تصفية البحث بالاسم
      if (_searchQuery.isNotEmpty && !empName.contains(_searchQuery.toLowerCase())) {
        return false;
      }

      // تصفية الفرع
      if (_selectedBranchFilter != null && _selectedBranchFilter != 'all' && branchId != _selectedBranchFilter) {
        return false;
      }

      // تصفية الحالة
      if (_selectedStatusFilter == 'active') {
        return status == 'approved' && remAmt > 0;
      } else if (_selectedStatusFilter == 'completed') {
        return status == 'completed' || (status == 'approved' && remAmt <= 0);
      } else if (_selectedStatusFilter == 'pending') {
        return status == 'pending';
      }

      return true;
    }).toList();
  }

  // تصدير كشف حساب Excel لموظف معين
  Future<void> _exportLoanToExcel(Map<String, dynamic> loan) async {
    setState(() => _isExporting = true);
    final empName = loan['employees']?['full_name'] ?? 'الموظف';

    try {
      // استخراج الأقساط وترتيبها
      List<Map<String, dynamic>> installments = [];
      if (loan['loan_installments'] != null) {
        installments = List<Map<String, dynamic>>.from(loan['loan_installments']);
        installments.sort((a, b) => (a['due_date'] ?? '').compareTo(b['due_date'] ?? ''));
      }

      // توليد ملف Excel الاحترافي
      final String filePath = await ExcelExportService.generateLoanStatementExcel(
        loan: loan,
        installments: installments,
      );

      if (!mounted) return;

      // إظهار نافذة تأكيد ومشاركة الملف
      _showExcelSuccessDialog(empName, filePath);

    } catch (e) {
      debugPrint('خطأ في تصدير ملف Excel: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل تصدير ملف Excel: $e', style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: AppTheme.dangerRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  // نافذة نجاح تصدير ملف Excel
  void _showExcelSuccessDialog(String empName, String filePath) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: AppTheme.successGreen.withValues(alpha: 0.4)),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.successGreen.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.table_chart_rounded, color: AppTheme.successGreen, size: 24),
            ),
            const SizedBox(width: 12),
            const Text(
              'تم تصدير كشف Excel بنجاح! 📊',
              style: TextStyle(fontFamily: 'Cairo', fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'تم إنشاء كشف حساب السلفة الاحترافي الخاص بالموظف ($empName) متضمناً كافة التسديدات والملاحظات وجدول الأقساط.',
              style: const TextStyle(fontFamily: 'Cairo', fontSize: 13, color: Colors.white70, height: 1.5),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.folder_rounded, color: AppTheme.neonCyan, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      filePath.split(Platform.pathSeparator).last,
                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, color: AppTheme.neonCyan, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: filePath));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('تم نسخ مسار الملف إلى الحافظة 📋', style: TextStyle(fontFamily: 'Cairo')),
                  backgroundColor: AppTheme.primaryTeal,
                ),
              );
            },
            icon: const Icon(Icons.copy_rounded, size: 18, color: Colors.white70),
            label: const Text('نسخ المسار', style: TextStyle(fontFamily: 'Cairo', color: Colors.white70, fontSize: 11)),
          ),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              ExcelExportService.shareExcelFile(filePath, text: 'كشف حساب سلفة الموظف: $empName');
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.neonCyan,
              side: const BorderSide(color: AppTheme.neonCyan),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.share_rounded, size: 18),
            label: const Text('مشاركة / واتساب 📤', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 11)),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              ExcelExportService.openExcelFile(filePath);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.successGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: const Text('فتح الملف 📊', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 11)),
          ),
        ],
      ),
    );
  }

  // عرض التفاصيل الكاملة لسلفة موظف في نافذة منبثقة تفاعلية
  void _showLoanDetailsSheet(Map<String, dynamic> loan) {
    final emp = loan['employees'] ?? {};
    final String empName = emp['full_name'] ?? 'موظف غير معروف';
    final String avatarUrl = emp['avatar_url'] ?? '';
    final String branchName = emp['branches']?['name'] ?? 'الفرع الرئيسي';
    final String deptName = emp['departments']?['name'] ?? 'عام';
    final double salary = (emp['monthly_salary_iqd'] as num?)?.toDouble() ?? 0.0;
    final double totalAmount = (loan['amount'] as num?)?.toDouble() ?? 0.0;
    final int months = (loan['installment_count'] as num?)?.toInt() ?? 1;
    final double monthly = (loan['installment_amount'] as num?)?.toDouble() ?? 0.0;
    final double remaining = (loan['remaining_amount'] as num?)?.toDouble() ?? 0.0;
    final double paid = totalAmount - remaining > 0 ? (totalAmount - remaining) : 0.0;
    final String status = loan['status'] ?? 'pending';
    final String pledgeUrl = loan['pledge_url'] ?? '';
    final String reason = loan['reason'] ?? loan['notes'] ?? 'لا توجد ملاحظات مسجلة';
    final String loanDate = loan['created_at'] != null 
        ? loan['created_at'].toString().split('T')[0] 
        : '-';

    List<Map<String, dynamic>> installments = [];
    if (loan['loan_installments'] != null) {
      installments = List<Map<String, dynamic>>.from(loan['loan_installments']);
      installments.sort((a, b) => (a['due_date'] ?? '').compareTo(b['due_date'] ?? ''));
    }

    final int paidInstallmentsCount = installments.where((i) => i['is_paid'] == true).length;
    final double progressPercent = totalAmount > 0 ? (paid / totalAmount).clamp(0.0, 1.0) : 0.0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => DraggableScrollableSheet(
          initialChildSize: 0.9,
          minChildSize: 0.5,
          maxChildSize: 0.96,
          builder: (_, scrollController) => Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
              border: Border.all(color: AppTheme.neonCyan.withValues(alpha: 0.3), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.neonCyan.withValues(alpha: 0.15),
                  blurRadius: 30,
                  spreadRadius: 2,
                )
              ],
            ),
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                // مقبض السحب
                Center(
                  child: Container(
                    width: 48,
                    height: 5,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),

                // ترويسة تفاصيل الموظف
                Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: AppTheme.primaryTeal.withValues(alpha: 0.2),
                      backgroundImage: avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                      child: avatarUrl.isEmpty 
                          ? const Icon(Icons.person_rounded, color: AppTheme.neonCyan, size: 28) 
                          : null,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            empName,
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$branchName • $deptName',
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 12,
                              color: Colors.white60,
                            ),
                          ),
                          if (salary > 0)
                            Text(
                              'الراتب الشهري: ${AppConstants.formatMoney(salary)}',
                              style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 11,
                                color: AppTheme.neonCyan,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ),
                    ),
                    // زر التصدير السريع لملف Excel
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _exportLoanToExcel(loan);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.successGreen,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.file_download_rounded, size: 18),
                      label: const Text('Excel 📊', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // بطاقات الموقف المالي (المبلغ الكلي، المدفوع، المتبقي)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          _buildDetailKpiBox('أصل السلفة', AppConstants.formatMoney(totalAmount), Colors.white, Icons.monetization_on_rounded),
                          const SizedBox(width: 10),
                          _buildDetailKpiBox('المبلغ المدفوع', AppConstants.formatMoney(paid), AppTheme.successGreen, Icons.check_circle_rounded),
                          const SizedBox(width: 10),
                          _buildDetailKpiBox('المبلغ المتبقي', AppConstants.formatMoney(remaining), const Color(0xFFF87171), Icons.hourglass_top_rounded),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // شريط نسبة السداد
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'نسبة السداد: ${(progressPercent * 100).toStringAsFixed(1)}%',
                            style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, color: Colors.white70, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'تم تسديد $paidInstallmentsCount من $months أقساط',
                            style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, color: AppTheme.neonCyan, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: LinearProgressIndicator(
                          value: progressPercent,
                          minHeight: 8,
                          backgroundColor: Colors.white10,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            progressPercent >= 1.0 ? AppTheme.successGreen : AppTheme.neonCyan,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // تفاصيل إضافية (تاريخ الطلب، القسط الشهري، الملاحظات)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSheetInfoRow('تاريخ تقديم السلفة', loanDate, Icons.calendar_today_rounded),
                      const Divider(color: Colors.white10, height: 16),
                      _buildSheetInfoRow('القسط الشهري المعتمد', '${AppConstants.formatMoney(monthly)} / الشهر', Icons.payments_rounded),
                      const Divider(color: Colors.white10, height: 16),
                      _buildSheetInfoRow('مدة السداد', '$months أشهر متتالية', Icons.timelapse_rounded),
                      const Divider(color: Colors.white10, height: 16),
                      _buildSheetInfoRow('الملاحظات والسبب', reason, Icons.notes_rounded),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // صورة التعهد الخطي الموقّع (Pledge Document)
                const Text(
                  '📝 صورة التعهد الخطي المرفقة بالسلفة',
                  style: TextStyle(fontFamily: 'Cairo', fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 10),

                if (pledgeUrl.isNotEmpty) ...[
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppTheme.primaryTeal.withValues(alpha: 0.3)),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        // معاينة الصورة
                        GestureDetector(
                          onTap: () => _openFullScreenImage(pledgeUrl, empName),
                          child: Container(
                            height: 180,
                            width: double.infinity,
                            color: Colors.black26,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Image.network(
                                  pledgeUrl,
                                  width: double.infinity,
                                  height: 180,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Center(
                                    child: Icon(Icons.broken_image_rounded, color: Colors.white38, size: 48),
                                  ),
                                  loadingBuilder: (_, child, progress) {
                                    if (progress == null) return child;
                                    return const Center(child: CircularProgressIndicator(color: AppTheme.neonCyan));
                                  },
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.zoom_in_rounded, color: Colors.white, size: 16),
                                      SizedBox(width: 6),
                                      Text('انقر لتكبير صورة التعهد 🔍', style: TextStyle(fontFamily: 'Cairo', fontSize: 11, color: Colors.white)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // زر فتح وتحميل صورة التعهد
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () async {
                                    try {
                                      final uri = Uri.parse(pledgeUrl);
                                      if (await canLaunchUrl(uri)) {
                                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                                      }
                                    } catch (err) {
                                      debugPrint('Error launching pledge: $err');
                                    }
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.primaryTeal,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  icon: const Icon(Icons.download_rounded, size: 18),
                                  label: const Text('تحميل وفتح التعهد الخطي 📥', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 12)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline_rounded, color: Colors.white38, size: 20),
                        SizedBox(width: 10),
                        Text('لم يتم إرفاق صورة تعهد خطي مع هذا الطلب.', style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: Colors.white60)),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                // جدول الأقساط والتسديدات
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '🗓️ جدول الأقساط والتسديدات الشهرية',
                      style: TextStyle(fontFamily: 'Cairo', fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    Text(
                      '${installments.length} أقساط',
                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, color: AppTheme.neonCyan, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                if (installments.isNotEmpty) ...[
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: installments.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, idx) {
                      final inst = installments[idx];
                      final bool isPaid = inst['is_paid'] == true;
                      final double instAmt = (inst['amount'] as num?)?.toDouble() ?? 0.0;
                      final String dueDate = inst['due_date'] ?? '-';
                      final String? paidAt = inst['paid_at'];

                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: isPaid ? AppTheme.successGreen.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isPaid ? AppTheme.successGreen.withValues(alpha: 0.3) : Colors.white10,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: isPaid ? AppTheme.successGreen : Colors.white12,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '${idx + 1}',
                                style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'تاريخ الاستحقاق: $dueDate',
                                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                                  ),
                                  if (isPaid && paidAt != null)
                                    Text(
                                      'تم التسديد بتاريخ: ${paidAt.split('T')[0]}',
                                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 10, color: AppTheme.successGreen),
                                    ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  AppConstants.formatMoney(instAmt),
                                  style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: isPaid ? AppTheme.successGreen : Colors.white,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  margin: const EdgeInsets.only(top: 2),
                                  decoration: BoxDecoration(
                                    color: isPaid ? AppTheme.successGreen.withValues(alpha: 0.2) : Colors.amber.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    isPaid ? 'مسدد ✅' : 'متبقي ⏳',
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: isPaid ? AppTheme.successGreen : Colors.amber,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Text('لم يتم توليد أقساط لهذه السلفة بعد.', style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: Colors.white60)),
                  ),
                ],

                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // عرض الصورة بحجم الشاشة الكامل مع إمكانية التكبير والتصغير
  void _openFullScreenImage(String imageUrl, String title) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            InteractiveViewer(
              panEnabled: true,
              boundaryMargin: const EdgeInsets.all(20),
              minScale: 0.5,
              maxScale: 4.0,
              child: Center(
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Center(
                    child: Text('تعذر تحميل الصورة', style: TextStyle(color: Colors.white, fontFamily: 'Cairo')),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 40,
              right: 20,
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white, size: 30),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            Positioned(
              bottom: 30,
              left: 20,
              right: 20,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Text(
                    'تعهد سلفة: $title 📝',
                    style: const TextStyle(fontFamily: 'Cairo', color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailKpiBox(String title, String value, Color valueColor, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: valueColor),
            const SizedBox(height: 6),
            Text(
              title,
              style: const TextStyle(fontFamily: 'Cairo', fontSize: 10, color: Colors.white60),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold, color: valueColor),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSheetInfoRow(String title, String value, IconData icon) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppTheme.neonCyan),
        const SizedBox(width: 10),
        Text(
          '$title: ',
          style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, color: Colors.white60, fontWeight: FontWeight.w600),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  // نافذة إضافة سلفة جديدة مباشرة لموظف من قبل الإدارة
  void _showCreateLoanDialog() {
    String? selectedEmpId;
    final amountController = TextEditingController();
    final monthsController = TextEditingController(text: '5');
    final reasonController = TextEditingController();
    File? pledgeFile;
    bool isSubmittingDialog = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            top: 24,
            left: 20,
            right: 20,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            border: Border.all(color: AppTheme.neonCyan.withValues(alpha: 0.4), width: 1.5),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.add_circle_rounded, color: AppTheme.neonCyan, size: 24),
                        SizedBox(width: 10),
                        Text(
                          'إضافة سلفة جديدة لموظف ➕',
                          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white60),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // اختيار الموظف
                const Text('اختر الموظف المستفيد:', style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: Colors.white70, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      dropdownColor: const Color(0xFF1E293B),
                      value: selectedEmpId,
                      hint: const Text('اضغط لاختيار موظف...', style: TextStyle(fontFamily: 'Cairo', color: Colors.white38, fontSize: 12)),
                      items: _employeesList.map((emp) {
                        final name = emp['full_name'] ?? 'بدون اسم';
                        final branch = emp['branches']?['name'] ?? '';
                        return DropdownMenuItem<String>(
                          value: emp['id'] as String,
                          child: Text('$name ($branch)', style: const TextStyle(fontFamily: 'Cairo', color: Colors.white, fontSize: 13)),
                        );
                      }).toList(),
                      onChanged: (val) => setDialogState(() => selectedEmpId = val),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // مبلغ السلفة
                const Text('مبلغ السلفة الإجمالي (دينار عراقي):', style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: Colors.white70, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                TextField(
                  controller: amountController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontFamily: 'Cairo', color: Colors.white, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    hintText: 'مثال: 1000000',
                    hintStyle: const TextStyle(fontFamily: 'Cairo', color: Colors.white38, fontSize: 12),
                    suffixText: 'د.ع',
                    suffixStyle: const TextStyle(fontFamily: 'Cairo', color: AppTheme.neonCyan, fontWeight: FontWeight.bold),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.06),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Colors.white12)),
                  ),
                ),
                const SizedBox(height: 14),

                // عدد الأشهر / الأقساط
                const Text('مدة السداد (عدد الأشهر):', style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: Colors.white70, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                TextField(
                  controller: monthsController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontFamily: 'Cairo', color: Colors.white, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    hintText: 'مثال: 5',
                    hintStyle: const TextStyle(fontFamily: 'Cairo', color: Colors.white38, fontSize: 12),
                    suffixText: 'أشهر',
                    suffixStyle: const TextStyle(fontFamily: 'Cairo', color: AppTheme.neonCyan, fontWeight: FontWeight.bold),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.06),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Colors.white12)),
                  ),
                ),
                const SizedBox(height: 14),

                // سبب وملاحظات السلفة
                const Text('ملاحظات وسبب منح السلفة:', style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: Colors.white70, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                TextField(
                  controller: reasonController,
                  maxLines: 2,
                  style: const TextStyle(fontFamily: 'Cairo', color: Colors.white, fontSize: 12),
                  decoration: InputDecoration(
                    hintText: 'اكتب تفاصيل أو سبب منح السلفة...',
                    hintStyle: const TextStyle(fontFamily: 'Cairo', color: Colors.white38, fontSize: 12),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.06),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Colors.white12)),
                  ),
                ),
                const SizedBox(height: 14),

                // إرفاق صورة التعهد الخطي
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final picker = ImagePicker();
                          final picked = await picker.pickImage(source: ImageSource.camera, imageQuality: 80);
                          if (picked != null) {
                            setDialogState(() => pledgeFile = File(picked.path));
                          }
                        },
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: pledgeFile != null ? AppTheme.successGreen : AppTheme.neonCyan.withValues(alpha: 0.5)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        icon: Icon(pledgeFile != null ? Icons.check_circle_rounded : Icons.camera_alt_rounded, color: pledgeFile != null ? AppTheme.successGreen : AppTheme.neonCyan, size: 18),
                        label: Text(
                          pledgeFile != null ? 'تم التقاط صورة التعهد ✅' : 'تصوير التعهد الخطي 📷',
                          style: TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold, color: pledgeFile != null ? AppTheme.successGreen : Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // زر الحفظ والاعتماد
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: isSubmittingDialog
                        ? null
                        : () async {
                            if (selectedEmpId == null) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يرجى اختيار الموظف المستفيد أولاً!', style: TextStyle(fontFamily: 'Cairo')), backgroundColor: AppTheme.dangerRed));
                              return;
                            }
                            final double? amount = double.tryParse(amountController.text.replaceAll(',', '').trim());
                            final int? months = int.tryParse(monthsController.text.trim());
                            if (amount == null || amount <= 0) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يرجى إدخال مبلغ سلفة صحيح أكبر من الصفر!', style: TextStyle(fontFamily: 'Cairo')), backgroundColor: AppTheme.dangerRed));
                              return;
                            }
                            if (months == null || months <= 0) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يرجى إدخال عدد أشهر سداد صحيح (شهر واحد على الأقل)!', style: TextStyle(fontFamily: 'Cairo')), backgroundColor: AppTheme.dangerRed));
                              return;
                            }

                            setDialogState(() => isSubmittingDialog = true);
                            final adminUser = SupabaseService.currentUser;

                            try {
                              String? pledgeUrl;
                              if (pledgeFile != null) {
                                final ext = pledgeFile!.path.split('.').last;
                                final remotePath = 'pledges/$selectedEmpId/${const Uuid().v4()}.$ext';
                                pledgeUrl = await FileUploadService.uploadFile(
                                  bucketName: 'loan-pledges',
                                  remotePath: remotePath,
                                  file: pledgeFile!,
                                );
                              }

                              final int baseInstallment = (amount / months).floor();
                              final int remainder = (amount - (baseInstallment * months)).round();
                              final double monthlyAmt = baseInstallment.toDouble();

                              // 1. إدراج السلفة
                              final insertedLoan = await SupabaseService.client.from('loans').insert({
                                'employee_id': selectedEmpId,
                                'amount': amount,
                                'installment_count': months,
                                'installment_amount': monthlyAmt,
                                'remaining_amount': amount,
                                'pledge_url': pledgeUrl,
                                'status': 'approved',
                                'reason': reasonController.text.trim().isEmpty ? 'سلفة إدارية مباشرة' : reasonController.text.trim(),
                                'approved_by': adminUser?.id,
                                'approved_at': DateTime.now().toUtc().toIso8601String(),
                              }).select().single();

                              final String loanId = insertedLoan['id'];

                              // 2. توليد الأقساط الشهرية مع توزيع الباقي على القسط الأخير
                              final List<Map<String, dynamic>> installments = [];
                              final now = DateTime.now();
                              for (int i = 1; i <= months; i++) {
                                final due = DateTime(now.year, now.month + i, 1);
                                final double instAmt = (i == months) ? (baseInstallment + remainder).toDouble() : baseInstallment.toDouble();
                                installments.add({
                                  'loan_id': loanId,
                                  'due_date': due.toIso8601String().split('T')[0],
                                  'amount': instAmt,
                                  'is_paid': false,
                                });
                              }

                              await SupabaseService.client.from('loan_installments').insert(installments);

                              // 3. إشعار الموظف
                              try {
                                await SupabaseService.client.from('notifications').insert({
                                  'employee_id': selectedEmpId,
                                  'title': 'تم منحك سلفة مالية جديدة 💸',
                                  'body': 'تم اعتماد سلفة جديدة لك بقيمة ${AppConstants.formatMoney(amount)} مقسمة على $months أقساط شهرية.',
                                  'type': 'loan',
                                });
                              } catch (_) {}

                              if (ctx.mounted) {
                                Navigator.pop(ctx);
                              }
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('تمت إضافة واعتماد السلفة وتوليد الأقساط بنجاح ✅', style: TextStyle(fontFamily: 'Cairo')),
                                    backgroundColor: AppTheme.successGreen,
                                  ),
                                );
                                _loadLoansData();
                              }
                            } catch (err) {
                              debugPrint('Error creating direct loan: $err');
                              setDialogState(() => isSubmittingDialog = false);
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('فشل إضافة السلفة: $err', style: const TextStyle(fontFamily: 'Cairo')), backgroundColor: AppTheme.dangerRed),
                                );
                              }
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.successGreen,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: isSubmittingDialog
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('حفظ واعتماد السلفة مباشرة 💸', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 14)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: FloatingActionButton.extended(
          heroTag: 'create_loan_admin_fab',
          backgroundColor: AppTheme.primaryTeal,
          foregroundColor: Colors.white,
          elevation: 4,
          icon: const Icon(Icons.add_circle_outline_rounded),
          label: const Text(
            'إضافة سلفة لموظف ➕',
            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13),
          ),
          onPressed: _showCreateLoanDialog,
        ),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text(
            'متابعة سلف وأقساط الموظفين 💼',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Colors.white,
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: AppTheme.neonCyan),
              tooltip: 'تحديث البيانات',
              onPressed: _loadLoansData,
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(165),
            child: Column(
              children: [
                // 1. شريط البحث باسم الموظف
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
                  child: Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: TextField(
                      controller: _searchController,
                      style: const TextStyle(fontFamily: 'Cairo', color: Colors.white, fontSize: 12),
                      onChanged: (val) => setState(() => _searchQuery = val),
                      decoration: InputDecoration(
                        hintText: 'البحث باسم الموظف المستلف...',
                        hintStyle: const TextStyle(fontFamily: 'Cairo', color: Colors.white38, fontSize: 11),
                        prefixIcon: const Icon(Icons.search_rounded, color: Colors.white60, size: 18),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, color: Colors.white60, size: 16),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                ),

                // 2. قائمة اختيار الفروع (جميع الفروع أو فرع محدد)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
                  child: Container(
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _selectedBranchFilter != 'all' ? AppTheme.neonCyan : Colors.white12,
                        width: _selectedBranchFilter != 'all' ? 1.5 : 1.0,
                      ),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        dropdownColor: const Color(0xFF0F172A),
                        value: _selectedBranchFilter,
                        icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppTheme.neonCyan, size: 20),
                        items: [
                          const DropdownMenuItem<String>(
                            value: 'all',
                            child: Row(
                              children: [
                                Icon(Icons.domain_rounded, color: AppTheme.neonCyan, size: 16),
                                SizedBox(width: 8),
                                Text(
                                  '🏢 جميع الفروع (كافة الموظفين)',
                                  style: TextStyle(fontFamily: 'Cairo', color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                          ..._branchesList.map((branch) {
                            return DropdownMenuItem<String>(
                              value: branch['id'] as String,
                              child: Row(
                                children: [
                                  const Icon(Icons.storefront_rounded, color: AppTheme.successGreen, size: 16),
                                  const SizedBox(width: 8),
                                  Text(
                                    'فرع: ${branch['name']}',
                                    style: const TextStyle(fontFamily: 'Cairo', color: Colors.white, fontSize: 12),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                        onChanged: (val) {
                          setState(() {
                            _selectedBranchFilter = val;
                            _calculateKPIs();
                          });
                        },
                      ),
                    ),
                  ),
                ),

                // 3. فلاتر الحالة
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    children: [
                      _buildFilterChip('الكل', 'all'),
                      const SizedBox(width: 8),
                      _buildFilterChip('سلف نشطة (عليها متبقي)', 'active'),
                      const SizedBox(width: 8),
                      _buildFilterChip('مسددة بالكامل', 'completed'),
                      const SizedBox(width: 8),
                      _buildFilterChip('طلبات معلقة', 'pending'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AppTheme.neonCyan))
            : RefreshIndicator(
                onRefresh: _loadLoansData,
                color: AppTheme.neonCyan,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    // 1. بطاقات الإحصائيات العامة (KPIs)
                    _buildTopStatsCards(),

                    const SizedBox(height: 16),

                    // 2. عنوان القائمة والعدد
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'قائمة المستلفين (${_filteredLoans.length})',
                          style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                        ),
                        if (_isExporting)
                          const Row(
                            children: [
                              SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.successGreen)),
                              SizedBox(width: 6),
                              Text('جاري إنشاء Excel...', style: TextStyle(fontFamily: 'Cairo', fontSize: 11, color: AppTheme.successGreen)),
                            ],
                          ),
                      ],
                    ),

                    const SizedBox(height: 10),

                    // 3. قائمة الموظفين
                    if (_filteredLoans.isEmpty)
                      _buildEmptyState()
                    else
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _filteredLoans.length,
                        itemBuilder: (context, index) {
                          final loan = _filteredLoans[index];
                          return _buildLoanCard(loan);
                        },
                      ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final bool isSelected = _selectedStatusFilter == value;
    return GestureDetector(
      onTap: () => setState(() => _selectedStatusFilter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryTeal : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppTheme.neonCyan : Colors.white12,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? Colors.white : Colors.white70,
          ),
        ),
      ),
    );
  }

  Widget _buildTopStatsCards() {
    return GlassContainer(
      padding: const EdgeInsets.all(16),
      borderRadius: 22,
      opacity: 0.08,
      borderColor: AppTheme.neonCyan.withValues(alpha: 0.2),
      child: Column(
        children: [
          Row(
            children: [
              _buildKpiCardItem(
                'إجمالي السلف الممنوحة',
                AppConstants.formatMoney(_totalLoansAmount),
                Colors.white,
                Icons.account_balance_wallet_rounded,
                AppTheme.primaryTeal.withValues(alpha: 0.2),
              ),
              const SizedBox(width: 10),
              _buildKpiCardItem(
                'إجمالي المبالغ المسددة',
                AppConstants.formatMoney(_totalPaidAmount),
                AppTheme.successGreen,
                Icons.task_alt_rounded,
                AppTheme.successGreen.withValues(alpha: 0.2),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _buildKpiCardItem(
                'المتبقي بذمة الموظفين',
                AppConstants.formatMoney(_totalRemainingAmount),
                const Color(0xFFF87171),
                Icons.hourglass_bottom_rounded,
                const Color(0xFFEF4444).withValues(alpha: 0.2),
              ),
              const SizedBox(width: 10),
              _buildKpiCardItem(
                'السلف النشطة الجارية',
                '$_activeLoansCount موظف',
                AppTheme.neonCyan,
                Icons.people_alt_rounded,
                AppTheme.neonCyan.withValues(alpha: 0.2),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKpiCardItem(String title, String value, Color valColor, IconData icon, Color iconBg) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: valColor, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 10, color: Colors.white60),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      value,
                      style: TextStyle(fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.bold, color: valColor),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoanCard(Map<String, dynamic> loan) {
    final emp = loan['employees'] ?? {};
    final String empName = emp['full_name'] ?? 'موظف غير معروف';
    final String avatarUrl = emp['avatar_url'] ?? '';
    final String branchName = emp['branches']?['name'] ?? 'الفرع الرئيسي';
    final double totalAmount = (loan['amount'] as num?)?.toDouble() ?? 0.0;
    final int months = (loan['installment_count'] as num?)?.toInt() ?? 1;
    final double remaining = (loan['remaining_amount'] as num?)?.toDouble() ?? 0.0;
    final double paid = totalAmount - remaining > 0 ? (totalAmount - remaining) : 0.0;
    final String status = loan['status'] ?? 'pending';
    final double progressPercent = totalAmount > 0 ? (paid / totalAmount).clamp(0.0, 1.0) : 0.0;

    List<Map<String, dynamic>> installments = [];
    if (loan['loan_installments'] != null) {
      installments = List<Map<String, dynamic>>.from(loan['loan_installments']);
    }
    final int paidCount = installments.where((i) => i['is_paid'] == true).length;

    Color badgeBg;
    Color badgeText;
    String badgeTitle;

    if (status == 'pending') {
      badgeBg = Colors.amber.withValues(alpha: 0.2);
      badgeText = Colors.amber;
      badgeTitle = 'طلب معلق ⏳';
    } else if (remaining <= 0 || status == 'completed') {
      badgeBg = AppTheme.successGreen.withValues(alpha: 0.2);
      badgeText = AppTheme.successGreen;
      badgeTitle = 'مسددة بالكامل 🏁';
    } else if (status == 'rejected') {
      badgeBg = AppTheme.dangerRed.withValues(alpha: 0.2);
      badgeText = AppTheme.dangerRed;
      badgeTitle = 'مرفوضة ❌';
    } else {
      badgeBg = AppTheme.neonCyan.withValues(alpha: 0.2);
      badgeText = AppTheme.neonCyan;
      badgeTitle = 'سلفة نشطة 💸';
    }

    return GlassContainer(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      borderRadius: 18,
      opacity: 0.06,
      borderColor: Colors.white12,
      child: InkWell(
        onTap: () => _showLoanDetailsSheet(loan),
        borderRadius: BorderRadius.circular(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ترويسة الموظف
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: AppTheme.primaryTeal.withValues(alpha: 0.2),
                  backgroundImage: avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                  child: avatarUrl.isEmpty 
                      ? const Icon(Icons.person_rounded, color: AppTheme.neonCyan, size: 20) 
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        empName,
                        style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                      ),
                      Text(
                        branchName,
                        style: const TextStyle(fontFamily: 'Cairo', fontSize: 10, color: Colors.white60),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: badgeBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    badgeTitle,
                    style: TextStyle(fontFamily: 'Cairo', fontSize: 10, fontWeight: FontWeight.bold, color: badgeText),
                  ),
                ),
              ],
            ),

            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Divider(color: Colors.white10, height: 1),
            ),

            // مبالغ السلفة
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('المبلغ الكلي', style: TextStyle(fontFamily: 'Cairo', fontSize: 10, color: Colors.white60)),
                    Text(
                      AppConstants.formatMoney(totalAmount),
                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Text('المسدد', style: TextStyle(fontFamily: 'Cairo', fontSize: 10, color: Colors.white60)),
                    Text(
                      AppConstants.formatMoney(paid),
                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.successGreen),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('المتبقي بذمته', style: TextStyle(fontFamily: 'Cairo', fontSize: 10, color: Colors.white60)),
                    Text(
                      AppConstants.formatMoney(remaining),
                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFFF87171)),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 10),

            // شريط التقدم وزر Excel
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: progressPercent,
                          minHeight: 6,
                          backgroundColor: Colors.white10,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            progressPercent >= 1.0 ? AppTheme.successGreen : AppTheme.neonCyan,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'الأقساط المسددة: $paidCount من $months أقساط (${(progressPercent * 100).toStringAsFixed(0)}%)',
                        style: const TextStyle(fontFamily: 'Cairo', fontSize: 10, color: Colors.white60),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                InkWell(
                  onTap: () => _exportLoanToExcel(loan),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.successGreen.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.successGreen.withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.file_download_outlined, color: AppTheme.successGreen, size: 15),
                        SizedBox(width: 4),
                        Text('Excel', style: TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.successGreen)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off_rounded, size: 64, color: Colors.white.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            const Text(
              'لا توجد سجلات سلف مطابقة للبحث أو الفلتر المختار',
              style: TextStyle(fontFamily: 'Cairo', fontSize: 13, color: Colors.white60),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
