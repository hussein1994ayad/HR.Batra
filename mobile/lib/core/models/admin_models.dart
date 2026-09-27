// =========================================================================
// نماذج لوحة الإدارة: طلبات الأجهزة، سجل الأمان، وقرارات الغياب/التأخير
// =========================================================================

import '../utils/json_map.dart';

/// طلب اعتماد جهاز جديد — الجدول: public.employee_devices
class DeviceRequest {
  final String id;
  final String employeeId;
  final String employeeName;
  final String deviceId;
  final String? model;
  final String? osVersion;
  final DateTime? createdAt;

  const DeviceRequest({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.deviceId,
    this.model,
    this.osVersion,
    this.createdAt,
  });

  factory DeviceRequest.fromMap(JsonRow map) => DeviceRequest(
        id: map.str('id') ?? '',
        employeeId: map.str('employee_id') ?? '',
        employeeName: map.obj('employees')?.str('full_name') ?? 'موظف غير معروف',
        deviceId: map.str('device_id') ?? '',
        model: map.str('model'),
        osVersion: map.str('os_version'),
        createdAt: map.date('created_at'),
      );
}

enum SecurityLogType { mockGps, geofence }

/// خرق أمني: محاولة تزييف موقع أو مخالفة سياج جغرافي.
class SecurityLog {
  final SecurityLogType type;
  final String employeeName;
  final DateTime timestamp;
  final String details;

  /// "lat, lng" لمحاولات التزييف، وفارغ للمخالفات
  final String latLng;

  const SecurityLog({
    required this.type,
    required this.employeeName,
    required this.timestamp,
    required this.details,
    this.latLng = '',
  });

  factory SecurityLog.fromMockAttempt(JsonRow map) => SecurityLog(
        type: SecurityLogType.mockGps,
        employeeName: map.obj('employees')?.str('full_name') ?? 'موظف غير معروف',
        timestamp: map.date('timestamp') ?? DateTime(1970),
        details: 'محاولة تزييف موقع باستخدام: ${map.str('app_used') ?? 'تطبيق غير معروف'}',
        latLng: '${map.str('latitude')}, ${map.str('longitude')}',
      );

  factory SecurityLog.fromGeofenceViolation(JsonRow map) => SecurityLog(
        type: SecurityLogType.geofence,
        employeeName: map.obj('employees')?.str('full_name') ?? 'موظف غير معروف',
        timestamp: map.date('timestamp') ?? DateTime(1970),
        details: map.str('violation_type') == 'entry' ? 'دخول غير مصرح به' : 'خروج غير مصرح به',
      );
}

/// سجل غياب/تأخير/نصف يوم بانتظار قرار الخصم أو الإعفاء.
/// الغياب "الافتراضي" موظف بلا أي سجل في يوم عمله؛ يُنشأ سجله عند اتخاذ القرار.
class PendingDecision {
  /// null للغياب الافتراضي
  final String? attendanceId;
  final String employeeId;
  final String employeeName;
  final String? branchId;

  /// 'absent' | 'late' | 'half_day'
  final String status;

  /// YYYY-MM-DD
  final String workDate;
  final DateTime? checkInTime;
  final DateTime? checkOutTime;

  const PendingDecision({
    required this.employeeId,
    required this.employeeName,
    required this.status,
    required this.workDate,
    this.attendanceId,
    this.branchId,
    this.checkInTime,
    this.checkOutTime,
  });

  factory PendingDecision.fromAttendance(JsonRow map) {
    final employee = map.obj('employees');
    return PendingDecision(
      attendanceId: map.str('id'),
      employeeId: map.str('employee_id') ?? '',
      employeeName: employee?.str('full_name') ?? 'موظف غير معروف',
      branchId: map.str('branch_id') ?? employee?.str('branch_id'),
      status: map.str('status') ?? 'absent',
      workDate: map.str('work_date') ?? '',
      checkInTime: map.date('check_in_time'),
      checkOutTime: map.date('check_out_time'),
    );
  }

  bool get isVirtual => attendanceId == null;

  String get statusArabic {
    switch (status) {
      case 'late':
        return 'تأخير';
      case 'half_day':
        return 'نصف يوم';
      default:
        return 'غياب';
    }
  }

  /// مفتاح ثابت للقائمة (يحفظ حالة حقول الإدخال عند إعادة البناء).
  String get key => attendanceId ?? 'virtual_${employeeId}_$workDate';
}
