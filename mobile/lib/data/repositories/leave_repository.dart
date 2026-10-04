// =========================================================================
// إجازات الموظف: الرصيد، أنواع الإجازات من السياسة، سجل طلباتي، تقديم وإلغاء طلب.
// إشعار المدراء بالطلب الجديد يُرسل من قاعدة البيانات (trg_notify_admins_new_leave_request).
// =========================================================================

import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/services/file_upload_service.dart';
import '../../core/services/supabase_service.dart';

class LeaveRepository {
  LeaveRepository({SupabaseClient? client}) : _db = client ?? SupabaseService.client;
  final SupabaseClient _db;

  /// السنوية والمرضية لهذه السنة، والزمنيات لهذا الشهر.
  Future<dynamic> fetchBalance() => _db.rpc<dynamic>('get_leave_balance');

  Future<List<Map<String, dynamic>>> fetchMyRequests(String userId) async {
    final data = await _db.from('leave_requests').select().eq('employee_id', userId).order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(data);
  }

  /// صف إعداد leave_policy (قيمته فيها active_types).
  Future<Map<String, dynamic>?> fetchLeavePolicy() {
    return _db.from('system_settings').select('value').eq('key', 'leave_policy').maybeSingle();
  }

  /// رفع صورة المرفق (مع الضغط التلقائي) ويرجع رابطه.
  Future<String> uploadAttachment(String userId, File file) {
    final uniqueId = const Uuid().v4();
    final fileExtension = file.path.split('.').last;
    final remotePath = 'leaves/$userId/$uniqueId.$fileExtension';
    return FileUploadService.uploadFile(file: file, bucketName: 'employee-documents', remotePath: remotePath);
  }

  Future<void> submitRequest(Map<String, dynamic> row) async {
    await _db.from('leave_requests').insert(row);
  }

  /// إلغاء طلب ما زال قيد المراجعة فقط.
  Future<void> cancelPending(String id) async {
    await _db.from('leave_requests').update({'status': 'cancelled'}).eq('id', id).eq('status', 'pending');
  }
}
