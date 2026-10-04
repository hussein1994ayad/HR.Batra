// =========================================================================
// إشعارات الموظف: القائمة الكاملة (الأحدث أولاً) ووضع علامة "مقروء".
// =========================================================================

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/models/models.dart';
import '../../core/services/supabase_service.dart';

class NotificationRepository {
  NotificationRepository({SupabaseClient? client}) : _db = client ?? SupabaseService.client;
  final SupabaseClient _db;

  Future<List<NotificationModel>> fetchMine(String userId) async {
    final List<dynamic> data = await _db.from('notifications').select().eq('employee_id', userId).order('created_at', ascending: false);
    return rowsOf(data).map(NotificationModel.fromMap).toList();
  }

  Future<void> markRead(List<String> ids) async {
    await _db.from('notifications').update({'is_read': true}).inFilter('id', ids);
  }
}
