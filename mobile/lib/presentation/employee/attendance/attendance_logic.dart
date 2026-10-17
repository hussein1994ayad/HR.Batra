// منطق شاشة البصمة بدون واجهة: التأخير/الخروج المبكر، دمج البصمات المحفوظة بدون إنترنت،
// نوع البصمة التالية، والفحوصات المحلية قبل الإرسال. السيرفر يبقى صاحب القرار النهائي (punch_attendance).

import '../../../core/design/formatters.dart';
import '../../../core/models/attendance_model.dart';
import '../../../core/models/work_schedule_model.dart';
import '../../../core/services/precise_location.dart';
import '../../../core/utils/company_time.dart';

const attendanceOutOfRangeMessage = 'أنت خارج نطاق الفرع الجغرافي المسموح به للتبصيم.';

/// دقائق الوقت بعد منتصف الليل من وقت بالجدول (HH:mm أو HH:mm:ss)، أو null إذا غير صالح.
int? scheduleMinutesOf(Object? hhmm) {
  final parts = hhmm?.toString().split(':');
  if (parts == null || parts.length < 2) return null;
  final h = int.tryParse(parts[0]), m = int.tryParse(parts[1]);
  return h == null || m == null ? null : h * 60 + m;
}

/// تنبيه التأخير (بعد السماحية) عند الحضور، أو الخروج المبكر عند الانصراف؛ null = لا تنبيه.
String? punchNote({required bool isCheckIn, required WorkScheduleModel? schedule, required DateTime now}) {
  final nowMin = now.hour * 60 + now.minute;
  if (isCheckIn) {
    final start = scheduleMinutesOf(schedule?.checkInTime);
    if (schedule == null || start == null) return null;
    final grace = schedule.gracePeriodMinutes;
    final late = nowMin - start;
    // بعد نهاية الدوام ما نكول «متأخر 12 ساعة»
    final end = scheduleMinutesOf(schedule.checkOutTime);
    if (end != null && end > start && nowMin >= end) {
      return 'بصمة حضور بعد نهاية الدوام (${Fmt.timeOfDay(schedule.checkOutTime)})';
    }
    return late > grace ? 'متأخر ${Fmt.minutesLabel(late)} عن بداية الدوام' : null;
  }
  final end = scheduleMinutesOf(schedule?.checkOutTime);
  if (end == null) return null;
  final early = end - nowMin;
  return early > 0 ? 'خروج قبل نهاية الدوام بـ ${Fmt.minutesLabel(early)}' : null;
}

/// سجل اليوم من السيرفر + بصمات اليوم المحفوظة بالجهاز (لهذا المستخدم فقط) فوقه. null = ماكو شي.
AttendanceModel? mergeTodayOfflinePunches({
  required AttendanceModel? serverToday,
  required List<QueuedPunch> offlineQueue,
  required String? userId,
  required String todayStr,
}) {
  final todayOfflinePunches = offlineQueue.where((p) {
    if (p.userId != userId) return false;
    final time = DateTime.tryParse(p.time ?? '');
    return time != null && companyDateStr(time) == todayStr;
  }).toList();

  var combined = serverToday;
  for (final punch in todayOfflinePunches) {
    if (punch.type != 'check_in' && punch.type != 'check_out') continue;
    combined = (combined ?? AttendanceModel(id: '', employeeId: userId ?? '', workDate: todayStr)).withPunch(
      checkIn: punch.type == 'check_in',
      time: parseServerTime(punch.time),
      lat: punch.latitude,
      lng: punch.longitude,
    );
  }
  return combined;
}

/// انصراف إذا مسجّل حضور بدون انصراف، وإلا حضور.
String nextPunchType(AttendanceModel? today) =>
    today != null && today.hasCheckIn && !today.hasCheckOut ? 'check_out' : 'check_in';

/// الفحوصات المحلية قبل الإرسال (رسالة فورية بدل انتظار السيرفر): دقة GPS، النطاق، البصمة المكررة.
String? localPunchError({
  required String punchType,
  required double accuracy,
  required double distanceMeters,
  required double branchRadius,
  required AttendanceModel? today,
}) {
  if (accuracy > PreciseLocation.maxAccuracyFor(branchRadius)) {
    return PreciseLocation.lowAccuracyMessage(accuracy);
  }
  if (distanceMeters > branchRadius) {
    final double outOfRange = distanceMeters - branchRadius;
    return '$attendanceOutOfRangeMessage المتبقي لتصل للفرع: ${outOfRange.toStringAsFixed(1)} متر.';
  }
  if (punchType == 'check_in' && (today?.hasCheckIn ?? false)) {
    return 'لقد قمت بتسجيل بصمة الحضور مسبقاً لهذا اليوم!';
  }
  if (punchType == 'check_out' && (today?.hasCheckOut ?? false)) {
    return 'لقد قمت بتسجيل بصمة الانصراف مسبقاً لهذا اليوم!';
  }
  return null;
}
