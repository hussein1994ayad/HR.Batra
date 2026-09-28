// =========================================================================
// خطة تذكيرات البصمة المحلية (على الجهاز) — دالة نقية قابلة للاختبار
// =========================================================================
// تُستعمل على الآيفون: إشعارات السيرفر (Push) تحتاج حساب Apple Developer ومفتاح
// APNs، أما الإشعار المحلي فيعمل بدونهما. على الأندرويد يرسل السيرفر التذكيرات.
// التذكير قبل بداية الدوام وقبل نهايته بـ 15 دقيقة، في أيام الدوام فقط، وبدون
// أيام الإجازة، ولا يذكّر بما سُجّل اليوم.
// =========================================================================

class PlannedReminder {
  final int id;

  /// الوقت بتوقيت الشركة (ساعة الحائط)
  final DateTime at;
  final bool isCheckIn;
  final String title;
  final String body;

  const PlannedReminder({required this.id, required this.at, required this.isCheckIn, required this.title, required this.body});
}

const int kLocalCheckInReminderBase = 3000;
const int kLocalCheckOutReminderBase = 4000;
const int kLocalReminderDays = 14;

int? _minutes(String? hhmm) {
  if (hhmm == null) return null;
  final p = hhmm.split(':');
  if (p.length < 2) return null;
  final h = int.tryParse(p[0]);
  final m = int.tryParse(p[1]);
  return h == null || m == null ? null : h * 60 + m;
}

String _clock(int minutes) {
  final h = (minutes ~/ 60) % 24;
  final m = minutes % 60;
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12:${m.toString().padLeft(2, '0')} ${h < 12 ? 'ص' : 'م'}';
}

/// التذكيرات للأيام القادمة. [workDays] بترقيم قاعدة البيانات (0 = الأحد).
List<PlannedReminder> planAttendanceReminders({
  required DateTime now,
  required String? checkInTime,
  required String? checkOutTime,
  required List<int> workDays,
  Set<DateTime> leaveDays = const {},
  bool checkedInToday = false,
  bool checkedOutToday = false,
  int minutesBefore = 15,
  int days = kLocalReminderDays,
}) {
  final start = _minutes(checkInTime);
  final end = _minutes(checkOutTime);
  if (start == null || end == null) return const [];
  final today = DateTime(now.year, now.month, now.day);
  final leaves = {for (final d in leaveDays) DateTime(d.year, d.month, d.day)};
  final out = <PlannedReminder>[];

  for (var i = 0; i < days; i++) {
    final day = DateTime(today.year, today.month, today.day + i);
    if (!workDays.contains(day.weekday % 7) || leaves.contains(day)) continue;
    final endDay = end > start ? day : DateTime(day.year, day.month, day.day + 1); // دوام يعبر منتصف الليل

    final inAt = day.add(Duration(minutes: start - minutesBefore));
    if (inAt.isAfter(now) && !(i == 0 && checkedInToday)) {
      out.add(PlannedReminder(
        id: kLocalCheckInReminderBase + i,
        at: inAt,
        isCheckIn: true,
        title: '⏰ الدوام يبدأ خلال $minutesBefore دقيقة',
        body: 'دوامك يبدأ الساعة ${_clock(start)}. لا تنسَ تسجيل بصمة الحضور.',
      ));
    }
    final outAt = endDay.add(Duration(minutes: end - minutesBefore));
    if (outAt.isAfter(now) && !(i == 0 && checkedOutToday)) {
      out.add(PlannedReminder(
        id: kLocalCheckOutReminderBase + i,
        at: outAt,
        isCheckIn: false,
        title: '🔔 الدوام ينتهي خلال $minutesBefore دقيقة',
        body: 'ينتهي دوامك الساعة ${_clock(end)}. لا تنسَ تسجيل بصمة الانصراف قبل المغادرة.',
      ));
    }
  }
  return out;
}
