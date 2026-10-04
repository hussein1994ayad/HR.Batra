// =========================================================================
// ملف الموظف الشخصي (شاشة الإعدادات): البيانات، الصورة الشخصية، المستمسكات، وطلب حذف الحساب.
// =========================================================================

import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/services/file_upload_service.dart';
import '../../core/services/supabase_service.dart';

class ProfileRepository {
  ProfileRepository({SupabaseClient? client}) : _db = client ?? SupabaseService.client;
  final SupabaseClient _db;

  /// معلومات الموظف من الـ view الآمن.
  Future<Map<String, dynamic>?> fetchProfile(String userId) {
    return _db.from('v_employee_directory').select().eq('id', userId).maybeSingle();
  }

  /// يرفع الصورة الشخصية الجديدة (مع الضغط) إلى avatars/[remotePath] ويرجع رابطها.
  Future<String> uploadAvatar(File file, String remotePath) {
    return FileUploadService.uploadFile(file: file, bucketName: 'avatars', remotePath: remotePath);
  }

  Future<void> updateAvatarUrl(String userId, String url) async {
    await _db.from('employees').update({'avatar_url': url}).eq('id', userId);
  }

  /// حذف الصورة القديمة من التخزين (بعد نجاح تحديث الرابط).
  Future<void> removeAvatarObject(String path) async {
    await _db.storage.from('avatars').remove([path]);
  }

  /// يرفع مستمسكاً إلى employee-documents/<id>/<وقت>.<امتداد> ويرجع رابطه.
  Future<String> uploadDocument(String userId, File file) {
    final ext = file.path.split('.').last;
    return FileUploadService.uploadFile(
      file: file,
      bucketName: 'employee-documents',
      remotePath: '$userId/${DateTime.now().millisecondsSinceEpoch}.$ext',
    );
  }

  Future<void> updateDocumentUrls(String userId, List<String> urls) async {
    await _db.from('employees').update({'document_urls': urls}).eq('id', userId);
  }

  /// مجموع المتبقي من السلف المعتمدة (طلب حذف الحساب ممنوع إذا أكبر من صفر).
  Future<double> fetchApprovedLoansRemaining(String userId) async {
    final loans = await _db.from('loans').select('remaining_amount').eq('employee_id', userId).eq('status', 'approved');
    double totalRemaining = 0.0;
    for (final loan in loans) {
      totalRemaining += (loan['remaining_amount'] as num?)?.toDouble() ?? 0.0;
    }
    return totalRemaining;
  }

  /// الدالة ترسل الطلب لكل الأدمنية (الموظف لا يرى حساباتهم بسبب RLS).
  Future<void> requestAccountDeletion() async {
    await _db.rpc<dynamic>('request_account_deletion');
  }
}
