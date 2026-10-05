// منطق شاشات الأفرع بدون واجهة.

import '../../../core/models/models.dart';

/// يدمج كل فرع مع جدول دوامه (إن وجد؛ وإلا جدول فارغ و hasSchedule = false).
List<BranchWithSchedule> mergeBranchSchedules(List<dynamic> branchRows, List<dynamic> scheduleRows) {
  final zones = [for (final z in branchRows) Map<String, dynamic>.from(z as Map)];
  final schedules = [for (final s in scheduleRows) Map<String, dynamic>.from(s as Map)];

  final List<BranchWithSchedule> merged = [];
  for (final zone in zones) {
    final schedule = schedules.firstWhere(
      (s) => s['branch_id'] == zone['id'],
      orElse: () => <String, dynamic>{},
    );
    merged.add(BranchWithSchedule(
      zoneId: zone.str('id'),
      zoneName: zone.str('name'),
      hasSchedule: schedule.isNotEmpty,
      schedule: BranchSchedule.fromMap(schedule),
    ));
  }
  return merged;
}
