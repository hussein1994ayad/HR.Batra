// =========================================================================
// جدول دوام على مستوى الفرع (work_schedules بدون موظف أو قسم) — لشاشة "أوقات الدوام".
// الحقول nullable كما تصل، والشاشة تعرض بدائلها (15 د سماحية، 5 د تذكير، 8 ص – 4 م...).
// =========================================================================

import '../utils/json_map.dart';

class BranchSchedule {
  final String? id;

  /// أيام الدوام بترقيم القاعدة (0 = الأحد)؛ null إذا العمود فارغ.
  final List<int>? workDays;
  final String? checkInTime;
  final String? checkOutTime;
  final int? gracePeriodMinutes;
  final int? reminderMinutesAfter;

  const BranchSchedule({this.id, this.workDays, this.checkInTime, this.checkOutTime, this.gracePeriodMinutes, this.reminderMinutesAfter});

  factory BranchSchedule.fromMap(JsonRow map) {
    final days = map['work_days'] as List<dynamic>?;
    return BranchSchedule(
      id: map.str('id'),
      workDays: days == null ? null : [for (final d in days) (d as num).toInt()],
      checkInTime: map['check_in_time']?.toString(),
      checkOutTime: map['check_out_time']?.toString(),
      gracePeriodMinutes: (map['grace_period_minutes'] as num?)?.toInt(),
      reminderMinutesAfter: (map['reminder_minutes_after'] as num?)?.toInt(),
    );
  }
}

/// فرع مع جدول دوامه (أو بدون جدول).
class BranchWithSchedule {
  final String? zoneId;
  final String? zoneName;
  final bool hasSchedule;

  /// جدول فارغ (كل الحقول null) إذا [hasSchedule] = false.
  final BranchSchedule schedule;

  const BranchWithSchedule({required this.zoneId, required this.zoneName, required this.hasSchedule, required this.schedule});
}
