import 'package:flutter_test/flutter_test.dart';
import 'package:hr_pro/core/models/models.dart';
import 'package:hr_pro/presentation/admin/branches/branches_logic.dart';

void main() {
  test('mergeBranchSchedules pairs each branch with its schedule, or an empty one', () {
    final merged = mergeBranchSchedules(
      [
        {'id': 'b1', 'name': 'الكرادة'},
        {'id': 'b2', 'name': 'المنصور'},
      ],
      [
        {'id': 's1', 'branch_id': 'b2', 'check_in_time': '08:00:00', 'work_days': [0, 1, 2], 'grace_period_minutes': 10},
      ],
    );
    expect(merged.map((b) => (b.zoneId, b.zoneName, b.hasSchedule)), [('b1', 'الكرادة', false), ('b2', 'المنصور', true)]);
    final empty = merged.first.schedule;
    expect((empty.id, empty.workDays, empty.checkInTime, empty.gracePeriodMinutes, empty.reminderMinutesAfter), (null, null, null, null, null));
    final s = merged.last.schedule;
    expect((s.id, s.checkInTime, s.gracePeriodMinutes), ('s1', '08:00:00', 10));
    expect(s.workDays, [0, 1, 2]);
  });

  test('no branches gives an empty list', () {
    expect(mergeBranchSchedules(const [], const [{'branch_id': 'x'}]), isEmpty);
  });

  test('BranchModel keeps missing location/radius as null and names lists with a fallback', () {
    final b = BranchModel.fromMap(const {'id': 'b1', 'latitude': 33.3, 'longitude': '44.4'});
    expect((b.latitude, b.longitude, b.hasLocation, b.radiusMeters, b.rawName, b.name), (33.3, null, false, null, null, 'فرع'));
  });
}
