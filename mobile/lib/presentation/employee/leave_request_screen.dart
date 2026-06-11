// =========================================================================
// نظام HR Pro v6.0 - شاشة طلبات وأرصدة الإجازات (Leave Requests & Balances Screen)
// =========================================================================

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../../core/services/supabase_service.dart';
import '../../core/services/file_upload_service.dart';
import '../../core/theme/app_theme.dart';
import '../shared/widgets/glass_container.dart';

class LeaveRequestScreen extends StatefulWidget {
  const LeaveRequestScreen({super.key});

  @override
  State<LeaveRequestScreen> createState() => _LeaveRequestScreenState();
}

class _LeaveRequestScreenState extends State<LeaveRequestScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _formKey = GlobalKey<FormState>();
  
  // حقول الطلب
  String _leaveType = 'annual'; // 'annual', 'sick', 'emergency', 'maternity', 'other'
  bool _isHourly = false;
  bool _isPaid = true; // خيار الدفع
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _startHour = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _endHour = const TimeOfDay(hour: 12, minute: 0);
  final _reasonController = TextEditingController();
  
  File? _attachmentFile;
  bool _isUploading = false;
  // bool _isLoadingBalances = true;
  bool _isLoadingHistory = true;

  // Map<String, dynamic> _balances = {
  //   'employee_id': '',
  //   'annual_entitlement': 21,
  //   'annual_used': 0,
  //   'sick_entitlement': 15,
  //   'sick_used': 0,
  // };
  
  List<Map<String, dynamic>> _leaveHistory = [];
  
  List<Map<String, String>> _leaveTypes = [
    {'id': 'annual', 'name': 'إجازة سنوية اعتيادية'},
    {'id': 'sick', 'name': 'إجازة مرضية بتقرير طبي'},
    {'id': 'emergency', 'name': 'إجازة طارئة مستعجلة'},
    {'id': 'maternity', 'name': 'إجازة أمومة ورعاية'},
    {'id': 'other', 'name': 'مأذونية أو إجازة أخرى'},
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // _loadBalances();
    _loadHistory();
    _loadLeaveTypes();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  // تحميل أرصدة الإجازات للموظف الحالي
  /*
  Future<void> _loadBalances() async {
    final user = SupabaseService.currentUser;
    if (user == null) return;

    try {
      final data = await SupabaseService.client
          .from('leave_balances')
          .select()
          .eq('employee_id', user.id)
          .maybeSingle();

      if (data != null) {
        setState(() {
          _balances = data;
        });
      } else {
        // إذا لم يكن لديه سجل رصيد إجازات، ننشئه تلقائياً
        final defaultBalance = {
          'employee_id': user.id,
          'annual_entitlement': 21,
          'annual_used': 0,
          'sick_entitlement': 15,
          'sick_used': 0,
        };
        await SupabaseService.client.from('leave_balances').insert(defaultBalance);
        setState(() {
          _balances = defaultBalance;
        });
      }
    } catch (e) {
      debugPrint('خطأ في تحميل أرصدة الإجازات: $e');
    } finally {
      setState(() => _isLoadingBalances = false);
    }
  }
  */

  // تحميل سجل الطلبات التاريخي للموظف
  Future<void> _loadHistory() async {
    final user = SupabaseService.currentUser;
    if (user == null) return;

    try {
      final data = await SupabaseService.client
          .from('leave_requests')
          .select()
          .eq('employee_id', user.id)
          .order('created_at', ascending: false);

      setState(() {
        _leaveHistory = List<Map<String, dynamic>>.from(data);
      });
    } catch (e) {
      debugPrint('خطأ في تحميل تاريخ الإجازات: $e');
    } finally {
      setState(() => _isLoadingHistory = false);
    }
  }

  // تحميل أنواع الإجازات الديناميكية من إعدادات النظام
  Future<void> _loadLeaveTypes() async {
    try {
      final data = await SupabaseService.client
          .from('system_settings')
          .select('value')
          .eq('key', 'leave_policy')
          .maybeSingle();

      if (data != null && data['value'] != null) {
        final policy = data['value'] as Map<String, dynamic>;
        if (policy['active_types'] != null) {
          final typesList = policy['active_types'] as List<dynamic>;
          final List<Map<String, String>> mappedTypes = [];
          for (var t in typesList) {
            final typeMap = t as Map<String, dynamic>;
            mappedTypes.add({
              'id': typeMap['id']?.toString() ?? '',
              'name': typeMap['name']?.toString() ?? '',
            });
          }
          if (mappedTypes.isNotEmpty) {
            setState(() {
              _leaveTypes = mappedTypes;
              // إذا كان النوع المحدد حالياً غير موجود في القائمة الجديدة، نقوم بإعادة ضبطه
              if (!_leaveTypes.any((t) => t['id'] == _leaveType)) {
                _leaveType = _leaveTypes.first['id']!;
              }
            });
          }
        }
      }
    } catch (e) {
      debugPrint('خطأ في تحميل أنواع الإجازات من السيرفر: $e');
    }
  }

  // التقاط أو اختيار مرفق (صورة التقرير الطبي أو المبرر)
  Future<void> _pickAttachment() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );

    if (pickedFile != null) {
      setState(() {
        _attachmentFile = File(pickedFile.path);
      });
    }
  }

  // معالجة وتقديم طلب الإجازة
  Future<void> _submitLeaveRequest() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isUploading = true);
    final user = SupabaseService.currentUser;
    if (user == null) return;

    try {
      String? attachmentUrl;

      // 1. رفع المرفق إن وجد مع تفعيل ميزات الضغط التلقائي
      if (_attachmentFile != null) {
        final uniqueId = const Uuid().v4();
        final fileExtension = _attachmentFile!.path.split('.').last;
        final remotePath = 'leaves/${user.id}/$uniqueId.$fileExtension';

        attachmentUrl = await FileUploadService.uploadFile(
          file: _attachmentFile!,
          bucketName: 'documents',
          remotePath: remotePath,
        );
      }

      // 2. إعداد أوقات الإجازة الساعية إن وجدت
      String? startHourStr;
      String? endHourStr;
      if (_isHourly) {
        startHourStr = '${_startHour.hour.toString().padLeft(2, '0')}:${_startHour.minute.toString().padLeft(2, '0')}:00';
        endHourStr = '${_endHour.hour.toString().padLeft(2, '0')}:${_endHour.minute.toString().padLeft(2, '0')}:00';
      }

      // 3. إدراج الطلب بقاعدة البيانات
      await SupabaseService.client.from('leave_requests').insert({
        'employee_id': user.id,
        'leave_type': _leaveType,
        'is_hourly': _isHourly,
        'start_date': _startDate.toUtc().toIso8601String(),
        'end_date': _endDate.toUtc().toIso8601String(),
        'start_hour': startHourStr,
        'end_hour': endHourStr,
        'is_paid': _isPaid,
        'reason': _reasonController.text.trim(),
        'attachment_url': attachmentUrl,
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

      // 4. إشعار بنجاح تقديم الطلب للموظف نفسه
      await SupabaseService.client.from('notifications').insert({
        'employee_id': user.id,
        'title': 'تقديم طلب إجازة جديد 📝',
        'body': 'تم إرسال طلب إجازتك الجديد بنجاح للإدارة وجاري مراجعته والرد قريباً.',
        'type': 'leave',
      });

      // 5. إشعار المدراء والمسؤولين
      try {
        final List<dynamic> admins = await SupabaseService.client
            .from('employees')
            .select('id')
            .or('role.eq.admin,role.eq.manager');
        
        for (var admin in admins) {
          if (admin['id'] != null && admin['id'] != user.id) {
            await SupabaseService.client.from('notifications').insert({
              'employee_id': admin['id'],
              'title': 'طلب إجازة جديد معلق 📝',
              'body': 'قدم الموظف ($empName) طلب إجازة جديد. يرجى المراجعة والاتخاذ من لوحة الإدارة.',
              'type': 'leave',
            });
          }
        }
      } catch (e) {
        debugPrint('خطأ في إرسال إشعارات الإجازة للمسؤولين: $e');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إرسال طلب الإجازة بنجاح، جاري الانتظار للموافقة عليها.', style: TextStyle(fontFamily: 'Cairo')),
            backgroundColor: AppTheme.successGreen,
          ),
        );
        _resetForm();
        _tabController.animateTo(1); // تحويل الموظف لتبويب السجل
        _loadHistory();
      }

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ في تقديم الطلب: $e', style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: AppTheme.dangerRed,
          ),
        );
      }
    } finally {
      setState(() => _isUploading = false);
    }
  }

  void _resetForm() {
    _reasonController.clear();
    setState(() {
      _attachmentFile = null;
      _isHourly = false;
      _isPaid = true;
      _leaveType = 'annual';
      _startDate = DateTime.now();
      _endDate = DateTime.now().add(const Duration(days: 1));
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'بوابة طلب الإجازات',
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
            Tab(text: 'تقديم طلب إجازة', icon: Icon(Icons.note_add_rounded)),
            Tab(text: 'سجل إجازاتي السابقة', icon: Icon(Icons.history_edu_rounded)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // تبويب 1: تقديم الإجازة
          SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // لوحة الأرصدة الحالية الخلابة مخفية بناءً على طلب العميل
                // _buildBalancesRow(isDark),
                // const SizedBox(height: 24),
                
                // نموذج إدخال البيانات
                _buildLeaveForm(isDark),
              ],
            ),
          ),
          
          // تبويب 2: سجل الإجازات السابقة
          _buildLeaveHistoryTab(isDark),
        ],
      ),
    );
  }

  // لوحة أرصدة الإجازات للموظف
  /*
  Widget _buildBalancesRow(bool isDark) {
    if (_isLoadingBalances) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.neonCyan));
    }

    final annualTotal = _balances['annual_entitlement'] ?? 21;
    final annualUsed = _balances['annual_used'] ?? 0;
    final annualLeft = annualTotal - annualUsed;

    final sickTotal = _balances['sick_entitlement'] ?? 15;
    final sickUsed = _balances['sick_used'] ?? 0;
    final sickLeft = sickTotal - sickUsed;

    return Row(
      children: [
        Expanded(
          child: _buildBalanceCard(
            title: 'إجازات سنوية متبقية',
            value: '$annualLeft يوم',
            sub: 'من أصل $annualTotal',
            color: AppTheme.neonCyan,
            isDark: isDark,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildBalanceCard(
            title: 'رصيد مرضي متبقي',
            value: '$sickLeft يوم',
            sub: 'من أصل $sickTotal',
            color: AppTheme.neonPink,
            isDark: isDark,
          ),
        ),
      ],
    );
  }

  Widget _buildBalanceCard({
    required String title,
    required String value,
    required String sub,
    required Color color,
    required bool isDark,
  }) {
    return GlassContainer(
      padding: const EdgeInsets.all(16),
      borderRadius: 20,
      opacity: 0.12,
      borderColor: color.withOpacity(0.3),
      boxShadow: [
        BoxShadow(
          color: color.withOpacity(0.08),
          blurRadius: 16,
          spreadRadius: 1,
        )
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color, fontFamily: 'Cairo')),
          const SizedBox(height: 4),
          Text(sub, style: const TextStyle(fontSize: 10, color: Colors.white54, fontFamily: 'Cairo')),
        ],
      ),
    );
  }
  */

  // نموذج طلب الإجازة الفعلي
  Widget _buildLeaveForm(bool isDark) {
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
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // نوع الإجازة
            const Text('تصنيف ونوع الإجازة المرجوة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white, fontFamily: 'Cairo')),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _leaveType,
              style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'Cairo'),
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.white.withOpacity(0.04),
                prefixIcon: const Icon(Icons.category_rounded, color: AppTheme.neonCyan),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: AppTheme.neonCyan),
                ),
              ),
              dropdownColor: const Color(0xFF1E293B),
              items: _leaveTypes.map((e) {
                return DropdownMenuItem(
                  value: e['id'],
                  child: Text(e['name']!, style: const TextStyle(fontSize: 13, color: Colors.white, fontFamily: 'Cairo')),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() => _leaveType = val);
                }
              },
            ),
            const SizedBox(height: 18),

            // خيار إجازة ساعية أم يومية
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('هل الإجازة ساعية (مأذونية)؟', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white, fontFamily: 'Cairo')),
                    Text('تفعيل لحساب الساعات والدقائق', style: TextStyle(fontSize: 10, color: Colors.white54, fontFamily: 'Cairo')),
                  ],
                ),
                Switch.adaptive(
                  value: _isHourly,
                  activeColor: AppTheme.neonCyan,
                  activeTrackColor: AppTheme.neonCyan.withOpacity(0.3),
                  onChanged: (val) {
                    setState(() => _isHourly = val);
                  },
                ),
              ],
            ),
            const SizedBox(height: 18),

            // خيار إجازة براتب أو بدون راتب
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('نوع الإجازة المالي', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white, fontFamily: 'Cairo')),
                    Text('مستقطعة بدون راتب / مدفوعة الراتب', style: TextStyle(fontSize: 10, color: Colors.white54, fontFamily: 'Cairo')),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _isPaid ? AppTheme.successGreen.withOpacity(0.15) : AppTheme.dangerRed.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _isPaid ? AppTheme.successGreen.withOpacity(0.3) : AppTheme.dangerRed.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Text(
                        _isPaid ? 'مدفوعة الأجر 💰' : 'مستقطعة (بدون راتب) ⚠️',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: _isPaid ? AppTheme.successGreen : AppTheme.dangerRed,
                          fontFamily: 'Cairo'
                        ),
                      ),
                      const SizedBox(width: 8),
                      Switch.adaptive(
                        value: _isPaid,
                        activeColor: AppTheme.successGreen,
                        activeTrackColor: AppTheme.successGreen.withOpacity(0.3),
                        inactiveThumbColor: AppTheme.dangerRed,
                        inactiveTrackColor: AppTheme.dangerRed.withOpacity(0.3),
                        onChanged: (val) {
                          setState(() => _isPaid = val);
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // اختيار التواريخ والأوقات
            if (!_isHourly) ...[
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('تاريخ البداية', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white, fontFamily: 'Cairo')),
                        const SizedBox(height: 6),
                        InkWell(
                          onTap: () => _selectDate(true),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.04),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white.withOpacity(0.1)),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('${_startDate.year}/${_startDate.month}/${_startDate.day}', style: const TextStyle(fontSize: 12, color: Colors.white, fontFamily: 'Cairo')),
                                const Icon(Icons.calendar_month, color: AppTheme.neonCyan, size: 18),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('تاريخ النهاية', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white, fontFamily: 'Cairo')),
                        const SizedBox(height: 6),
                        InkWell(
                          onTap: () => _selectDate(false),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.04),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white.withOpacity(0.1)),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('${_endDate.year}/${_endDate.month}/${_endDate.day}', style: const TextStyle(fontSize: 12, color: Colors.white, fontFamily: 'Cairo')),
                                const Icon(Icons.calendar_month, color: AppTheme.neonCyan, size: 18),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ] else ...[
              // إدخال الساعات والتوقيتات
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('تاريخ المأذونية', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white, fontFamily: 'Cairo')),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () => _selectDate(true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withOpacity(0.1)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('${_startDate.year}/${_startDate.month}/${_startDate.day}', style: const TextStyle(fontSize: 12, color: Colors.white, fontFamily: 'Cairo')),
                          const Icon(Icons.calendar_month, color: AppTheme.neonCyan, size: 18),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('من الساعة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white, fontFamily: 'Cairo')),
                            const SizedBox(height: 6),
                            InkWell(
                              onTap: () => _selectTime(true),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.04),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(_formatTimeOfDay(_startHour), style: const TextStyle(fontSize: 12, color: Colors.white, fontFamily: 'Cairo')),
                                    const Icon(Icons.access_time_filled_rounded, color: AppTheme.neonCyan, size: 18),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('إلى الساعة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white, fontFamily: 'Cairo')),
                            const SizedBox(height: 6),
                            InkWell(
                              onTap: () => _selectTime(false),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.04),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(_formatTimeOfDay(_endHour), style: const TextStyle(fontSize: 12, color: Colors.white, fontFamily: 'Cairo')),
                                    const Icon(Icons.access_time_filled_rounded, color: AppTheme.neonCyan, size: 18),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
            const SizedBox(height: 18),

            // سبب الإجازة
            const Text('مبررات وأسباب طلب الإجازة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white, fontFamily: 'Cairo')),
            const SizedBox(height: 8),
            TextFormField(
              controller: _reasonController,
              maxLines: 3,
              style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'Cairo'),
              decoration: InputDecoration(
                hintText: 'اكتب الأسباب بالتفصيل هنا...',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 12, fontFamily: 'Cairo'),
                filled: true,
                fillColor: Colors.white.withOpacity(0.04),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: AppTheme.neonCyan),
                ),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'يرجى كتابة سبب الإجازة بالتفصيل';
                }
                return null;
              },
            ),
            const SizedBox(height: 18),

            // ملف مرفق (مستند أو تقرير طبي)
            const Text('إرفاق وثيقة مبررة (صورة أو تقرير)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white, fontFamily: 'Cairo')),
            const SizedBox(height: 8),
            InkWell(
              onTap: _pickAttachment,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _attachmentFile != null ? AppTheme.successGreen : Colors.white.withOpacity(0.1),
                    width: _attachmentFile != null ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _attachmentFile != null ? Icons.task_alt_rounded : Icons.cloud_upload_outlined,
                      color: _attachmentFile != null ? AppTheme.successGreen : AppTheme.neonCyan,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _attachmentFile != null 
                          ? 'تم إرفاق الملف بنجاح! 📸' 
                          : 'انقر لاختيار ورفع وثيقة مبررة للطلب',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cairo',
                        color: _attachmentFile != null ? AppTheme.successGreen : AppTheme.neonCyan,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 28),

            // زر تقديم الطلب بنقاط توهج نيون
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  if (!_isUploading)
                    BoxShadow(
                      color: AppTheme.neonCyan.withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    )
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: ElevatedButton(
                  onPressed: _isUploading ? null : _submitLeaveRequest,
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                    shadowColor: Colors.transparent,
                    backgroundColor: Colors.transparent,
                  ),
                  child: Ink(
                    decoration: const BoxDecoration(
                      gradient: AppTheme.cyberGradient,
                    ),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 52.0),
                      alignment: Alignment.center,
                      child: _isUploading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                            )
                          : const Text(
                              'تقديم طلب الإجازة رسمياً',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Cairo',
                                fontSize: 15,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // تبويب سجل الإجازات السابقة
  Widget _buildLeaveHistoryTab(bool isDark) {
    if (_isLoadingHistory) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.neonCyan));
    }

    if (_leaveHistory.isEmpty) {
      return const Center(
        child: Text(
          'لا توجد سجلات إجازات سابقة لك حالياً ✨',
          style: TextStyle(fontSize: 12, color: Colors.white70, fontFamily: 'Cairo'),
        ),
      );
    }

    final statusLabel = {
      'pending': 'قيد المراجعة 🟡',
      'approved': 'مقبولة 🟢',
      'rejected': 'مرفوضة 🔴',
    };

    return RefreshIndicator(
      onRefresh: _loadHistory,
      color: AppTheme.neonCyan,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _leaveHistory.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final req = _leaveHistory[index];
          final type = req['leave_type'] ?? 'other';
          final isHourly = req['is_hourly'] ?? false;
          final status = req['status'] ?? 'pending';
          final cardColor = _getStatusColor(status);

          final String typeLabelStr = _leaveTypes.firstWhere(
            (t) => t['id'] == type,
            orElse: () => {
              'id': type,
              'name': type == 'annual' ? 'سنوية' :
                      type == 'sick' ? 'مرضية' :
                      type == 'emergency' ? 'طارئة' :
                      type == 'maternity' ? 'أمومة' :
                      type == 'other' ? 'أخرى' : type
            },
          )['name']!;

          return GlassContainer(
            padding: const EdgeInsets.all(16),
            borderRadius: 20,
            opacity: 0.08,
            borderColor: cardColor.withOpacity(0.3),
            boxShadow: [
              BoxShadow(
                color: cardColor.withOpacity(0.04),
                blurRadius: 10,
              )
            ],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'إجازة $typeLabelStr (${isHourly ? "ساعية" : "يومية"})',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white, fontFamily: 'Cairo'),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: cardColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: cardColor.withOpacity(0.3)),
                      ),
                      child: Text(
                        statusLabel[status] ?? 'غير معروف',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: cardColor, fontFamily: 'Cairo'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'الفترة: ${_formatDate(req['start_date'])} إلى ${_formatDate(req['end_date'])}',
                  style: const TextStyle(fontSize: 11, color: Colors.white70, fontFamily: 'Cairo'),
                ),
                if (isHourly && req['start_hour'] != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'التوقيت: ${_formatTimeStr(req['start_hour'])} إلى ${_formatTimeStr(req['end_hour'])}',
                    style: const TextStyle(fontSize: 11, color: Colors.white70, fontFamily: 'Cairo'),
                  ),
                ],
                if (req['reason'] != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    'السبب: ${req['reason']}',
                    style: const TextStyle(fontSize: 12, color: Colors.white70, fontFamily: 'Cairo'),
                  ),
                ],
                if (req['attachment_url'] != null) ...[
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () {}, // فتح المرفق
                    child: const Row(
                      children: [
                        Icon(Icons.attachment_rounded, size: 16, color: AppTheme.neonCyan),
                        SizedBox(width: 4),
                        Text('عرض المستند المرفق 📸', style: TextStyle(fontSize: 11, color: AppTheme.neonCyan, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                      ],
                    ),
                  )
                ]
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

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final date = DateTime.parse(dateStr).toLocal();
      return '${date.year}/${date.month}/${date.day}';
    } catch (_) {
      return '';
    }
  }

  Future<void> _selectDate(bool isStart) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : _endDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('ar'),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppTheme.neonCyan,
              onPrimary: Colors.white,
              surface: Color(0xFF1E293B),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
          if (_endDate.isBefore(_startDate)) {
            _endDate = _startDate.add(const Duration(days: 1));
          }
        } else {
          _endDate = picked;
        }
      });
    }
  }

  Future<void> _selectTime(bool isStart) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _startHour : _endHour,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppTheme.neonCyan,
              onPrimary: Colors.white,
              surface: Color(0xFF1E293B),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        if (isStart) {
          _startHour = picked;
        } else {
          _endHour = picked;
        }
      });
    }
  }

  String _formatTimeStr(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return '--:--';
    try {
      final parts = timeStr.split(':');
      if (parts.length < 2) return timeStr;
      int hour = int.parse(parts[0]);
      final int minute = int.parse(parts[1]);
      final String period = hour >= 12 ? 'PM' : 'AM';
      hour = hour % 12;
      if (hour == 0) hour = 12;
      final String minuteStr = minute.toString().padLeft(2, '0');
      return '$hour:$minuteStr $period';
    } catch (e) {
      return timeStr;
    }
  }

  String _formatTimeOfDay(TimeOfDay tod) {
    final int hour = tod.hourOfPeriod == 0 ? 12 : tod.hourOfPeriod;
    final String minute = tod.minute.toString().padLeft(2, '0');
    final String period = tod.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }
}

