// =========================================================================
// نظام HR Pro v6.0 - جدول الدوام الفعلي للموظف
// =========================================================================
// مصدر واحد تستعمله شاشة البصمة، الرئيسية، التذكيرات، وخدمة التتبع.
// الأولوية تُحسب في السيرفر (get_effective_work_schedule):
// جدول الموظف نفسه ← جدول قسمه ← جدول فرعه.
// =========================================================================

import 'supabase_service.dart';

class ScheduleService {
  /// جدول الدوام الفعلي للمستخدم الحالي، أو null إن لم يوجد جدول.
  static Future<Map<String, dynamic>?> fetchEffectiveSchedule() async {
    final dynamic rows =
        await SupabaseService.client.rpc<dynamic>('get_effective_work_schedule');
    if (rows is List && rows.isNotEmpty) {
      return Map<String, dynamic>.from(rows.first as Map);
    }
    return null;
  }
}
