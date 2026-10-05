// =========================================================================
// التخزين للإدارة: سلة المحذوفات (deleted_files) — عرض، استعادة، حذف نهائي —
// وإحصائيات المساحة (get_storage_stats).
// =========================================================================

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/models/models.dart';
import '../../core/services/supabase_service.dart';

class StorageRepository {
  StorageRepository({SupabaseClient? client}) : _db = client ?? SupabaseService.client;
  final SupabaseClient _db;

  /// الملفات بالسلة (غير المستعادة) مع اسم الموظف، الأحدث أولاً.
  Future<List<DeletedFileModel>> fetchTrash() async {
    final List<dynamic> data =
        await _db.from('deleted_files').select('*, employees(full_name)').isFilter('restored_at', null).order('deleted_at', ascending: false);
    return List<Map<String, dynamic>>.from(data).map(DeletedFileModel.fromMap).toList();
  }

  Future<void> restore(String fileId) async {
    await _db.from('deleted_files').update({
      'restored_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', fileId);
  }

  /// حذف الملف من التخزين أولاً ثم من السجل.
  Future<void> deletePermanently({required String bucket, required String filePath, required String fileId}) async {
    await _db.storage.from(bucket).remove([filePath]);
    await _db.from('deleted_files').delete().eq('id', fileId);
  }

  /// أحجام الملفات بالسلة (غير المستعادة).
  Future<List<Map<String, dynamic>>> fetchTrashSizes() {
    return _db.from('deleted_files').select('file_size_bytes').isFilter('restored_at', null);
  }

  /// المساحات الحقيقية لكل bucket من الدالة في Supabase.
  Future<dynamic> fetchStorageStats() => _db.rpc<dynamic>('get_storage_stats');
}
