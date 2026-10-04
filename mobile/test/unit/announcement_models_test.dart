import 'package:flutter_test/flutter_test.dart';
import 'package:hr_pro/core/models/models.dart';
import 'package:hr_pro/presentation/employee/announcements/announcement_widgets.dart';

void main() {
  final now = DateTime(2026, 10, 4, 12);

  group('AnnouncementModel', () {
    test('defaults and start fallback to created_at', () {
      final a = AnnouncementModel.fromMap({'created_at': '2026-10-01T09:00:00Z', 'body': 'نص'});
      expect(a.title, 'إعلان إداري');
      expect(a.body, 'نص');
      expect(a.shownFrom, DateTime.parse('2026-10-01T09:00:00Z').toLocal());
      expect(a.isPinned, isFalse);
    });

    test('remaining time wording', () {
      AnnouncementModel ends(DateTime d) => AnnouncementModel.fromMap({'ends_at': d.toUtc().toIso8601String()});
      expect(announcementRemaining(ends(DateTime(2026, 10, 4, 20)), now: now), 'ينتهي اليوم');
      expect(announcementRemaining(ends(DateTime(2026, 10, 5, 9)), now: now), 'ينتهي غداً');
      expect(announcementRemaining(ends(DateTime(2026, 10, 9)), now: now), 'باقي 5 أيام');
      expect(announcementRemaining(AnnouncementModel.fromMap(const {}), now: now), isNull);
    });

    test('progress is null without an end, clamped otherwise', () {
      final a = AnnouncementModel.fromMap({
        'starts_at': DateTime(2026, 10, 2, 12).toUtc().toIso8601String(),
        'ends_at': DateTime(2026, 10, 6, 12).toUtc().toIso8601String(),
      });
      expect(announcementProgress(a, now: now), closeTo(0.5, 0.001));
      expect(announcementProgress(AnnouncementModel.fromMap(const {}), now: now), isNull);
    });

    test('rowsStrict throws on a non-list like the old cast did', () {
      expect(() => rowsStrict(null, AnnouncementModel.fromMap), throwsA(isA<TypeError>()));
      expect(rowsStrict([<String, dynamic>{'title': 'x'}], AnnouncementModel.fromMap).single.title, 'x');
    });
  });

  group('OnLeavePerson', () {
    test('daily leave: until and return', () {
      final p = OnLeavePerson.fromMap(const {'full_name': 'سارة', 'to_date': '2026-10-06'});
      expect(onLeaveUntil(p, now: now), 'حتى 6 تشرين الأول');
      expect(onLeaveReturn(p, now: now), 'يعود بعد 3 أيام');
      expect(p.branchLabel, '—');
    });

    test('last day today and hourly leave', () {
      expect(onLeaveUntil(OnLeavePerson.fromMap(const {'to_date': '2026-10-04'}), now: now), 'آخر يوم اليوم');
      final h = OnLeavePerson.fromMap(const {'is_hourly': true, 'start_hour': '10:00:00', 'end_hour': '12:00:00'});
      expect(onLeaveUntil(h, now: now), '10:00 ص – 12:00 م');
      expect(onLeaveReturn(h, now: now), isNull);
    });
  });

  test('LatePerson duration wording', () {
    expect(lateDuration(LatePerson.fromMap(const {'late_minutes': 40})), '40 دقيقة');
    expect(lateDuration(LatePerson.fromMap(const {'late_minutes': 40}), short: true), '40 د');
    expect(lateDuration(LatePerson.fromMap(const {'late_minutes': 75})), '1 س 15 د');
    expect(LatePerson.fromMap(const {}).fullName, 'موظف');
  });
}
