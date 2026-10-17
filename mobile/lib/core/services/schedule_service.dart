// =========================================================================
// نظام HR Pro v6.0 - جدول الدوام الفعلي للموظف
// =========================================================================
// مصدر واحد تستعمله شاشة البصمة، الرئيسية، التذكيرات، وخدمة التتبع.
// الأولوية تُحسب في السيرفر (get_effective_work_schedule):
// جدول الموظف نفسه ← جدول قسمه ← جدول فرعه.
// =========================================================================

import '../models/work_schedule_model.dart';
import '../utils/json_map.dart';
import 'supabase_service.dart';

class ScheduleService {
  /// جدول الدوام الفعلي للمستخدم الحالي، أو null إن لم يوجد جدول.
  static Future<WorkScheduleModel?> fetchEffectiveSchedule() async {
    final dynamic rows =
        await SupabaseService.client.rpc<dynamic>('get_effective_work_schedule');
    final first = rowsOf(rows).firstOrNull;
    return first == null ? null : WorkScheduleModel.fromMap(first);
  }
}
