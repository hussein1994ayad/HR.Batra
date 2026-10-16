// =========================================================================
// إدارة الموظفين (للإدارة): القائمة مع الأجهزة والفروع، التفعيل/التعطيل، فك ربط الجهاز،
// إنشاء حساب موظف (create_employee_secure)، ووثائق الموظف بالتخزين.
// =========================================================================

import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/logic/employee_history.dart';
import '../../core/logic/end_of_service.dart';
import '../../core/models/models.dart';
import '../../core/services/image_compression_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/utils/app_log.dart';
import '../../core/utils/arabic_format.dart';
import 'employee_pay.dart';
import 'write_guard.dart';

class EmployeeAdminRepository {
  EmployeeAdminRepository({SupabaseClient? client}) : _db = client ?? SupabaseService.client;
  final SupabaseClient _db;

  /// الموظفون مع أجهزتهم وفروعهم وأقسامهم، والأفرع (id, name) — بالتوازي.
  Future<({List<ManagedEmployee> employees, List<BranchModel> branches})> fetchEmployeesAndBranches() async {
    final results = await Future.wait<dynamic>([
      _db.from('employees').select('$kEmployeeColumns, employee_devices(id, model), branches(name), departments(name)').order('full_name'),
      _db.from('branches').select('id, name').order('name'),
      // الراتب من السيرفر: للأدمن، والمدير ما يوصله شي
      fetchEmployeePay(_db),
    ]);
    final pay = results[2] as Map<String, JsonRow>;
    return (
      employees: List<Map<String, dynamic>>.from(results[0] as Iterable<dynamic>)
          .map((row) => ManagedEmployee.fromMap(withPay(row, pay)))
          .toList(),
      branches: List<Map<String, dynamic>>.from(results[1] as Iterable<dynamic>).map(BranchModel.fromMap).toList(),
    );
  }

  /// تفعيل/تعطيل الحساب. عند التعطيل يُحفظ آخر يوم عمل فعلي (termination_date).
  Future<void> setActive(String employeeId, {required bool active, DateTime? lastDay}) async {
    ensureChanged(await _db.from('employees').update({
      'is_active': active,
      if (lastDay != null) 'termination_date': '${lastDay.year}-${lastDay.month.toString().padLeft(2, '0')}-${lastDay.day.toString().padLeft(2, '0')}',
    }).eq('id', employeeId).select('id'));
  }

  /// تفعيل حساب موظف ترك ورجع بتاريخ رجوعه (تدقيق 14/10 PAY-009): أيام الانقطاع ما تطلع غياب وتنقص من راتب ذاك المسير.
  /// سيرفر قبل تحديث 20261021000000: تفعيل عادي (الرجوع = اليوم).
  Future<ReactivateResult> reactivate(String employeeId, DateTime returnDate) async {
    try {
      final res = await _db.rpc<dynamic>('reactivate_employee', params: {'p_employee_id': employeeId, 'p_return_date': isoDate(returnDate)});
      return res is Map ? ReactivateResult.fromMap(Map<String, dynamic>.from(res)) : const ReactivateResult();
    } on PostgrestException catch (e) {
      if (e.code != 'PGRST202') rethrow;
      await setActive(employeeId, active: true);
      return const ReactivateResult();
    }
  }

  /// سجل الموظف بالتواريخ (باشر، انتقل، ترك، رجع). null = سيرفر قبل تحديث 20261021000000.
  Future<List<EmployeeHistoryEvent>?> employeeHistory(String employeeId) async {
    try {
      final res = await _db.rpc<dynamic>('get_employee_history', params: {'p_employee_id': employeeId});
      return [
        for (final e in (res as List?) ?? const [])
          if (e is Map) EmployeeHistoryEvent.fromMap(Map<String, dynamic>.from(e)),
      ];
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST202') return null;
      rethrow;
    }
  }

  /// معاينة «إنهاء الخدمات»: شلون ينحسب آخر راتب لو آخر يوم = [lastDay] (السيرفر يحسب ويتراجع، ما يتغير شي).
  /// null = سيرفر قبل تحديث 20261020000000.
  Future<EndOfServicePreview?> endOfServicePreview(String employeeId, DateTime lastDay) async {
    try {
      final res = await _db.rpc<dynamic>('end_of_service_preview', params: {'p_employee_id': employeeId, 'p_last_day': isoDate(lastDay)});
      return res is Map ? EndOfServicePreview.fromMap(Map<String, dynamic>.from(res)) : null;
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST202') return null;
      rethrow;
    }
  }

  /// آخر يوم بصم بيه الموظف (اقتراح «آخر يوم عمل» عند التعطيل).
  Future<DateTime?> lastPunchDate(String employeeId) async {
    final rows = await _db
        .from('attendance')
        .select('work_date')
        .eq('employee_id', employeeId)
        .not('check_in_time', 'is', null)
        .order('work_date', ascending: false)
        .limit(1);
    final value = rows.isEmpty ? null : rows.first['work_date'];
    return value is String ? DateTime.tryParse(value) : null;
  }

  /// فك ربط الجهاز: مسح تسجيلات الجهاز القديمة ثم قفل الحساب على أول جهاز جديد.
  Future<void> unbindDevice(String employeeId) async {
    // 1. مسح تسجيلات الجهاز القديمة
    await _db.from('employee_devices').delete().eq('employee_id', employeeId);
    // 2. تحديث قفل الموظف ليكون نشطاً للجهاز القادم
    ensureChanged(await _db.from('employees').update({'device_id_lock': 'force_lock_active'}).eq('id', employeeId).select('id'));
  }

  /// إنشاء موظف بحسابه. بدون كود = السيرفر يعطي الرقم التالي (EMP-003، EMP-004... — تدقيق 14/10 BUG-010).
  Future<void> createEmployee(Map<String, dynamic> params) async {
    try {
      await _db.rpc<dynamic>('create_employee_secure', params: params);
    } on PostgrestException catch (e) {
      // سيرفر قبل تحديث 20261023000000: الكود إجباري
      if (e.code != '23502' || params['p_employee_code'] != null) rethrow;
      await _db.rpc<dynamic>('create_employee_secure',
          params: {...params, 'p_employee_code': 'EMP-${DateTime.now().millisecondsSinceEpoch % 10000}'});
    }
  }

  /// يضغط الصور ويرفعها إلى bucket 'employee-documents' ويرجع روابطها (الملف اللي يفشل يُتخطى).
  Future<List<String>> uploadDocuments(List<File> files, String employeeId) async {
    final uploadedUrls = <String>[];
    for (final file in files) {
      try {
        // ضغط الصورة، أو الملف كما هو إذا لم يكن صورة (مثل PDF)
        final processedFile = await ImageCompressionService.compressImage(file);
        final fileName = '$employeeId/${DateTime.now().millisecondsSinceEpoch}_${file.path.split(Platform.pathSeparator).last}';
        await _db.storage.from('employee-documents').upload(fileName, processedFile);
        uploadedUrls.add(_db.storage.from('employee-documents').getPublicUrl(fileName));
      } catch (e) {
        appLog('Error compressing/uploading file: $e');
      }
    }
    return uploadedUrls;
  }

  /// حذف مباشر من التخزين: بس لملفات انرفعت هسه وما انحفظت (الحفظ فشل).
  /// المستمسك المشال من القائمة تحطه القاعدة بالسلة بعد ما ينحفظ (تدقيق 14/10 BUG-009).
  Future<void> removeDocumentObject(String path) async {
    await _db.storage.from('employee-documents').remove([path]);
  }

  Future<void> updateDocumentUrls(Object employeeId, List<String> urls) async {
    ensureChanged(await _db.from('employees').update({'document_urls': urls}).eq('id', employeeId).select('id'));
  }
}
