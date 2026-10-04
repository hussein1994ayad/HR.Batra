// متى نتتبع؟ فقط إذا الموظف بصم حضور اليوم وما بصم انصراف، وضمن أيام وساعات التتبع
// (tracking_schedules، وإلا جدول الدوام الفعلي). الحالة تنحفظ محلياً (tracking_state.json)
// حتى يكمل القرار بدون إنترنت، وتُحدَّث من السيرفر إذا أقدم من 10 دقائق.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../schedule_service.dart';
import '../supabase_service.dart';

class TrackingSchedule {
  TrackingSchedule._();

  static Future<File> get _trackingStateFile async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/tracking_state.json');
  }

  /// حفظ حالة تتبع الموظف والجدول محلياً للعمل دون اتصال بالإنترنت
  static Future<void> saveState({
    required bool hasCheckedIn,
    required String checkedInDate,
    String? userId,
    Map<String, dynamic>? schedule,
  }) async {
    try {
      final file = await _trackingStateFile;
      final data = {
        'has_checked_in': hasCheckedIn,
        'checked_in_date': checkedInDate,
        'user_id': userId,
        'schedule': schedule,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      await file.writeAsString(jsonEncode(data));
      debugPrint('💾 تم حفظ حالة التتبع محلياً للعمل أوفلاين.');
    } catch (e) {
      debugPrint('❌ فشل في حفظ حالة التتبع محلياً: $e');
    }
  }

  /// قراءة حالة تتبع الموظف المخزنة محلياً
  static Future<Map<String, dynamic>?> readState() async {
    try {
      final file = await _trackingStateFile;
      if (file.existsSync()) {
        final content = await file.readAsString();
        if (content.isNotEmpty) {
          return jsonDecode(content) as Map<String, dynamic>;
        }
      }
    } catch (e) {
      debugPrint('❌ فشل في قراءة حالة التتبع المحلية: $e');
    }
    return null;
  }

  /// التحقق من صلاحية اليوم والوقت وحالة تسجيل الدخول لتحديد ما إذا كان يجب استمرار التتبع.
  /// [isTrackingFallback]: إذا ماكو إنترنت ولا حالة محلية لليوم، نعتمد حالة الجلسة الحالية.
  static Future<bool> shouldTrack(String userId, {required bool isTrackingFallback}) async {
    final todayStr = DateTime.now().toIso8601String().split('T')[0];

    // 1. محاولة قراءة الحالة المخزنة محلياً
    final cached = await readState();
    if (cached != null && cached['checked_in_date'] == todayStr) {
      final updatedAtStr = cached['updated_at'] as String?;
      if (updatedAtStr != null) {
        final updatedAt = DateTime.tryParse(updatedAtStr);
        if (updatedAt != null) {
          final difference = DateTime.now().difference(updatedAt.toLocal());
          if (difference < const Duration(minutes: 10)) {
            return evaluateStateFromCache(cached);
          }
        }
      }
    }

    // 2. إذا مضى وقت أو لم يوجد كاش، نحاول التحديث من السيرفر
    try {
      final attendanceData = await SupabaseService.client
          .from('attendance')
          .select()
          .eq('employee_id', userId)
          .eq('work_date', todayStr)
          .maybeSingle();

      bool hasCheckedIn = false;
      if (attendanceData != null) {
        if (attendanceData['check_in_time'] != null && attendanceData['check_out_time'] == null) {
          hasCheckedIn = true;
        }
      }

      dynamic trackingSchedule = await SupabaseService.client
          .from('tracking_schedules')
          .select()
          .eq('employee_id', userId)
          .maybeSingle();

      // Fallback: لو ما فيه tracking_schedule، استخدم work_schedule (الأوقات الرسمية للدوام)
      if (trackingSchedule == null) {
        final workSchedule = await ScheduleService.fetchEffectiveSchedule();
        if (workSchedule != null) {
          trackingSchedule = {
            'start_time': workSchedule['check_in_time'],
            'end_time': workSchedule['check_out_time'],
            'tracking_days': workSchedule['work_days'],
          };
        }
      }

      await saveState(
        hasCheckedIn: hasCheckedIn,
        checkedInDate: todayStr,
        userId: userId,
        schedule: trackingSchedule as Map<String, dynamic>?,
      );

      if (!hasCheckedIn) return false;
      if (trackingSchedule == null) return true;

      return evaluateSchedule(trackingSchedule);
    } catch (e) {
      debugPrint('⚠️ وضع الأوفلاين نشط، الاعتماد على الحالة المحلية: $e');
      if (cached != null && cached['checked_in_date'] == todayStr) {
        return evaluateStateFromCache(cached);
      }
      // إذا كان الموظف مسجلاً في الجلسة الحالية نعتبره نشطاً
      return isTrackingFallback;
    }
  }

  static bool evaluateStateFromCache(Map<String, dynamic> cached) {
    final bool hasCheckedIn = (cached['has_checked_in'] ?? false) as bool;
    if (!hasCheckedIn) return false;

    final schedule = cached['schedule'] as Map<String, dynamic>?;
    if (schedule == null) return true;

    return evaluateSchedule(schedule);
  }

  /// أيام التتبع (0 = الأحد كما بقاعدة البيانات) والساعات؛ الافتراضي 08:00–18:00.
  static bool evaluateSchedule(Map<String, dynamic> schedule) {
    final now = DateTime.now();
    final int pgDay = now.weekday % 7; // Sunday = 0, Monday = 1, etc.
    final List<dynamic> trackingDays = (schedule['tracking_days'] ?? <dynamic>[]) as List<dynamic>;

    if (trackingDays.isNotEmpty && !trackingDays.contains(pgDay)) {
      return false;
    }

    final String startTimeStr = (schedule['start_time'] ?? '08:00:00') as String;
    final String endTimeStr = (schedule['end_time'] ?? '18:00:00') as String;

    return isCurrentTimeBetween(startTimeStr, endTimeStr);
  }

  /// التحقق من وقوع الوقت الحالي بين وقت البدء والنهاية (نهاية قبل البداية = دوام يعبر منتصف الليل)
  static bool isCurrentTimeBetween(String startStr, String endStr, {DateTime? now}) {
    try {
      final current = now ?? DateTime.now();
      final startParts = startStr.split(':');
      final endParts = endStr.split(':');

      if (startParts.length < 2 || endParts.length < 2) return false;

      final int startHour = int.tryParse(startParts[0]) ?? 8;
      final int startMinute = int.tryParse(startParts[1]) ?? 0;
      final int endHour = int.tryParse(endParts[0]) ?? 18;
      final int endMinute = int.tryParse(endParts[1]) ?? 0;

      final start = DateTime(current.year, current.month, current.day, startHour, startMinute);
      var end = DateTime(current.year, current.month, current.day, endHour, endMinute);

      if (end.isBefore(start)) {
        end = end.add(const Duration(days: 1));
      }

      return current.isAfter(start) && current.isBefore(end);
    } catch (_) {
      return false;
    }
  }
}
