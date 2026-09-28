// تذكيرات البصمة المحلية (للآيفون): قبل بداية الدوام ونهايته بـ 15 دقيقة.

import 'package:flutter_test/flutter_test.dart';
import 'package:hr_pro/core/logic/reminder_plan.dart';

void main() {
  // الإثنين 2026-09-28 الساعة 07:00، دوام 09:00 → 14:00 من السبت للخميس
  final now = DateTime(2026, 9, 28, 7);
  List<PlannedReminder> plan({bool inToday = false, bool outToday = false, Set<DateTime> leave = const {}, DateTime? at}) =>
      planAttendanceReminders(
        now: at ?? now, checkInTime: '09:00:00', checkOutTime: '14:00:00', workDays: const [0, 1, 2, 3, 4, 6],
        checkedInToday: inToday, checkedOutToday: outToday, leaveDays: leave, days: 7,
      );

  test('reminds 15 minutes before the start and the end of each work day', () {
    final p = plan();
    expect(p.first.at, DateTime(2026, 9, 28, 8, 45));
    expect(p.first.isCheckIn, isTrue);
    expect(p[1].at, DateTime(2026, 9, 28, 13, 45));
    expect(p[1].title, '🔔 الدوام ينتهي خلال 15 دقيقة');
    expect(p[1].body, contains('2:00 م'));
    // 7 أيام منها جمعة واحدة (2 أكتوبر) = 6 أيام دوام × تذكيرين
    expect(p, hasLength(12));
    expect(p.any((r) => r.at.day == 2 && r.at.month == 10), isFalse);
  });

  test('no reminder for what was already punched today, or for past times', () {
    expect(plan(inToday: true).first.at, DateTime(2026, 9, 28, 13, 45));
    expect(plan(inToday: true, outToday: true).first.at, DateTime(2026, 9, 29, 8, 45));
    expect(plan(at: DateTime(2026, 9, 28, 10)).first.at, DateTime(2026, 9, 28, 13, 45));
  });

  test('leave days are skipped and ids are unique per day', () {
    final p = plan(leave: {DateTime(2026, 9, 29)});
    expect(p.any((r) => r.at.day == 29), isFalse);
    expect(p.map((r) => r.id).toSet(), hasLength(p.length));
  });

  test('no schedule times → no reminders', () {
    expect(planAttendanceReminders(now: now, checkInTime: null, checkOutTime: '14:00', workDays: const [1]), isEmpty);
  });
}
