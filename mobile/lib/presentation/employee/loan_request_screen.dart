// =========================================================================
// نظام HR Pro v6.0 - شاشة القروض والسلف الآلية (Automated Loans & Installments Screen)
// =========================================================================

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../../core/services/supabase_service.dart';
import '../../core/services/file_upload_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/constants.dart';
import '../shared/widgets/glass_container.dart';

class LoanRequestScreen extends StatefulWidget {
  const LoanRequestScreen({super.key});

  @override
  State<LoanRequestScreen> createState() => _LoanRequestScreenState();
}

class _LoanRequestScreenState extends State<LoanRequestScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // حقول حاسبة القروض
  double _requestedAmount = 500000; // 500,000 دينار عراقي كحد أدنى افتراضي
  double _monthlyInstallment = 250000; // قسط افتراضي
  
  File? _pledgeFile;
  bool _isSubmitting = false;
  bool _isLoadingHistory = true;

  List<Map<String, dynamic>> _loansHistory = [];

  late TextEditingController _amountController;
  late TextEditingController _installmentController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _amountController = TextEditingController(text: _requestedAmount.toStringAsFixed(0));
    _installmentController = TextEditingController(text: _monthlyInstallment.toStringAsFixed(0));
    _loadLoansHistory();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _amountController.dispose();
    _installmentController.dispose();
    super.dispose();
  }

  // تحميل تاريخ القروض والأقساط الخاصة بالموظف
  Future<void> _loadLoansHistory() async {
    final user = SupabaseService.currentUser;
    if (user == null) return;

    try {
      // جلب السلف مصحوبة ببيانات الأقساط إن وجدت
      final data = await SupabaseService.client
          .from('loans')
          .select('*, loan_installments(*)')
          .eq('employee_id', user.id)
          .order('created_at', ascending: false);

      setState(() {
        _loansHistory = List<Map<String, dynamic>>.from(data);
      });
    } catch (e) {
      debugPrint('خطأ في تحميل تاريخ السلف: $e');
    } finally {
      setState(() => _isLoadingHistory = false);
    }
  }

  // التقاط صورة التعهد الخطي الموقّع والملزم قانونياً
  Future<void> _pickPledge() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.camera, // التقاط فوري عبر الكاميرا لزيادة الموثوقية
      imageQuality: 80,
    );

    if (pickedFile != null) {
      setState(() {
        _pledgeFile = File(pickedFile.path);
      });
    }
  }

  // تقديم طلب السلفة
  Future<void> _submitLoanRequest() async {
    if (_pledgeFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يجب عليك تصوير وإرفاق التعهد الخطي الموقّع لاستكمال الطلب ⚠️', style: TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppTheme.dangerRed,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    final user = SupabaseService.currentUser;
    if (user == null) return;

    try {
      // 1. رفع صورة التعهد إلى bucket مخصصة 'loan-pledges' مع تفعيل الضغط التلقائي الفوري للحماية
      final uniqueId = const Uuid().v4();
      final fileExtension = _pledgeFile!.path.split('.').last;
      final remotePath = 'pledges/${user.id}/$uniqueId.$fileExtension';

      final pledgeUrl = await FileUploadService.uploadFile(
        file: _pledgeFile!,
        bucketName: 'loan-pledges',
        remotePath: remotePath,
      );

      final int installmentCount = (_requestedAmount / _monthlyInstallment).ceil();

      // 2. إدراج طلب السلفة
      await SupabaseService.client.from('loans').insert({
        'employee_id': user.id,
        'amount': _requestedAmount,
        'installment_amount': _monthlyInstallment,
        'installment_count': installmentCount,
        'remaining_amount': _requestedAmount,
        'pledge_url': pledgeUrl,
        'status': 'pending',
      });

      // جلب اسم الموظف الحالي لإدراجه في نص إشعار المسؤولين
      String empName = 'موظف';
      try {
        final empProfile = await SupabaseService.client
            .from('employees')
            .select('full_name')
            .eq('id', user.id)
            .maybeSingle();
        if (empProfile != null && empProfile['full_name'] != null) {
          empName = empProfile['full_name'];
        }
      } catch (e) {
        debugPrint('خطأ في جلب اسم الموظف: $e');
      }

      // 3. تسجيل الإشعار بالطلب الجديد للموظف نفسه
      await SupabaseService.client.from('notifications').insert({
        'employee_id': user.id,
        'title': 'طلب سلفة جديدة 💰',
        'body': 'تم تقديم طلب السلفة المالية بقيمة (${_requestedAmount.toStringAsFixed(0)} ${AppConstants.currency}) رسمياً للإدارة المالية للتدقيق.',
        'type': 'loan',
      });

      // 4. إشعار المدراء والمسؤولين
      try {
        final List<dynamic> admins = await SupabaseService.client
            .from('employees')
            .select('id')
            .or('role.eq.admin,role.eq.manager');
        
        for (var admin in admins) {
          if (admin['id'] != null && admin['id'] != user.id) {
            await SupabaseService.client.from('notifications').insert({
              'employee_id': admin['id'],
              'title': 'طلب سلفة جديدة معلق 💰',
              'body': 'قدم الموظف ($empName) طلب سلفة مالية بقيمة (${_requestedAmount.toStringAsFixed(0)} ${AppConstants.currency}) على أقساط لمدة ($installmentCount أشهر).',
              'type': 'loan',
            });
          }
        }
      } catch (e) {
        debugPrint('خطأ في إرسال إشعارات السلفة للمسؤولين: $e');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إرسال طلب السلفة والتعهد بنجاح للإدارة المالية! 🎉', style: TextStyle(fontFamily: 'Cairo')),
            backgroundColor: AppTheme.successGreen,
          ),
        );
        setState(() {
          _pledgeFile = null;
          _requestedAmount = 500000;
          _monthlyInstallment = 250000;
        });
        _tabController.animateTo(1); // الانتقال لتبويب السجل
        _loadLoansHistory();
      }

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ في تقديم السلفة: $e', style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: AppTheme.dangerRed,
          ),
        );
      }
    } finally {
      setState(() => _isSubmitting = false);
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
        title: const Text(
          'بوابة القروض والسلف الماليّة',
          style: TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.neonCyan,
          labelColor: AppTheme.neonCyan,
          unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13),
          tabs: const [
            Tab(text: 'حاسبة وطلب سلفة', icon: Icon(Icons.calculate_rounded)),
            Tab(text: 'سجل وأقساط السلف', icon: Icon(Icons.receipt_long_rounded)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // تبويب 1: حاسبة وتقديم الطلب
          SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // لوحة حاسبة القروض التفاعلية الخلابة
                _buildCalculatorCard(isDark),
                const SizedBox(height: 24),
                
                // لوحة التعهد الخطي الموقّع الإلزامي
                _buildPledgeCard(isDark),
                const SizedBox(height: 32),

                // زر الإرسال النهائي
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.neonCyan.withOpacity(_isSubmitting ? 0.1 : 0.3),
                        blurRadius: 16,
                        spreadRadius: 1,
                      )
                    ],
                  ),
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _submitLoanRequest,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.neonCyan,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    child: _isSubmitting
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                            'تقديم طلب السلفة رسمياً',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
          
          // تبويب 2: تاريخ السلف والأقساط
          _buildLoansHistoryTab(isDark),
        ],
      ),
    );
  }

  // بطاقة حاسبة السلف التفاعلية
  Widget _buildCalculatorCard(bool isDark) {
    final int months = _monthlyInstallment > 0 ? (_requestedAmount / _monthlyInstallment).ceil() : 0;

    return GlassContainer(
      padding: const EdgeInsets.all(20),
      borderRadius: 24,
      opacity: 0.1,
      borderColor: AppTheme.neonCyan.withOpacity(0.2),
      boxShadow: [
        BoxShadow(
          color: AppTheme.neonCyan.withOpacity(0.04),
          blurRadius: 20,
        )
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.monetization_on, color: AppTheme.neonCyan),
              SizedBox(width: 8),
              Text(
                'طلب السلفة المالية والأقساط الشهرية',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, fontFamily: 'Cairo', color: Colors.white),
              ),
            ],
          ),
          const Divider(height: 24, color: Colors.white12),

          // حقل إدخال قيمة السلفة المطلوبة يدوياً
          const Text(
            'المبلغ المطلوب سلفته (د.ع)',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white70, fontFamily: 'Cairo'),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _amountController,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.white, fontSize: 14, fontFamily: 'Cairo', fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.white.withOpacity(0.04),
              prefixIcon: const Icon(Icons.edit_note_rounded, color: AppTheme.neonCyan),
              suffixText: 'د.ع',
              suffixStyle: const TextStyle(color: AppTheme.neonCyan, fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: AppTheme.neonCyan),
              ),
            ),
            onChanged: (val) {
              final double? parsed = double.tryParse(val.replaceAll(RegExp(r'[^0-9]'), ''));
              if (parsed != null) {
                setState(() {
                  _requestedAmount = parsed;
                });
              }
            },
          ),
          
          const SizedBox(height: 16),
          
          // حقل إدخال القسط الشهري
          const Text(
            'القسط الشهري المرجو سداده (د.ع)',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white70, fontFamily: 'Cairo'),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _installmentController,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.white, fontSize: 14, fontFamily: 'Cairo', fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.white.withOpacity(0.04),
              prefixIcon: const Icon(Icons.edit_calendar_rounded, color: AppTheme.neonCyan),
              suffixText: 'د.ع / شهر',
              suffixStyle: const TextStyle(color: AppTheme.neonCyan, fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: AppTheme.neonCyan),
              ),
            ),
            onChanged: (val) {
              final double? parsed = double.tryParse(val.replaceAll(RegExp(r'[^0-9]'), ''));
              if (parsed != null && parsed > 0) {
                setState(() {
                  _monthlyInstallment = parsed;
                });
              }
            },
          ),
          const Divider(height: 24, color: Colors.white12),

          // النتيجة النهائية للأقساط
          GlassContainer(
            padding: const EdgeInsets.all(16),
            borderRadius: 16,
            opacity: 0.12,
            borderColor: AppTheme.neonCyan.withOpacity(0.3),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'عدد الأشهر المقدرة للسداد:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white70, fontFamily: 'Cairo'),
                ),
                Text(
                  '$months أشهر',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: AppTheme.neonCyan, fontFamily: 'Cairo'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // بطاقة رفع التعهد الخطي الموقّع
  Widget _buildPledgeCard(bool isDark) {
    return GlassContainer(
      padding: const EdgeInsets.all(20),
      borderRadius: 24,
      opacity: 0.1,
      borderColor: AppTheme.warningOrange.withOpacity(0.2),
      boxShadow: [
        BoxShadow(
          color: AppTheme.warningOrange.withOpacity(0.04),
          blurRadius: 20,
        )
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.assignment_turned_in_rounded, color: AppTheme.warningOrange),
              SizedBox(width: 8),
              Text(
                'التعهد الخطي الملزم قانونياً',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, fontFamily: 'Cairo', color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'قوانين الرقابة تفرض توقيع تعهد سحب سلفة خطياً من الإدارة. يرجى توقيع التعهد، ثم التقاط صورة واضحة للتعهد المكتوب والموقع ورفعها هنا لمراجعة طلبك.',
            style: TextStyle(fontSize: 11, color: Colors.white70, height: 1.6, fontFamily: 'Cairo'),
          ),
          const SizedBox(height: 20),

          InkWell(
            onTap: _pickPledge,
            child: GlassContainer(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              borderRadius: 16,
              opacity: 0.08,
              borderColor: _pledgeFile != null ? AppTheme.successGreen.withOpacity(0.4) : Colors.white12,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    _pledgeFile != null ? Icons.check_circle : Icons.camera_alt_outlined,
                    color: _pledgeFile != null ? AppTheme.successGreen : AppTheme.neonCyan,
                    size: 32,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _pledgeFile != null 
                        ? 'تم تصوير وإرفاق التعهد بنجاح! 📸' 
                        : 'انقر لفتح الكاميرا وتصوير التعهد الموقّع',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: _pledgeFile != null ? AppTheme.successGreen : AppTheme.neonCyan,
                      fontFamily: 'Cairo',
                    ),
                  ),
                  if (_pledgeFile != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'الملف: ${_pledgeFile!.path.split("/").last}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 10, color: Colors.white54, fontFamily: 'Cairo'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // تبويب السجل وعرض الأقساط
  Widget _buildLoansHistoryTab(bool isDark) {
    if (_isLoadingHistory) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.neonCyan));
    }

    if (_loansHistory.isEmpty) {
      return const Center(
        child: Text(
          'لا توجد سجلات سلف سابقة لك حالياً ✨',
          style: TextStyle(fontSize: 12, color: Colors.white70, fontFamily: 'Cairo'),
        ),
      );
    }

    final statusLabel = {
      'pending': 'قيد الدراسة 🟡',
      'approved': 'معتمدة ومصروفة 🟢',
      'rejected': 'مرفوضة من الإدارة 🔴',
    };

    return RefreshIndicator(
      onRefresh: _loadLoansHistory,
      color: AppTheme.neonCyan,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _loansHistory.length,
        separatorBuilder: (_, __) => const SizedBox(height: 16),
        itemBuilder: (context, index) {
          final loan = _loansHistory[index];
          final double amount = (loan['amount'] as num).toDouble();
          final double remaining = (loan['remaining_amount'] as num).toDouble();
          final double installmentAmount = (loan['installment_amount'] as num).toDouble();
          final status = loan['status'] ?? 'pending';

          final color = _getStatusColor(status);

          return GlassContainer(
            padding: const EdgeInsets.all(18),
            borderRadius: 20,
            opacity: 0.1,
            borderColor: color.withOpacity(0.2),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.04),
                blurRadius: 16,
              )
            ],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'سلفة مالية بقيمة ${amount.toStringAsFixed(0)} ${AppConstants.currency}',
                       style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Colors.white, fontFamily: 'Cairo'),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: color.withOpacity(0.3), width: 1),
                      ),
                      child: Text(
                        statusLabel[status] ?? 'غير معروف',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color, fontFamily: 'Cairo'),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24, color: Colors.white12),
                
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('القسط الشهري', style: TextStyle(fontSize: 10, color: Colors.white54, fontFamily: 'Cairo')),
                          const SizedBox(height: 4),
                          Text('${installmentAmount.toStringAsFixed(0)} ${AppConstants.currency}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white, fontFamily: 'Cairo')),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('المتبقي للسداد', style: TextStyle(fontSize: 10, color: Colors.white54, fontFamily: 'Cairo')),
                          const SizedBox(height: 4),
                          Text('${remaining.toStringAsFixed(0)} ${AppConstants.currency}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.neonCyan, fontFamily: 'Cairo')),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('الأقساط (الأشهر)', style: TextStyle(fontSize: 10, color: Colors.white54, fontFamily: 'Cairo')),
                          const SizedBox(height: 4),
                          Text('${loan["installment_count"]} أشهر', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white, fontFamily: 'Cairo')),
                        ],
                      ),
                    ),
                  ],
                ),
                if (status == 'approved' && (loan['loan_installments'] != null && (loan['loan_installments'] as List).isNotEmpty)) ...[
                  const Divider(height: 24, color: Colors.white12),
                  const Text(
                    'جدول سداد الأقساط الشهرية:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.white70, fontFamily: 'Cairo'),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 120,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.02),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        physics: const ClampingScrollPhysics(),
                        itemCount: (loan['loan_installments'] as List).length,
                        itemBuilder: (context, i) {
                          final inst = loan['loan_installments'][i];
                          final double instAmount = (inst['amount'] as num).toDouble();
                          final String dueDate = inst['due_date'] ?? '';
                          final bool isPaid = inst['is_paid'] ?? false;
                          
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'القسط ${i + 1}: ${dueDate}',
                                  style: const TextStyle(fontSize: 10, color: Colors.white60, fontFamily: 'Cairo'),
                                ),
                                Row(
                                  children: [
                                    Text(
                                      '${instAmount.toStringAsFixed(0)} ${AppConstants.currency}',
                                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'Cairo'),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: isPaid ? AppTheme.successGreen.withOpacity(0.15) : AppTheme.warningOrange.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        isPaid ? 'مدفوع' : 'غير مدفوع',
                                        style: TextStyle(
                                          fontSize: 8,
                                          fontWeight: FontWeight.bold,
                                          color: isPaid ? AppTheme.successGreen : AppTheme.warningOrange,
                                          fontFamily: 'Cairo',
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
                    ),
                  ),
                ],
                if (loan['pledge_url'] != null) ...[
                  const SizedBox(height: 14),
                  InkWell(
                    onTap: () {},
                    child: Row(
                      children: [
                        Icon(Icons.attachment, size: 16, color: color),
                        const SizedBox(width: 4),
                        Text('عرض التعهد الخطي المرفق 📸', style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'approved':
        return AppTheme.successGreen;
      case 'rejected':
        return AppTheme.neonPink;
      default:
        return AppTheme.warningOrange;
    }
  }
}
