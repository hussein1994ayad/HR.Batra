// منطق شاشة البصمة بدون واجهة: التأخير/الخروج المبكر، دمج البصمات المحفوظة بدون إنترنت،
// نوع البصمة التالية، والفحوصات المحلية قبل الإرسال. السيرفر يبقى صاحب القرار النهائي (punch_attendance).

import '../../../core/design/formatters.dart';
import '../../../core/models/work_schedule_model.dart';
import '../../../core/services/precise_location.dart';

const attendanceOutOfRangeMessage = 'أنت خارج نطاق الفرع الجغرافي المسموح به للتبصيم.';

/// دقائق الوقت بعد منتصف الليل من وقت بالجدول (HH:mm أو HH:mm:ss)، أو null إذا غير صالح.
int? scheduleMinutesOf(Object? hhmm) {
  final parts = hhmm?.toString().split(':');
  if (parts == null || parts.length < 2) return null;
  final h = int.tryParse(parts[0]), m = int.tryParse(parts[1]);
  return h == null || m == null ? null : h * 60 + m;
}

/// تنبيه التأخير (بعد السماحية) عند الحضور، أو الخروج المبكر عند الانصراف؛ null = لا تنبيه.
String? punchNote({required bool isCheckIn, required Map<String, dynamic>? schedule, required DateTime now}) {
  final nowMin = now.hour * 60 + now.minute;
  if (isCheckIn) {
    final start = scheduleMinutesOf(schedule?['check_in_time']);
    if (start == null) return null;
    final grace = (schedule?['grace_period_minutes'] as num?)?.toInt() ?? kDefaultGraceMinutes;
    final late = nowMin - start;
    return late > grace ? 'متأخر ${Fmt.minutesLabel(late)} عن بداية الدوام' : null;
  }
  final end = scheduleMinutesOf(schedule?['check_out_time']);
  if (end == null) return null;
  final early = end - nowMin;
  return early > 0 ? 'خروج قبل نهاية الدوام بـ ${Fmt.minutesLabel(early)}' : null;
}

/// سجل اليوم من السيرفر + بصمات اليوم المحفوظة بالجهاز (لهذا المستخدم فقط) فوقه. {} = ماكو شي.
Map<String, dynamic> mergeTodayOfflinePunches({
  required Map<String, dynamic>? serverToday,
  required List<Map<String, dynamic>> offlineQueue,
  required String? userId,
  required String todayStr,
}) {
  final todayOfflinePunches = offlineQueue.where((p) {
    if (p['user_id'] != userId) return false;
    final time = DateTime.tryParse(p['time'] as String? ?? '')?.toLocal();
    return time != null && time.toIso8601String().startsWith(todayStr);
  }).toList();

  final Map<String, dynamic> combinedAttendance = serverToday != null ? Map<String, dynamic>.from(serverToday) : {};

  for (final punch in todayOfflinePunches) {
    if (punch['type'] == 'check_in') {
      combinedAttendance['check_in_time'] = punch['time'];
      combinedAttendance['check_in_lat'] = punch['latitude'];
      combinedAttendance['check_in_lng'] = punch['longitude'];
    } else if (punch['type'] == 'check_out') {
      combinedAttendance['check_out_time'] = punch['time'];
      combinedAttendance['check_out_lat'] = punch['latitude'];
      combinedAttendance['check_out_lng'] = punch['longitude'];
    }
  }
  return combinedAttendance;
}

/// انصراف إذا مسجّل حضور بدون انصراف، وإلا حضور.
String nextPunchType(Map<String, dynamic> today) =>
    today['check_in_time'] != null && today['check_out_time'] == null ? 'check_out' : 'check_in';

/// الفحوصات المحلية قبل الإرسال (رسالة فورية بدل انتظار السيرفر): دقة GPS، النطاق، البصمة المكررة.
String? localPunchError({
  required String punchType,
  required double accuracy,
  required double distanceMeters,
  required double branchRadius,
  required Map<String, dynamic>? today,
}) {
  if (accuracy > PreciseLocation.maxAccuracyFor(branchRadius)) {
    return PreciseLocation.lowAccuracyMessage(accuracy);
  }
  if (distanceMeters > branchRadius) {
    final double outOfRange = distanceMeters - branchRadius;
    return '$attendanceOutOfRangeMessage المتبقي لتصل للفرع: ${outOfRange.toStringAsFixed(1)} متر.';
  }
  if (punchType == 'check_in' && today?['check_in_time'] != null) {
    return 'لقد قمت بتسجيل بصمة الحضور مسبقاً لهذا اليوم!';
  }
  if (punchType == 'check_out' && today?['check_out_time'] != null) {
    return 'لقد قمت بتسجيل بصمة الانصراف مسبقاً لهذا اليوم!';
  }
  return null;
}
