// =========================================================================
// HR Pro v6.0 — نموذج بيانات الدوام (Attendance Model)
// =========================================================================
// الجدول المقابل في قاعدة البيانات: public.attendance
//
// الحقول:
//   id               UUID        معرف السجل
//   employee_id      UUID        معرف الموظف
//   branch_id        UUID        معرف الفرع الذي سُجّلت فيه البصمة
//   work_date        DATE        تاريخ يوم العمل (YYYY-MM-DD)
//   check_in_time    TIMESTAMPTZ وقت تسجيل الحضور (null = لم يبصم بعد)
//   check_out_time   TIMESTAMPTZ وقت تسجيل الانصراف (null = لم ينصرف بعد)
//   check_in_lat     FLOAT8      خط العرض عند الحضور
//   check_in_lng     FLOAT8      خط الطول عند الحضور
//   check_out_lat    FLOAT8      خط العرض عند الانصراف
//   check_out_lng    FLOAT8      خط الطول عند الانصراف
//   status           TEXT        الحالة: 'present'|'late'|'absent'|'half_day'
//   is_late          BOOL        هل تأخر عن وقت الدوام؟
//   late_minutes     INT         عدد دقائق التأخير (0 إذا لم يتأخر)
//   notes            TEXT        ملاحظات (تسجيل يدوي / استثناء)
//   created_at       TIMESTAMPTZ وقت إنشاء السجل
// =========================================================================

/// يمثّل سجل دوام يومي لموظف واحد.
class AttendanceModel {
  // ─── الحقول ───────────────────────────────────────────────────────────

  final String id;
  final String employeeId;
  final String? branchId;

  /// تاريخ يوم العمل (فقط التاريخ بدون وقت)
  final DateTime workDate;

  /// وقت تسجيل الحضور (null = لم يبصم بعد)
  final DateTime? checkInTime;

  /// وقت تسجيل الانصراف (null = لم ينصرف بعد)
  final DateTime? checkOutTime;

  /// إحداثيات موقع بصمة الحضور
  final double? checkInLat;
  final double? checkInLng;

  /// إحداثيات موقع بصمة الانصراف
  final double? checkOutLat;
  final double? checkOutLng;

  /// حالة الدوام: 'present' | 'late' | 'absent' | 'half_day'
  final String status;

  /// هل تأخر الموظف؟
  final bool isLate;

  /// عدد دقائق التأخير
  final int lateMinutes;

  /// ملاحظات إضافية
  final String? notes;

  final DateTime? createdAt;

  // ─── Constructor ──────────────────────────────────────────────────────

  const AttendanceModel({
    required this.id,
    required this.employeeId,
    required this.workDate,
    required this.status,
    this.branchId,
    this.checkInTime,
    this.checkOutTime,
    this.checkInLat,
    this.checkInLng,
    this.checkOutLat,
    this.checkOutLng,
    this.isLate = false,
    this.lateMinutes = 0,
    this.notes,
    this.createdAt,
  });

  // ─── Factory: من Map إلى Model ────────────────────────────────────────

  factory AttendanceModel.fromMap(Map<String, dynamic> map) {
    return AttendanceModel(
      id:           (map['id'] ?? '') as String,
      employeeId:   (map['employee_id'] ?? '') as String,
      branchId:     map['branch_id'] as String?,
      workDate:     DateTime.parse(map['work_date'] as String),
      checkInTime:  map['check_in_time'] != null
                        ? DateTime.parse(map['check_in_time'] as String).toLocal()
                        : null,
      checkOutTime: map['check_out_time'] != null
                        ? DateTime.parse(map['check_out_time'] as String).toLocal()
                        : null,
      checkInLat:   (map['check_in_lat'] as num?)?.toDouble(),
      checkInLng:   (map['check_in_lng'] as num?)?.toDouble(),
      checkOutLat:  (map['check_out_lat'] as num?)?.toDouble(),
      checkOutLng:  (map['check_out_lng'] as num?)?.toDouble(),
      status:       (map['status'] ?? 'present') as String,
      isLate:       (map['is_late'] as bool?) ?? false,
      lateMinutes:  (map['late_minutes'] as int?) ?? 0,
      notes:        map['notes'] as String?,
      createdAt:    map['created_at'] != null
                        ? DateTime.parse(map['created_at'] as String).toLocal()
                        : null,
    );
  }

  // ─── Helpers ──────────────────────────────────────────────────────────

  /// هل سجّل الموظف الحضور؟
  bool get hasCheckIn => checkInTime != null;

  /// هل سجّل الموظف الانصراف؟
  bool get hasCheckOut => checkOutTime != null;

  /// هل الدوام مكتمل (حضور + انصراف)؟
  bool get isComplete => hasCheckIn && hasCheckOut;

  /// مدة الدوام (null إذا لم يكتمل)
  Duration? get workDuration {
    if (checkInTime == null || checkOutTime == null) return null;
    return checkOutTime!.difference(checkInTime!);
  }

  /// مدة الدوام بالساعات والدقائق كنص عربي (مثال: "7 ساعات 30 دقيقة")
  String get workDurationText {
    final d = workDuration;
    if (d == null) return '--';
    final hours = d.inHours;
    final minutes = d.inMinutes % 60;
    if (hours == 0) return '$minutes دقيقة';
    if (minutes == 0) return '$hours ساعة';
    return '$hours ساعة $minutes دقيقة';
  }
}
