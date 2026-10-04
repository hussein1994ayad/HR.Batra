// =========================================================================
// التعاميم السارية والمجازون/المتأخرون اليوم — للوحة التعاميم والشاشة الرئيسية — ونشر تعميم للإدارة.
// التعميم يظهر من تاريخ بدايته حتى تاريخ انتهائه، وللجمهور المستهدف فقط.
// =========================================================================

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/models/models.dart';
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

  // ── نشر تعميم (للإدارة) ──

  /// الأفرع والموظفون النشطون لاختيار الجمهور المستهدف (بالتوازي).
  Future<({List<BranchModel> branches, List<EmployeeRef> employees})> fetchTargets() async {
    final futures = await Future.wait([
      _db.from('branches').select('id, name').order('name'),
      _db.from('employees').select('id, full_name').eq('is_active', true).order('full_name'),
    ]);
    return (
      branches: List<Map<String, dynamic>>.from(futures[0]).map(BranchModel.fromMap).toList(),
      employees: List<Map<String, dynamic>>.from(futures[1]).map(EmployeeRef.fromMap).toList(),
    );
  }

  /// ينشر التعميم ويرسل الإشعارات للجمهور المستهدف؛ يرجع ما تُرجعه الدالة (عدد المستلمين).
  Future<dynamic> publish(Map<String, dynamic> params) => _db.rpc<dynamic>('publish_announcement', params: params);
}
