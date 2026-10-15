// تدقيق 14/10/2026 — المرحلة 2: وقت البصمة بدون إنترنت من آخر وقت سيرفر + عدّاد الموبايل (ما يتأثر بتغيير الساعة).

import 'package:flutter_test/flutter_test.dart';
import 'package:hr_pro/core/logic/attendance_report.dart';
import 'package:hr_pro/core/logic/offline_punch_time.dart';

void main() {
  final server = DateTime.utc(2026, 10, 15, 5); // آخر وقت سيرفر محفوظ (8:00 بغداد)
  final anchor = ClockAnchor(serverTime: server, elapsedMs: 1000000, bootId: 'count:7');

  test('the real punch time = last server time + what the phone counter counted since', () {
    // بعد ساعتين وربع (والشاشة مطفية): الوقت المؤكد 10:15 بغداد، مهما كانت ساعة الموبايل
    final t = computeOfflinePunchTime(anchor, const ClockSnapshot(elapsedMs: 1000000 + 8100000, bootId: 'count:7'));
    expect(t.check, 'anchored');
    expect(t.trustedTime, DateTime.utc(2026, 10, 15, 7, 15));
  });

  test('after a restart (counter reset or new boot) the time is unknown and needs review', () {
    expect(computeOfflinePunchTime(anchor, const ClockSnapshot(elapsedMs: 500, bootId: 'count:7')).check, 'no_anchor');
    expect(computeOfflinePunchTime(anchor, const ClockSnapshot(elapsedMs: 9000000, bootId: 'count:8')).check, 'no_anchor');
  });

  test('iPhone boot time moves a few seconds with automatic time, but a real reboot does not match', () {
    final ios = ClockAnchor(serverTime: server, elapsedMs: 1000, bootId: 'time:1760500000');
    expect(computeOfflinePunchTime(ios, const ClockSnapshot(elapsedMs: 61000, bootId: 'time:1760500003')).check, 'anchored');
    expect(computeOfflinePunchTime(ios, const ClockSnapshot(elapsedMs: 61000, bootId: 'time:1760590000')).check, 'no_anchor');
  });

  test('without a saved server time, or an unreadable counter, or a very old one: needs review', () {
    expect(computeOfflinePunchTime(null, const ClockSnapshot(elapsedMs: 5, bootId: 'count:7')).check, 'no_anchor');
    expect(computeOfflinePunchTime(anchor, null).check, 'no_anchor');
    expect(computeOfflinePunchTime(anchor, ClockSnapshot(elapsedMs: 1000000 + const Duration(days: 8).inMilliseconds, bootId: 'count:7')).check, 'no_anchor');
    expect(sameBoot('count:-1', 'count:-1'), isFalse);
  });

  test('the saved anchor survives a round trip', () {
    final back = ClockAnchor.fromJson(anchor.toJson())!;
    expect(back.serverTime, server);
    expect(back.elapsedMs, anchor.elapsedMs);
    expect(back.bootId, anchor.bootId);
  });

  test('the attendance report notes offline punches and the ones that need review', () {
    const emp = ReportEmployee(id: 'e1', name: 'علي', code: 'E1');
    ReportRow row(String? src) => ReportRow(
          date: DateTime(2026, 10, 15),
          employee: emp,
          status: ReportStatus.present,
          attendance: ReportAttendance(id: 'a1', employeeId: 'e1', date: DateTime(2026, 10, 15), status: 'present',
              checkIn: DateTime(2026, 10, 15, 9), checkOut: DateTime(2026, 10, 15, 14), checkInSource: src),
        );
    expect(row('offline_review').note, contains('تحتاج مراجعة'));
    expect(row('offline_verified').note, 'بصمة بدون إنترنت');
    expect(row('online').note, isEmpty);
  });
}
