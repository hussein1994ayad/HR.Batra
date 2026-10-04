// منطق شاشات الأفرع بدون واجهة.

/// يدمج كل فرع مع جدول دوامه (إن وجد): zone_id, zone_name, has_schedule, schedule ({} إذا ماكو جدول).
List<Map<String, dynamic>> mergeBranchSchedules(List<dynamic> branchRows, List<dynamic> scheduleRows) {
  final zones = [for (final z in branchRows) Map<String, dynamic>.from(z as Map)];
  final schedules = [for (final s in scheduleRows) Map<String, dynamic>.from(s as Map)];

  final List<Map<String, dynamic>> merged = [];
  for (final zone in zones) {
    final schedule = schedules.firstWhere(
      (s) => s['branch_id'] == zone['id'],
      orElse: () => <String, dynamic>{},
    );
    merged.add({
      'zone_id': zone['id'],
      'zone_name': zone['name'],
      'has_schedule': schedule.isNotEmpty,
      'schedule': schedule,
    });
  }
  return merged;
}
