// =========================================================================
// الشاشة الرئيسية للموظف: الملف الشخصي، دوام اليوم، التعاميم، الإشعارات غير المقروءة،
// العطل الرسمية، المجازون والمتأخرون اليوم — والاشتراكات الفورية (Realtime).
// =========================================================================

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/services/supabase_service.dart';

class HomeRepository {
  HomeRepository({SupabaseClient? client}) : _db = client ?? SupabaseService.client;
  final SupabaseClient _db;

  /// الاسم والقسم والفرع والصورة والدور من دليل الموظفين.
  Future<Map<String, dynamic>?> fetchProfile(String userId) {
    return _db.from('v_employee_directory').select().eq('id', userId).maybeSingle();
  }

  Future<Map<String, dynamic>?> fetchTodayAttendance(String userId, String todayStr) {
    return _db.from('attendance').select().eq('employee_id', userId).eq('work_date', todayStr).maybeSingle();
  }

  /// التعاميم السارية الآن لهذا الموظف فقط (مدة + جمهور مستهدف)
  Future<dynamic> fetchActiveAnnouncements({int limit = 3}) {
    return _db.rpc<dynamic>('get_active_announcements', params: {'p_limit': limit});
  }

  Future<List<dynamic>> fetchUnreadNotificationIds(String userId) async {
    return await _db.from('notifications').select('id').eq('employee_id', userId).eq('is_read', false);
  }

  Future<bool> isOfficialHoliday(String todayStr) async {
    final row = await _db.from('official_holidays').select('holiday_date').eq('holiday_date', todayStr).maybeSingle();
    return row != null;
  }

  /// [المجازون الآن، المتأخرون اليوم]. دالة المتأخرين قد لا تكون منشورة على السيرفر: فشلها = قائمة فارغة.
  Future<List<dynamic>> fetchOnLeaveAndLateToday() {
    return Future.wait<dynamic>([
      _db.rpc<dynamic>('get_on_leave_now'),
      _db.rpc<dynamic>('get_late_today').catchError((Object _) => <dynamic>[]),
    ]);
  }

  /// إشعار جديد للموظف (لزيادة العداد وإظهار إشعار داخل التطبيق).
  RealtimeChannel subscribeToNewNotifications(String userId, void Function(PostgresChangePayload payload) onInsert) {
    return _db
        .channel('public:notifications:user:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'employee_id', value: userId),
          callback: onInsert,
        )
        .subscribe((status, [error]) {
          debugPrint('=== notifications channel: $status ===');
          if (error != null) debugPrint('=== channel error: $error ===');
        });
  }

  /// أي تغيير بسجلات حضور الموظف (البصمة من جهاز آخر أو من الإدارة تحدّث الكارد فوراً).
  RealtimeChannel subscribeToAttendance(String userId, void Function(PostgresChangePayload payload) onChange) {
    return _db
        .channel('home:attendance:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'attendance',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'employee_id', value: userId),
          callback: onChange,
        )
        .subscribe((status, [error]) {
          debugPrint('=== attendance channel: $status ===');
        });
  }

  Future<String> removeChannel(RealtimeChannel channel) => _db.removeChannel(channel);
}
