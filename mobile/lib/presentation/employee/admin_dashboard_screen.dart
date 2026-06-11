// =========================================================================
// نظام HR Pro v6.0 - لوحة تحكم وإدارة المدراء والأدمن (Admin/Manager Dashboard Screen)
// =========================================================================

import 'package:flutter/material.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import 'package:go_router/go_router.dart';
import '../../core/routes/app_router.dart';
import '../shared/widgets/glass_background.dart';
import '../shared/widgets/glass_container.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;

  // إحصائيات سريعة
  int _presentCount = 0;
  int _absentCount = 0;
  int _pendingLeavesCount = 0;
  int _pendingLoansCount = 0;
  int _pendingDevicesCount = 0;
  int _violationsCount = 0;

  // القوائم التفصيلية
  List<Map<String, dynamic>> _pendingLeaves = [];
  List<Map<String, dynamic>> _pendingLoans = [];
  List<Map<String, dynamic>> _pendingDevices = [];
  List<Map<String, dynamic>> _securityLogs = [];
  List<Map<String, dynamic>> _pendingDecisions = [];
  
  String? _selectedBranchId = 'all';
  String? _selectedEmployeeId = 'all';
  DateTime? _selectedDate;
  List<Map<String, dynamic>> _employeesList = [];
  List<Map<String, dynamic>> _branches = [];
  int _pendingDecisionsCount = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _loadDashboardData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // تحميل البيانات الشاملة من قاعدة بيانات Supabase
  Future<void> _loadDashboardData() async {
    setState(() => _isLoading = true);

    // تحميل الفروع والموظفين أولاً وبشكل متوازي إن وجدوا فارغين لتجهيز قائمة الموظفين المفردين
    try {
      final List<Future<dynamic>> initFutures = [];
      int idxBranches = -1;
      int idxEmployees = -1;

      if (_branches.isEmpty) {
        idxBranches = initFutures.length;
        initFutures.add(SupabaseService.client.from('branches').select('id, name').order('name'));
      }
      if (_employeesList.isEmpty) {
        idxEmployees = initFutures.length;
        initFutures.add(SupabaseService.client
            .from('employees')
            .select('id, full_name, branch_id, is_active')
            .order('full_name'));
      }

      if (initFutures.isNotEmpty) {
        final results = await Future.wait(initFutures);
        if (idxBranches != -1) {
          _branches = List<Map<String, dynamic>>.from(results[idxBranches]);
        }
        if (idxEmployees != -1) {
          _employeesList = List<Map<String, dynamic>>.from(results[idxEmployees]);
        }
      }
    } catch (e) {
      debugPrint('خطأ في تحميل الفروع والموظفين: $e');
    }

    // تحديد الموظفين المفلترين النشطين
    final filteredEmployees = _employeesList.where((emp) {
      if (emp['is_active'] == false) return false;
      if (_selectedEmployeeId != null && _selectedEmployeeId != 'all') {
        return emp['id'] == _selectedEmployeeId;
      }
      if (_selectedBranchId != null && _selectedBranchId != 'all') {
        return emp['branch_id'] == _selectedBranchId;
      }
      return true;
    }).toList();

    List<String>? filterEmployeeIds = filteredEmployees.map((e) => e['id'] as String).toList();
    if (filterEmployeeIds.isEmpty) {
      filterEmployeeIds = ['no-employees-found'];
    }

    // تواريخ التصفية
    final String targetDateStr = _selectedDate != null 
        ? _selectedDate!.toIso8601String().split('T')[0] 
        : DateTime.now().toIso8601String().split('T')[0];
        
    final startOfDay = _selectedDate != null 
        ? DateTime(_selectedDate!.year, _selectedDate!.month, _selectedDate!.day, 0, 0, 0).toUtc().toIso8601String()
        : null;
    final endOfDay = _selectedDate != null 
        ? DateTime(_selectedDate!.year, _selectedDate!.month, _selectedDate!.day, 23, 59, 59).toUtc().toIso8601String()
        : null;

    // متغيرات مؤقتة لتجميع النتائج
    int present = 0;
    int absent = 0;
    List<Map<String, dynamic>> attendanceTodayList = [];
    List<Map<String, dynamic>> leavesData = [];
    List<Map<String, dynamic>> loansData = [];
    List<Map<String, dynamic>> devicesData = [];
    List<Map<String, dynamic>> mockAttempts = [];
    List<Map<String, dynamic>> violationsList = [];
    List<Map<String, dynamic>> decisionsData = [];

    // إعداد قائمة الـ Futures للاستعلام المتوازي
    final List<Future<dynamic>> futures = [];
    int idxAttendanceToday = -1;
    int idxLeaves = -1;
    int idxLoans = -1;
    int idxDevices = -1;
    int idxMock = -1;
    int idxViolations = -1;
    int idxDecisions = -1;

    // هل هناك تصفية مخصصة بناء على الموظف أو الفرع؟
    bool applyEmployeeFilter = (_selectedEmployeeId != null && _selectedEmployeeId != 'all') || 
                               (_selectedBranchId != null && _selectedBranchId != 'all');

    // 1. حضور اليوم
    idxAttendanceToday = futures.length;
    var attendanceQuery = SupabaseService.client
          .from('attendance')
          .select('status, employee_id')
          .eq('work_date', targetDateStr);
    if (applyEmployeeFilter && filterEmployeeIds != null) {
      attendanceQuery = attendanceQuery.inFilter('employee_id', filterEmployeeIds);
    }
    futures.add(
      attendanceQuery.catchError((e) {
            debugPrint('خطأ في تحميل حضور اليوم: $e');
            return [];
          })
    );

    // 2. طلبات الإجازات المعلقة
    var leavesQuery = SupabaseService.client
        .from('leave_requests')
        .select('*, employees!leave_requests_employee_id_fkey!inner(full_name)')
        .eq('status', 'pending');
    if (applyEmployeeFilter && filterEmployeeIds != null) {
      leavesQuery = leavesQuery.inFilter('employee_id', filterEmployeeIds);
    }
    if (startOfDay != null && endOfDay != null) {
      leavesQuery = leavesQuery.lte('start_date', endOfDay).gte('end_date', startOfDay);
    }
    idxLeaves = futures.length;
    futures.add(
      leavesQuery.catchError((e) {
        debugPrint('خطأ في تحميل الإجازات: $e');
        return [];
      })
    );

    // 3. طلبات السلف المعلقة
    var loansQuery = SupabaseService.client
        .from('loans')
        .select('*, employees!loans_employee_id_fkey!inner(full_name)')
        .eq('status', 'pending');
    if (applyEmployeeFilter && filterEmployeeIds != null) {
      loansQuery = loansQuery.inFilter('employee_id', filterEmployeeIds);
    }
    if (startOfDay != null && endOfDay != null) {
      loansQuery = loansQuery.gte('created_at', startOfDay).lte('created_at', endOfDay);
    }
    idxLoans = futures.length;
    futures.add(
      loansQuery.catchError((e) {
        debugPrint('خطأ في تحميل السلف: $e');
        return [];
      })
    );

    // 4. الأجهزة غير المعتمدة
    var devicesQuery = SupabaseService.client
        .from('employee_devices')
        .select('*, employees!inner(full_name)')
        .eq('is_approved', false);
    if (applyEmployeeFilter && filterEmployeeIds != null) {
      devicesQuery = devicesQuery.inFilter('employee_id', filterEmployeeIds);
    }
    if (startOfDay != null && endOfDay != null) {
      devicesQuery = devicesQuery.gte('created_at', startOfDay).lte('created_at', endOfDay);
    }
    idxDevices = futures.length;
    futures.add(
      devicesQuery.catchError((e) {
        debugPrint('خطأ في تحميل الأجهزة: $e');
        return [];
      })
    );

    // 5. محاولات التزييف الجغرافي
    var mockQuery = SupabaseService.client
        .from('mock_gps_attempts')
        .select('*, employees!inner(full_name)');
    if (applyEmployeeFilter && filterEmployeeIds != null) {
      mockQuery = mockQuery.inFilter('employee_id', filterEmployeeIds);
    }
    if (startOfDay != null && endOfDay != null) {
      mockQuery = mockQuery.gte('timestamp', startOfDay).lte('timestamp', endOfDay);
    }
    idxMock = futures.length;
    futures.add(
      mockQuery.order('timestamp', ascending: false).limit(15).catchError((e) {
        debugPrint('خطأ في تحميل محاولات التزييف: $e');
        return [];
      })
    );

    // 6. مخالفات الجيوفينس
    var violationsQuery = SupabaseService.client
        .from('geofence_violations')
        .select('*, employees!inner(full_name)');
    if (applyEmployeeFilter && filterEmployeeIds != null) {
      violationsQuery = violationsQuery.inFilter('employee_id', filterEmployeeIds);
    }
    if (startOfDay != null && endOfDay != null) {
      violationsQuery = violationsQuery.gte('timestamp', startOfDay).lte('timestamp', endOfDay);
    }
    idxViolations = futures.length;
    futures.add(
      violationsQuery.order('timestamp', ascending: false).limit(15).catchError((e) {
        debugPrint('خطأ في تحميل مخالفات الجيوفينس: $e');
        return [];
      })
    );

    // 7. قرارات الغياب والتأخير المعلقة (فقط في حال تم تحديد التاريخ)
    if (_selectedDate != null) {
      var decisionsQuery = SupabaseService.client
          .from('attendance')
          .select('*, employees!inner(full_name, branch_id)')
          .inFilter('status', ['absent', 'late', 'half_day'])
          .isFilter('deduction_applied', null)
          .eq('work_date', targetDateStr);
      if (applyEmployeeFilter && filterEmployeeIds != null) {
        decisionsQuery = decisionsQuery.inFilter('employee_id', filterEmployeeIds);
      }
      idxDecisions = futures.length;
      futures.add(
        decisionsQuery.catchError((e) {
          debugPrint('خطأ في تحميل قرارات الغياب والتأخير: $e');
          return [];
        })
      );
    }

    // الانتظار الفعلي المتوازي لجميع الاستعلامات المتبقية
    final results = await Future.wait(futures);

    // استخلاص البيانات
    attendanceTodayList = List<Map<String, dynamic>>.from(results[idxAttendanceToday]);
    leavesData = List<Map<String, dynamic>>.from(results[idxLeaves]);
    loansData = List<Map<String, dynamic>>.from(results[idxLoans]);
    devicesData = List<Map<String, dynamic>>.from(results[idxDevices]);
    mockAttempts = List<Map<String, dynamic>>.from(results[idxMock]);
    violationsList = List<Map<String, dynamic>>.from(results[idxViolations]);
    if (idxDecisions != -1) {
      decisionsData = List<Map<String, dynamic>>.from(results[idxDecisions]);
    }

    // 1. حساب حضور وغياب اليوم
    final Map<String, Map<String, dynamic>> attendanceMap = {};
    for (var row in attendanceTodayList) {
      attendanceMap[row['employee_id']] = Map<String, dynamic>.from(row);
    }

    for (var emp in filteredEmployees) {
      final record = attendanceMap[emp['id']];
      if (record != null) {
        final status = record['status'];
        if (status == 'present' || status == 'late' || status == 'half_day') {
          present++;
        } else if (status == 'absent') {
          absent++;
        }
      } else {
        absent++;
      }
    }

    // 2. إذا تم تحديد تاريخ، أضف الغيابات الافتراضية
    if (_selectedDate != null) {
      for (var emp in filteredEmployees) {
        final hasRecord = attendanceMap.containsKey(emp['id']);
        if (!hasRecord) {
          decisionsData.add({
            'id': 'virtual_${emp['id']}_$targetDateStr',
            'employee_id': emp['id'],
            'branch_id': emp['branch_id'],
            'status': 'absent',
            'work_date': targetDateStr,
            'deduction_applied': null,
            'is_virtual': true,
            'employees': {'full_name': emp['full_name']},
          });
        }
      }
    }

    // دمج سجلات الأمان
    final List<Map<String, dynamic>> secLogs = [];
    for (var att in mockAttempts) {
      secLogs.add({
        'type': 'mock_gps',
        'employee_name': att['employees']?['full_name'] ?? 'موظف غير معروف',
        'timestamp': att['timestamp'],
        'details': 'محاولة تزييف موقع باستخدام: ${att['app_used'] ?? 'تطبيق غير معروف'}',
        'lat_lng': '${att['latitude']}, ${att['longitude']}',
      });
    }
    for (var vio in violationsList) {
      final vType = vio['violation_type'] == 'entry' ? 'دخول غير مصرح به' : 'خروج غير مصرح به';
      secLogs.add({
        'type': 'geofence',
        'employee_name': vio['employees']?['full_name'] ?? 'موظف غير معروف',
        'timestamp': vio['timestamp'],
        'details': '$vType',
        'lat_lng': '',
      });
    }
    if (secLogs.isNotEmpty) {
      secLogs.sort((a, b) => DateTime.parse(b['timestamp']).compareTo(DateTime.parse(a['timestamp'])));
    }

    setState(() {
      _presentCount = present;
      _absentCount = absent;
      _pendingLeaves = leavesData;
      _pendingLeavesCount = leavesData.length;
      _pendingLoans = loansData;
      _pendingLoansCount = loansData.length;
      _pendingDevices = devicesData;
      _pendingDevicesCount = devicesData.length;
      _securityLogs = secLogs;
      _violationsCount = secLogs.length;
      _pendingDecisions = decisionsData;
      _pendingDecisionsCount = decisionsData.length;
      _isLoading = false;
    });
  }

  // معالجة قرار غياب أو تأخير
  Future<void> _processDecision(String attendanceId, String employeeId, String status, bool applyDeduction, String reason, double amount) async {
    final adminUser = SupabaseService.currentUser;
    if (adminUser == null) return;

    try {
      setState(() => _isLoading = true);

      if (applyDeduction) {
        // تحديث السجل الفعلي الموجود مسبقاً
        await SupabaseService.client.from('attendance').update({
          'deduction_applied': applyDeduction,
          'deduction_reason': reason,
          'deduction_status': applyDeduction ? 'applied' : 'ignored',
        }).eq('id', attendanceId);

        // إدراج الخصم في جدول المكافآت/الخصومات
        await SupabaseService.client.from('bonuses_deductions').insert({
          'employee_id': employeeId,
          'type': 'deduction',
          'amount': amount,
          'reason': reason,
          'issue_date': DateTime.now().toIso8601String().split('T')[0],
        });
      } else {
        await SupabaseService.client.from('attendance').update({
          'deduction_applied': applyDeduction,
          'deduction_reason': reason,
          'deduction_status': 'ignored',
        }).eq('id', attendanceId);
      }

      if (attendanceId.startsWith('virtual_')) {
        // استخراج تفاصيل الغياب الافتراضي
        final emp = _employeesList.firstWhere((e) => e['id'] == employeeId, orElse: () => {});
        final branchId = emp['branch_id'];
        final dateStr = attendanceId.split('_').last;

        // إدراج سجل حضور جديد كغائب مطبق عليه القرار
        await SupabaseService.client.from('attendance').insert({
          'employee_id': employeeId,
          'branch_id': branchId,
          'status': 'absent',
          'work_date': dateStr,
          'deduction_applied': applyDeduction,
          'deduction_reason': reason,
          'deduction_status': applyDeduction ? 'applied' : 'ignored',
        });
      }

      // 2. إشعار الموظف بالقرار
      final actionTitle = applyDeduction ? 'إشعار بخصم غياب/تأخير ⚠️' : 'إعفاء من الخصم 🎉';
      final actionBody = applyDeduction 
          ? 'تم تطبيق خصم بسبب $status. السبب: $reason'
          : 'تم إعفاؤك من خصم $status. السبب: $reason';

      await SupabaseService.client.from('notifications').insert({
        'employee_id': employeeId,
        'title': actionTitle,
        'body': actionBody,
        'type': 'attendance',
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(applyDeduction ? 'تم تطبيق الخصم ⚠️' : 'تم الإعفاء من الخصم ✅', style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: applyDeduction ? AppTheme.warningOrange : AppTheme.successGreen,
          ),
        );
      }
      _loadDashboardData();

    } catch (e) {
      debugPrint('خطأ في معالجة القرار: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // معالجة واعتماد الإجازات (قبول أو رفض)
  Future<void> _processLeave(String requestId, String employeeId, bool approve) async {
    final statusText = approve ? 'approved' : 'rejected';
    final adminUser = SupabaseService.currentUser;
    if (adminUser == null) return;

    try {
      setState(() => _isLoading = true);

      // 1. تحديث الطلب
      await SupabaseService.client.from('leave_requests').update({
        'status': statusText,
        'approved_by': adminUser.id,
        'approved_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', requestId);

      // 2. إرسال إشعار فوري للموظف
      final String actionTitle = approve ? 'الموافقة على طلب إجازتك 🎉' : 'رفض طلب إجازتك ❌';
      final String actionBody = approve 
          ? 'تهانينا! تمت الموافقة على طلب إجازتك المقدم مسبقاً.' 
          : 'نأسف لإعلامك بأنه تم رفض طلب إجازتك من قبل الإدارة.';

      await SupabaseService.client.from('notifications').insert({
        'employee_id': employeeId,
        'title': actionTitle,
        'body': actionBody,
        'type': 'leave',
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(approve ? 'تم قبول طلب الإجازة بنجاح ✅' : 'تم رفض طلب الإجازة ❌', style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: approve ? AppTheme.successGreen : AppTheme.dangerRed,
          ),
        );
      }
      _loadDashboardData();

    } catch (e) {
      debugPrint('خطأ في معالجة طلب الإجازة: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // معالجة واعتماد طلبات السلف (قبول أو رفض)
  Future<void> _processLoan(String loanId, String employeeId, double amount, int months, bool approve) async {
    final statusText = approve ? 'approved' : 'rejected';
    final adminUser = SupabaseService.currentUser;
    if (adminUser == null) return;

    try {
      setState(() => _isLoading = true);

      // 1. تحديث الطلب
      await SupabaseService.client.from('loans').update({
        'status': statusText,
        'approved_by': adminUser.id,
        'approved_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', loanId);

      // 2. إشعار الموظف
      final String actionTitle = approve ? 'الموافقة على طلب السلفة 💸' : 'رفض طلب السلفة ❌';
      final String actionBody = approve 
          ? 'تمت الموافقة على سلفة بقيمة ${amount.toStringAsFixed(0)} د.ع وتوزيعها على $months أقساط شهرية.'
          : 'نأسف، تم رفض طلب السلفة المقدم من قبلك.';

      await SupabaseService.client.from('notifications').insert({
        'employee_id': employeeId,
        'title': actionTitle,
        'body': actionBody,
        'type': 'loan',
      });

      // 3. إذا تمت الموافقة، توليد الأقساط الشهرية تلقائياً
      if (approve) {
        final double installmentAmt = (amount / months).roundToDouble();
        final List<Map<String, dynamic>> installments = [];
        final now = DateTime.now();

        for (int i = 1; i <= months; i++) {
          final due = DateTime(now.year, now.month + i, 1);
          installments.add({
            'loan_id': loanId,
            'due_date': due.toIso8601String().split('T')[0],
            'amount': installmentAmt,
            'is_paid': false,
          });
        }

        await SupabaseService.client.from('loan_installments').insert(installments);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(approve ? 'تم اعتماد السلفة وتوليد الأقساط ✅' : 'تم رفض طلب السلفة ❌', style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: approve ? AppTheme.successGreen : AppTheme.dangerRed,
          ),
        );
      }
      _loadDashboardData();

    } catch (e) {
      debugPrint('خطأ في معالجة طلب السلفة: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // اعتماد وجدولة أجهزة الموظفين المقفلة
  Future<void> _approveDevice(String deviceId, String employeeId, bool approve) async {
    final adminUser = SupabaseService.currentUser;
    if (adminUser == null) return;

    try {
      setState(() => _isLoading = true);

      if (approve) {
        // تحديث حالة الموافقة
        await SupabaseService.client.from('employee_devices').update({
          'is_approved': true,
          'approved_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', deviceId);

        // جلب معرّف الجهاز لتثبيت القفل على الموظف
        final devData = await SupabaseService.client
            .from('employee_devices')
            .select('device_id')
            .eq('id', deviceId)
            .maybeSingle();

        if (devData != null && devData['device_id'] != null) {
          await SupabaseService.client
              .from('employees')
              .update({'device_id_lock': devData['device_id']})
              .eq('id', employeeId);
        }

        // إشعار
        await SupabaseService.client.from('notifications').insert({
          'employee_id': employeeId,
          'title': 'اعتماد جهاز الدخول الجديد 📱',
          'body': 'تمت موافقة الإدارة على اعتماد هاتف تسجيل دخولك الجديد بنجاح.',
          'type': 'device',
        });
      } else {
        // حذف معرّف الجهاز المرفوض
        await SupabaseService.client.from('employee_devices').delete().eq('id', deviceId);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(approve ? 'تم اعتماد الجهاز بنجاح ✅' : 'تم رفض وإزالة الهاتف المذكور ❌', style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: approve ? AppTheme.successGreen : AppTheme.dangerRed,
          ),
        );
      }
      _loadDashboardData();

    } catch (e) {
      debugPrint('خطأ في اعتماد الجهاز: $e');
    } finally {
      setState(() => _isLoading = false);
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
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text(
            'لوحة إدارة الموارد البشرية 👑',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Colors.white,
              shadows: [
                Shadow(
                  color: AppTheme.neonCyan,
                  blurRadius: 10,
                ),
              ],
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.bar_chart_rounded, color: AppTheme.neonCyan),
              tooltip: 'تقارير الحضور',
              onPressed: () => context.push(AppRoutes.adminAttendanceReport),
            ),
            IconButton(
              icon: const Icon(Icons.people_alt_rounded, color: AppTheme.successGreen),
              tooltip: 'إدارة الموظفين',
              onPressed: () => context.push(AppRoutes.adminEmployeeManagement),
            ),
            IconButton(
              icon: const Icon(Icons.schedule_rounded, color: AppTheme.warningOrange),
              tooltip: 'أوقات عمل الأفرع',
              onPressed: () => context.push(AppRoutes.adminBranchSchedule),
            ),
            IconButton(
              icon: const Icon(Icons.delete_sweep_rounded, color: AppTheme.neonPink),
              tooltip: 'سلة المحذوفات',
              onPressed: () => context.push(AppRoutes.adminTrash),
            ),
            IconButton(
              icon: const Icon(Icons.cloud_queue_rounded, color: AppTheme.neonCyan),
              tooltip: 'إحصائيات التخزين',
              onPressed: () => context.push(AppRoutes.adminStorage),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(150),
            child: Column(
              children: [
                // Row 1: Branch and Employee Dropdowns
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                  child: Row(
                    children: [
                      // Branch Dropdown
                      Expanded(
                        child: Container(
                          height: 38,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppTheme.neonCyan.withOpacity(0.2)),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _selectedBranchId,
                              hint: const Text('جميع الفروع', style: TextStyle(fontFamily: 'Cairo', color: Colors.white, fontSize: 11)),
                              isExpanded: true,
                              dropdownColor: const Color(0xFF1A1F3A),
                              icon: const Icon(Icons.arrow_drop_down_rounded, color: AppTheme.neonCyan),
                              style: const TextStyle(fontFamily: 'Cairo', color: Colors.white, fontSize: 11),
                              items: [
                                const DropdownMenuItem(value: 'all', child: Text('جميع الفروع')),
                                ..._branches.map((b) => DropdownMenuItem<String>(value: b['id'], child: Text(b['name']))),
                              ],
                              onChanged: (val) {
                                setState(() {
                                  _selectedBranchId = val;
                                  // Reset selected employee if they are not in the new branch
                                  if (_selectedEmployeeId != null && _selectedEmployeeId != 'all') {
                                    final emp = _employeesList.firstWhere((e) => e['id'] == _selectedEmployeeId, orElse: () => {});
                                    if (emp.isNotEmpty && val != 'all' && emp['branch_id'] != val) {
                                      _selectedEmployeeId = 'all';
                                    }
                                  }
                                });
                                _loadDashboardData();
                              },
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Employee Dropdown
                      Expanded(
                        child: Container(
                          height: 38,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppTheme.successGreen.withOpacity(0.2)),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _selectedEmployeeId,
                              hint: const Text('جميع الموظفين', style: TextStyle(fontFamily: 'Cairo', color: Colors.white, fontSize: 11)),
                              isExpanded: true,
                              dropdownColor: const Color(0xFF1A1F3A),
                              icon: const Icon(Icons.arrow_drop_down_rounded, color: AppTheme.successGreen),
                              style: const TextStyle(fontFamily: 'Cairo', color: Colors.white, fontSize: 11),
                              items: [
                                const DropdownMenuItem(value: 'all', child: Text('جميع الموظفين')),
                                ..._employeesList.where((emp) {
                                  if (_selectedBranchId == null || _selectedBranchId == 'all') return true;
                                  return emp['branch_id'] == _selectedBranchId;
                                }).map((e) => DropdownMenuItem<String>(value: e['id'], child: Text(e['full_name']))),
                              ],
                              onChanged: (val) {
                                setState(() {
                                  _selectedEmployeeId = val;
                                });
                                _loadDashboardData();
                              },
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Row 2: Date Picker & Reset Buttons
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                  child: Row(
                    children: [
                      // Date Picker Button
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _selectedDate ?? DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: DateTime.now().add(const Duration(days: 365)),
                              locale: const Locale('ar'),
                              builder: (context, child) {
                                return Theme(
                                  data: Theme.of(context).copyWith(
                                    colorScheme: const ColorScheme.dark(
                                      primary: AppTheme.neonCyan,
                                      onPrimary: Colors.black,
                                      surface: Color(0xFF1A1F3A),
                                      onSurface: Colors.white,
                                    ),
                                  ),
                                  child: child!,
                                );
                              },
                            );
                            if (picked != null) {
                              setState(() {
                                _selectedDate = picked;
                              });
                              _loadDashboardData();
                            }
                          },
                          child: Container(
                            height: 34,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.06),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppTheme.warningOrange.withOpacity(0.2)),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _selectedDate == null 
                                      ? 'تصفية حسب التاريخ' 
                                      : '${_selectedDate!.year}/${_selectedDate!.month}/${_selectedDate!.day}',
                                  style: const TextStyle(fontFamily: 'Cairo', color: Colors.white, fontSize: 11),
                                ),
                                Icon(
                                  _selectedDate == null ? Icons.calendar_today_rounded : Icons.edit_calendar_rounded,
                                  color: AppTheme.warningOrange,
                                  size: 14,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      
                      // Reset Button (Visible only when filters are active)
                      if ((_selectedBranchId != null && _selectedBranchId != 'all') || 
                          (_selectedEmployeeId != null && _selectedEmployeeId != 'all') || 
                          _selectedDate != null) ...[
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: () {
                            setState(() {
                              _selectedBranchId = 'all';
                              _selectedEmployeeId = 'all';
                              _selectedDate = null;
                            });
                            _loadDashboardData();
                          },
                          child: Container(
                            height: 34,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: AppTheme.dangerRed.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppTheme.dangerRed.withOpacity(0.3)),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.filter_alt_off_rounded, color: Colors.white, size: 14),
                                SizedBox(width: 4),
                                Text(
                                  'إعادة ضبط',
                                  style: TextStyle(fontFamily: 'Cairo', color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                
                TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  labelStyle: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 11),
                  unselectedLabelStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 11),
                  indicatorColor: AppTheme.neonCyan,
                  labelColor: AppTheme.neonCyan,
                  unselectedLabelColor: Colors.white70,
                  indicatorSize: TabBarIndicatorSize.tab,
                  tabs: [
                    Tab(text: 'القرارات ($_pendingDecisionsCount)'),
                    Tab(text: 'الإجازات ($_pendingLeavesCount)'),
                    Tab(text: 'السلف ($_pendingLoansCount)'),
                    Tab(text: 'الأجهزة ($_pendingDevicesCount)'),
                    Tab(text: 'الأمان ($_violationsCount)'),
                  ],
                ),
              ],
            ),
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => context.push(AppRoutes.adminAnnouncement),
          backgroundColor: AppTheme.cyberPurple,
          icon: const Icon(Icons.campaign_rounded, color: Colors.white),
          label: const Text('تعميم جديد', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: Colors.white)),
        ),
        body: _isLoading
            ? const Center(
                child: CircularProgressIndicator(
                  color: AppTheme.neonCyan,
                ),
              )
            : RefreshIndicator(
                onRefresh: _loadDashboardData,
                color: AppTheme.neonCyan,
                backgroundColor: AppTheme.darkSurface,
                child: Column(
                  children: [
                    // 1. الإحصائيات الأفقية السريعة
                    _buildHeaderStats(isDark),

                    // 2. صفحات التبويبات الفعالة
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildDecisionsTab(isDark),
                          _buildLeavesTab(isDark),
                          _buildLoansTab(isDark),
                          _buildDevicesTab(isDark),
                          _buildSecurityTab(isDark),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  // قسم الإحصائيات الأفقية بنمط زجاجي متطور
  Widget _buildHeaderStats(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.08))),
      ),
      child: Row(
        children: [
          Expanded(child: _buildStatCard('حاضر اليوم', '$_presentCount', AppTheme.successGreen, Icons.done_all_rounded)),
          const SizedBox(width: 8),
          Expanded(child: _buildStatCard('غائب اليوم', '$_absentCount', AppTheme.dangerRed, Icons.close_rounded)),
          const SizedBox(width: 8),
          Expanded(child: _buildStatCard('مخالفات أمنية', '$_violationsCount', AppTheme.warningOrange, Icons.security_rounded)),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, Color color, IconData icon) {
    return GlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      borderRadius: 14,
      opacity: 0.12,
      borderColor: color.withOpacity(0.35),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title, 
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 8.5, color: Colors.white60, fontFamily: 'Cairo'),
                ),
                const SizedBox(height: 2),
                Text(
                  value, 
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // تبويب قرارات الغياب والتأخير
  Widget _buildDecisionsTab(bool isDark) {
    if (_selectedDate == null) {
      return _buildEmptyState(
        'يرجى تحديد تاريخ أولاً لعرض القرارات المعلقة 📅',
        icon: Icons.calendar_today_rounded,
        iconColor: AppTheme.warningOrange,
      );
    }
    if (_pendingDecisions.isEmpty) {
      return _buildEmptyState('لا توجد قرارات غياب أو تأخير معلقة لليوم المختار 👏');
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: _pendingDecisions.length,
      itemBuilder: (context, index) {
        final item = _pendingDecisions[index];
        final empName = item['employees']?['full_name'] ?? 'موظف غير معروف';
        String status = item['status'] ?? '';
        if (status == 'absent') status = 'غياب';
        if (status == 'late') status = 'تأخير';
        if (status == 'half_day') status = 'نصف يوم';
        final date = item['work_date'];

        int missedMinutes = 0;
        if (status == 'تأخير' && item['check_in_time'] != null) {
          try {
            final checkInTime = DateTime.parse(item['check_in_time']).toLocal();
            final expectedCheckIn = DateTime(checkInTime.year, checkInTime.month, checkInTime.day, 8, 30);
            if (checkInTime.isAfter(expectedCheckIn)) {
              missedMinutes = checkInTime.difference(expectedCheckIn).inMinutes;
            }
          } catch (_) {}
        } else if (status == 'نصف يوم' && item['check_out_time'] != null) {
          try {
            final checkOutTime = DateTime.parse(item['check_out_time']).toLocal();
            final expectedCheckOut = DateTime(checkOutTime.year, checkOutTime.month, checkOutTime.day, 16, 30);
            if (checkOutTime.isBefore(expectedCheckOut)) {
              missedMinutes = expectedCheckOut.difference(checkOutTime).inMinutes;
            }
          } catch (_) {}
        }

        double suggestedAmount = missedMinutes * 50.0;
        if (status == 'غياب') suggestedAmount = 25000.0;

        TextEditingController reasonCtrl = TextEditingController(text: missedMinutes > 0 ? 'دقائق مفقودة: $missedMinutes دقيقة' : '');
        TextEditingController amountCtrl = TextEditingController(text: suggestedAmount > 0 ? suggestedAmount.toStringAsFixed(0) : '');

        return GlassContainer(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(16),
          borderRadius: 20,
          opacity: 0.08,
          borderColor: status == 'غياب' ? AppTheme.dangerRed.withOpacity(0.3) : AppTheme.warningOrange.withOpacity(0.3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    empName, 
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white, fontFamily: 'Cairo'),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: status == 'غياب' ? AppTheme.dangerRed.withOpacity(0.15) : AppTheme.warningOrange.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: status == 'غياب' ? AppTheme.dangerRed.withOpacity(0.3) : AppTheme.warningOrange.withOpacity(0.3)),
                    ),
                    child: Text(
                      status,
                      style: TextStyle(color: status == 'غياب' ? AppTheme.dangerRed : AppTheme.warningOrange, fontSize: 9, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                    ),
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Divider(color: Colors.white10, height: 1),
              ),
              _buildInfoRow(Icons.calendar_month_rounded, 'تاريخ الدوام', date),
              if (item['status'] == 'late' && item['check_in_time'] != null) ...[
                const SizedBox(height: 10),
                _buildInfoRow(Icons.watch_later_rounded, 'توقيت البصمة (دخول)', _formatTime12h(item['check_in_time'])),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: amountCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(fontFamily: 'Cairo', color: Colors.white, fontSize: 12),
                      decoration: InputDecoration(
                        hintText: 'مبلغ الخصم (د.ع)',
                        hintStyle: const TextStyle(color: Colors.white38),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.05),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: reasonCtrl,
                      style: const TextStyle(fontFamily: 'Cairo', color: Colors.white, fontSize: 12),
                      decoration: InputDecoration(
                        hintText: 'سبب الخصم...',
                        hintStyle: const TextStyle(color: Colors.white38),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.05),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        final amt = double.tryParse(amountCtrl.text) ?? 0;
                        _processDecision(item['id'], item['employee_id'], status, true, reasonCtrl.text.isEmpty ? 'تم الخصم بناءً على تعليمات الإدارة' : reasonCtrl.text, amt);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.dangerRed,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('تطبيق خصم', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 11)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _processDecision(item['id'], item['employee_id'], status, false, reasonCtrl.text.isEmpty ? 'تم الإعفاء بناءً على تعليمات الإدارة' : reasonCtrl.text, 0),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.successGreen,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('إعفاء / مسامحة', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 11)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // تبويب طلبات الإجازات
  Widget _buildLeavesTab(bool isDark) {
    if (_pendingLeaves.isEmpty) {
      return _buildEmptyState('لا توجد طلبات إجازة معلقة حالياً 🎉');
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: _pendingLeaves.length,
      itemBuilder: (context, index) {
        final item = _pendingLeaves[index];
        final empName = item['employees']?['full_name'] ?? 'موظف غير معروف';
        final leaveType = item['leave_type'];
        final isHourly = item['is_hourly'] ?? false;
        final start = DateTime.parse(item['start_date']).toLocal();
        final end = DateTime.parse(item['end_date']).toLocal();
        final reason = item['reason'] ?? 'بدون سبب مذكور';

        String dateRangeText = isHourly 
            ? '${start.year}/${start.month}/${start.day} (${item['start_hour']} - ${item['end_hour']})'
            : 'من ${start.year}/${start.month}/${start.day} إلى ${end.year}/${end.month}/${end.day}';

        return GlassContainer(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(16),
          borderRadius: 20,
          opacity: 0.08,
          borderColor: AppTheme.neonCyan.withOpacity(0.25),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    empName, 
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white, fontFamily: 'Cairo'),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.neonCyan.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.neonCyan.withOpacity(0.3)),
                    ),
                    child: Text(
                      _getLeaveTypeText(leaveType),
                      style: const TextStyle(color: AppTheme.neonCyan, fontSize: 9, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                    ),
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Divider(color: Colors.white10, height: 1),
              ),
              _buildInfoRow(Icons.calendar_month_rounded, 'الفترة الزمنية', dateRangeText),
              const SizedBox(height: 10),
              _buildInfoRow(Icons.comment_rounded, 'سبب الإجازة', reason),
              if (item['attachment_url'] != null && (item['attachment_url'] as String).isNotEmpty) ...[
                const SizedBox(height: 10),
                _buildInfoRow(Icons.attachment_rounded, 'المرفق المرفوع', 'يوجد مستند رسمي مرفق 📄', isLink: true, url: item['attachment_url']),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _processLeave(item['id'], item['employee_id'], true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.successGreen,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('موافقة', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _processLeave(item['id'], item['employee_id'], false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.dangerRed, 
                        side: const BorderSide(color: AppTheme.dangerRed),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('رفض', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // تبويب طلبات السلف
  Widget _buildLoansTab(bool isDark) {
    if (_pendingLoans.isEmpty) {
      return _buildEmptyState('لا توجد طلبات سلف معلقة حالياً 💸');
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: _pendingLoans.length,
      itemBuilder: (context, index) {
        final item = _pendingLoans[index];
        final empName = item['employees']?['full_name'] ?? 'موظف غير معروف';
        final double amount = (item['amount'] as num).toDouble();
        final int months = item['installment_count'] as int;
        final double monthly = (item['installment_amount'] as num).toDouble();

        return GlassContainer(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(16),
          borderRadius: 20,
          opacity: 0.08,
          borderColor: AppTheme.cyberPurple.withOpacity(0.25),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    empName, 
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white, fontFamily: 'Cairo'),
                  ),
                  Text(
                    '${amount.toStringAsFixed(0)} د.ع',
                    style: const TextStyle(color: AppTheme.neonCyan, fontWeight: FontWeight.w900, fontSize: 14, fontFamily: 'Cairo'),
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Divider(color: Colors.white10, height: 1),
              ),
              _buildInfoRow(Icons.schedule_rounded, 'عدد الأقساط', '$months أشهر متتالية'),
              const SizedBox(height: 10),
              _buildInfoRow(Icons.price_change_rounded, 'القسط الشهري', '${monthly.toStringAsFixed(0)} د.ع / الشهر'),
              if (item['pledge_url'] != null && (item['pledge_url'] as String).isNotEmpty) ...[
                const SizedBox(height: 10),
                _buildInfoRow(Icons.draw_rounded, 'تعهد السلفة الموقّع', 'رابط التعهد الإلزامي المرفق 📝', isLink: true, url: item['pledge_url']),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _processLoan(item['id'], item['employee_id'], amount, months, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.successGreen,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('موافقة', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _processLoan(item['id'], item['employee_id'], amount, months, false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.dangerRed, 
                        side: const BorderSide(color: AppTheme.dangerRed),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('رفض', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // تبويب الأجهزة المعتمدة
  Widget _buildDevicesTab(bool isDark) {
    if (_pendingDevices.isEmpty) {
      return _buildEmptyState('لا توجد طلبات اعتماد أجهزة معلقة حالياً 📱');
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: _pendingDevices.length,
      itemBuilder: (context, index) {
        final item = _pendingDevices[index];
        final empName = item['employees']?['full_name'] ?? 'موظف غير معروف';
        final model = item['model'] ?? 'هاتف غير معروف';
        final os = item['os_version'] ?? 'نظام غير معروف';
        final uuid = item['device_id'] ?? 'UUID غير متوفر';

        return GlassContainer(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(16),
          borderRadius: 20,
          opacity: 0.08,
          borderColor: AppTheme.neonPink.withOpacity(0.25),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                empName, 
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white, fontFamily: 'Cairo'),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Divider(color: Colors.white10, height: 1),
              ),
              _buildInfoRow(Icons.phone_android_rounded, 'طراز الهاتف الجديد', model),
              const SizedBox(height: 10),
              _buildInfoRow(Icons.adb_rounded, 'إصدار نظام التشغيل', os),
              const SizedBox(height: 10),
              _buildInfoRow(Icons.fingerprint_rounded, 'معرف الهاتف الفريد', uuid, isCode: true),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _approveDevice(item['id'], item['employee_id'], true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.successGreen,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('اعتماد الجهاز', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _approveDevice(item['id'], item['employee_id'], false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.dangerRed, 
                        side: const BorderSide(color: AppTheme.dangerRed),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('رفض الطلب', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // تبويب الأمان والخروقات
  Widget _buildSecurityTab(bool isDark) {
    if (_securityLogs.isEmpty) {
      return _buildEmptyState('سجل الأمان خالٍ من الخروقات اليوم ✨');
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: _securityLogs.length,
      itemBuilder: (context, index) {
        final log = _securityLogs[index];
        final name = log['employee_name'];
        final date = DateTime.parse(log['timestamp']).toLocal();
        final details = log['details'];
        final latLng = log['lat_lng'] as String;

        return GlassContainer(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(16),
          borderRadius: 20,
          opacity: 0.12,
          borderColor: AppTheme.dangerRed.withOpacity(0.35),
          boxShadow: [
            BoxShadow(
              color: AppTheme.dangerRed.withOpacity(0.12),
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
                    name, 
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white, fontFamily: 'Cairo'),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.dangerRed.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.dangerRed.withOpacity(0.3)),
                    ),
                    child: const Text(
                      'خطر أمني ⚠️',
                      style: TextStyle(color: AppTheme.dangerRed, fontSize: 9, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                    ),
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Divider(color: Colors.white10, height: 1),
              ),
              _buildInfoRow(Icons.warning_amber_rounded, 'تفاصيل الخرق المكتشف', details),
              const SizedBox(height: 10),
              _buildInfoRow(Icons.schedule_rounded, 'توقيت المحاولة', '${_formatTime12h(log['timestamp'])} بتاريخ ${date.year}/${date.month}/${date.day}'),
              if (latLng.isNotEmpty) ...[
                const SizedBox(height: 10),
                _buildInfoRow(Icons.location_on_rounded, 'الإحداثيات المرصودة', latLng, isCode: true),
              ],
            ],
          ),
        );
      },
    );
  }

  // شاشات فرعية مساعدة
  Widget _buildEmptyState(String text, {IconData icon = Icons.verified_rounded, Color iconColor = AppTheme.successGreen}) {
    return Center(
      child: GlassContainer(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        margin: const EdgeInsets.all(24),
        borderRadius: 24,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: iconColor, size: 54),
            const SizedBox(height: 16),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Colors.white70, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime12h(String? isoString) {
    if (isoString == null || isoString.isEmpty) return '--:--';
    try {
      final dateTime = DateTime.parse(isoString).toLocal();
      int hour = dateTime.hour;
      final int minute = dateTime.minute;
      final String period = hour >= 12 ? 'PM' : 'AM';
      
      hour = hour % 12;
      if (hour == 0) hour = 12;
      
      final String minuteStr = minute.toString().padLeft(2, '0');
      return '$hour:$minuteStr $period';
    } catch (e) {
      return '--:--';
    }
  }

  Widget _buildInfoRow(IconData icon, String label, String val, {bool isCode = false, bool isLink = false, String? url}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Colors.white54),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 9.5, color: Colors.white38, fontFamily: 'Cairo')),
              const SizedBox(height: 2),
              if (isLink && url != null)
                GestureDetector(
                  onTap: () {
                    // فتح الرابط المباشر للملف المضغوط
                  },
                  child: Text(
                    val,
                    style: const TextStyle(
                      fontSize: 11, 
                      color: AppTheme.neonCyan, 
                      fontWeight: FontWeight.bold, 
                      decoration: TextDecoration.underline, 
                      fontFamily: 'Cairo',
                    ),
                  ),
                )
              else if (isCode)
                // تأمين التوافقية ومنع خروج النصوص خارج مساحة الشاشة بالالتفاف أو القطع
                SelectableText(
                  val,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'monospace',
                    color: AppTheme.neonCyan,
                  ),
                )
              else
                Text(
                  val,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo',
                    color: Colors.white,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  String _getLeaveTypeText(String type) {
    switch (type) {
      case 'annual':
        return 'إجازة سنوية';
      case 'sick':
        return 'إجازة مرضية';
      case 'emergency':
        return 'إجازة طارئة';
      case 'maternity':
        return 'إجازة أمومة';
      default:
        return 'إجازة أخرى';
    }
  }
}
