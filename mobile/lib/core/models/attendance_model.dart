// =========================================================================
// نموذج سجل الحضور — الجدول: public.attendance
// =========================================================================

import '../utils/json_map.dart';

class AttendanceModel {
  final String id;
  final String employeeId;
  final String? employeeName;
  final String? branchId;

  /// work_date بصيغة YYYY-MM-DD
  final String workDate;
  final DateTime? checkInTime;
  final DateTime? checkOutTime;
  final double? checkInLat;
  final double? checkInLng;
  final double? checkOutLat;
  final double? checkOutLng;

  /// 'present' | 'late' | 'absent' | 'half_day' — null إذا ما تحدد (السجل يعرض «—»)
  final String? status;
  final bool isMockDetected;
  final bool checkOutOffline;

  /// 'pending' | 'applied' | 'ignored'
  final String? deductionStatus;
  final bool? deductionApplied;
  final String? deductionReason;
  final DateTime? createdAt;

  const AttendanceModel({
    required this.id,
    required this.employeeId,
    required this.workDate,
    this.status,
    this.employeeName,
    this.branchId,
    this.checkInTime,
    this.checkOutTime,
    this.checkInLat,
    this.checkInLng,
    this.checkOutLat,
    this.checkOutLng,
    this.isMockDetected = false,
    this.checkOutOffline = false,
    this.deductionStatus,
    this.deductionApplied,
    this.deductionReason,
    this.createdAt,
  });

  factory AttendanceModel.fromMap(JsonRow map) {
    final employee = map.obj('employees');
    return AttendanceModel(
      id: map.str('id') ?? '',
      employeeId: map.str('employee_id') ?? '',
      employeeName: employee?.str('full_name'),
      branchId: map.str('branch_id') ?? employee?.str('branch_id'),
      workDate: map.str('work_date') ?? '',
      checkInTime: map.date('check_in_time'),
      checkOutTime: map.date('check_out_time'),
      checkInLat: map.dbl('check_in_lat'),
      checkInLng: map.dbl('check_in_lng'),
      checkOutLat: map.dbl('check_out_lat'),
      checkOutLng: map.dbl('check_out_lng'),
      status: map.str('status'),
      isMockDetected: map.boolean('is_mock_detected') ?? false,
      checkOutOffline: map.boolean('check_out_offline') ?? false,
      deductionStatus: map.str('deduction_status'),
      deductionApplied: map.boolean('deduction_applied'),
      deductionReason: map.str('deduction_reason'),
      createdAt: map.date('created_at'),
    );
  }

  /// حضور فعلي (حاضر، متأخر، أو نصف يوم).
  bool get isPresent => status == 'present' || status == 'late' || status == 'half_day';
  bool get isAbsent => status == 'absent';
  bool get hasCheckIn => checkInTime != null;
  bool get hasCheckOut => checkOutTime != null;

  Duration? get workDuration =>
      checkInTime == null || checkOutTime == null ? null : checkOutTime!.difference(checkInTime!);

  /// نفس السجل ببصمة حضور ([checkIn] = true) أو انصراف بوقت وموقع جديد (دمج بصمات الجهاز بدون إنترنت).
  AttendanceModel withPunch({required bool checkIn, required DateTime? time, double? lat, double? lng}) => AttendanceModel(
        id: id,
        employeeId: employeeId,
        employeeName: employeeName,
        branchId: branchId,
        workDate: workDate,
        checkInTime: checkIn ? time : checkInTime,
        checkOutTime: checkIn ? checkOutTime : time,
        checkInLat: checkIn ? lat : checkInLat,
        checkInLng: checkIn ? lng : checkInLng,
        checkOutLat: checkIn ? checkOutLat : lat,
        checkOutLng: checkIn ? checkOutLng : lng,
        status: status,
        isMockDetected: isMockDetected,
        checkOutOffline: checkOutOffline,
        deductionStatus: deductionStatus,
        deductionApplied: deductionApplied,
        deductionReason: deductionReason,
        createdAt: createdAt,
      );
}

/// بصمة محفوظة بالجهاز (بدون إنترنت) ولسه ما انرفعت — عنصر من طابور `AttendanceSyncService`.
class QueuedPunch {
  final String? userId;

  /// 'check_in' | 'check_out'
  final String? type;

  /// الوقت كما انحفظ (ISO؛ UTC للبصمات الجديدة).
  final String? time;
  final double? latitude;
  final double? longitude;

  const QueuedPunch({this.userId, this.type, this.time, this.latitude, this.longitude});

  factory QueuedPunch.fromMap(JsonRow map) => QueuedPunch(
        userId: map.str('user_id'),
        type: map.str('type'),
        time: map.str('time'),
        latitude: map.dbl('latitude'),
        longitude: map.dbl('longitude'),
      );
}
