// =========================================================================
// التعاميم السارية والمجازون/المتأخرون اليوم — للوحة التعاميم والشاشة الرئيسية.
// التعميم يظهر من تاريخ بدايته حتى تاريخ انتهائه، وللجمهور المستهدف فقط.
// =========================================================================

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/services/supabase_service.dart';

class AnnouncementRepository {
  AnnouncementRepository({SupabaseClient? client}) : _db = client ?? SupabaseService.client;
  final SupabaseClient _db;

  /// التعاميم السارية الآن لهذا الموظف فقط (مدة + جمهور مستهدف)
  Future<dynamic> fetchActive({required int limit}) {
    return _db.rpc<dynamic>('get_active_announcements', params: {'p_limit': limit});
  }

  /// [المجازون الآن، المتأخرون اليوم]. دالة المتأخرين قد لا تكون منشورة على السيرفر: فشلها = قائمة فارغة.
  Future<List<dynamic>> fetchOnLeaveAndLateToday() {
    return Future.wait<dynamic>([
      _db.rpc<dynamic>('get_on_leave_now'),
      _db.rpc<dynamic>('get_late_today').catchError((Object _) => <dynamic>[]),
    ]);
  }

  /// [التعاميم، المجازون الآن، المتأخرون اليوم] بالتوازي (لوحة التعاميم).
  Future<List<dynamic>> fetchBoard({int limit = 50}) async {
    final r = await Future.wait<dynamic>([fetchActive(limit: limit), fetchOnLeaveAndLateToday()]);
    return [r[0], ...(r[1] as List<dynamic>)];
  }
}
