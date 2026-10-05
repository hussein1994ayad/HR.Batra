// =========================================================================
// إدارة الموظفين (للإدارة): القائمة مع الأجهزة والفروع، التفعيل/التعطيل، فك ربط الجهاز،
// إنشاء حساب موظف (create_employee_secure)، ووثائق الموظف بالتخزين.
// =========================================================================

import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/models/models.dart';
import '../../core/services/image_compression_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/utils/app_log.dart';

class EmployeeAdminRepository {
  EmployeeAdminRepository({SupabaseClient? client}) : _db = client ?? SupabaseService.client;
  final SupabaseClient _db;

  /// الموظفون مع أجهزتهم وفروعهم وأقسامهم، والأفرع (id, name) — بالتوازي.
  Future<({List<ManagedEmployee> employees, List<BranchModel> branches})> fetchEmployeesAndBranches() async {
    final results = await Future.wait<dynamic>([
      _db.from('employees').select('*, employee_devices(id, model), branches(name), departments(name)').order('full_name'),
      _db.from('branches').select('id, name').order('name'),
    ]);
    return (
      employees: List<Map<String, dynamic>>.from(results[0] as Iterable<dynamic>).map(ManagedEmployee.fromMap).toList(),
      branches: List<Map<String, dynamic>>.from(results[1] as Iterable<dynamic>).map(BranchModel.fromMap).toList(),
    );
  }

  /// تفعيل/تعطيل الحساب. عند التعطيل يُحفظ آخر يوم عمل فعلي (termination_date).
  Future<void> setActive(String employeeId, {required bool active, DateTime? lastDay}) async {
    await _db.from('employees').update({
      'is_active': active,
      if (lastDay != null) 'termination_date': '${lastDay.year}-${lastDay.month.toString().padLeft(2, '0')}-${lastDay.day.toString().padLeft(2, '0')}',
    }).eq('id', employeeId);
  }

  /// فك ربط الجهاز: مسح تسجيلات الجهاز القديمة ثم قفل الحساب على أول جهاز جديد.
  Future<void> unbindDevice(String employeeId) async {
    // 1. مسح تسجيلات الجهاز القديمة
    await _db.from('employee_devices').delete().eq('employee_id', employeeId);
    // 2. تحديث قفل الموظف ليكون نشطاً للجهاز القادم
    await _db.from('employees').update({'device_id_lock': 'force_lock_active'}).eq('id', employeeId);
  }

  Future<void> createEmployee(Map<String, dynamic> params) async {
    await _db.rpc<dynamic>('create_employee_secure', params: params);
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

  Future<void> removeDocumentObject(String path) async {
    await _db.storage.from('employee-documents').remove([path]);
  }

  Future<void> updateDocumentUrls(Object employeeId, List<String> urls) async {
    await _db.from('employees').update({'document_urls': urls}).eq('id', employeeId);
  }
}
