// =========================================================================
// رصيد إجازات الموظف (get_leave_balance): السنوية والمرضية لهذه السنة، والزمنيات لهذا الشهر.
// =========================================================================

import '../utils/json_map.dart';

class LeaveBalance {
  final Object? year;

  /// المتبقي والاستحقاق كما تصل (num أو null).
  final num? annualLeft;
  final num? annualEntitlement;
  final num? sickLeft;
  final num? sickEntitlement;
  final num? hourlyLeftHours;
  final num? hourlyAllowanceHours;

  const LeaveBalance({
    this.year,
    this.annualLeft,
    this.annualEntitlement,
    this.sickLeft,
    this.sickEntitlement,
    this.hourlyLeftHours,
    this.hourlyAllowanceHours,
  });

  /// صارم: يرمي إذا ناقص قسم (annual/sick/hourly) — الشاشة تخفي الكارت عندها.
  factory LeaveBalance.fromMap(JsonRow map) {
    final annual = Map<String, dynamic>.from(map['annual'] as Map);
    final sick = Map<String, dynamic>.from(map['sick'] as Map);
    final hourly = Map<String, dynamic>.from(map['hourly'] as Map);
    return LeaveBalance(
      year: map['year'],
      annualLeft: annual['left'] as num?,
      annualEntitlement: annual['entitlement'] as num?,
      sickLeft: sick['left'] as num?,
      sickEntitlement: sick['entitlement'] as num?,
      hourlyLeftHours: hourly['left_hours'] as num?,
      hourlyAllowanceHours: hourly['allowance_hours'] as num?,
    );
  }
}
