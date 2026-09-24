// =========================================================================
// HR Pro v6.0 — نموذج طلب الإجازة (Leave Request Model)
// =========================================================================
// الجدول المقابل في قاعدة البيانات: public.leave_requests
//
// الحقول:
//   id           UUID    معرف الطلب
//   employee_id  UUID    معرف الموظف مقدّم الطلب
//   leave_type   TEXT    نوع الإجازة: 'annual'|'sick'|'emergency'|'unpaid'|'maternity'
//   start_date   DATE    تاريخ بداية الإجازة
//   end_date     DATE    تاريخ نهاية الإجازة
//   reason       TEXT    سبب الإجازة (يكتبه الموظف)
//   status       TEXT    حالة الطلب: 'pending'|'approved'|'rejected'
//   admin_notes  TEXT    ملاحظات المدير عند الرفض أو القبول
//   approved_by  UUID    معرف المدير الذي وافق/رفض
//   created_at   TIMESTAMPTZ تاريخ تقديم الطلب
// =========================================================================

/// أنواع الإجازات المتاحة
enum LeaveType {
  annual,    // إجازة سنوية
  sick,      // إجازة مرضية
  emergency, // إجازة طارئة
  unpaid,    // إجازة بدون راتب
  maternity, // إجازة أمومة
}

extension LeaveTypeExtension on LeaveType {
  /// الاسم العربي لنوع الإجازة
  String get arabicName {
    switch (this) {
      case LeaveType.annual:    return 'إجازة سنوية';
      case LeaveType.sick:      return 'إجازة مرضية';
      case LeaveType.emergency: return 'إجازة طارئة';
      case LeaveType.unpaid:    return 'إجازة بدون راتب';
      case LeaveType.maternity: return 'إجازة أمومة';
    }
  }

  static LeaveType fromString(String s) {
    switch (s) {
      case 'sick':      return LeaveType.sick;
      case 'emergency': return LeaveType.emergency;
      case 'unpaid':    return LeaveType.unpaid;
      case 'maternity': return LeaveType.maternity;
      default:          return LeaveType.annual;
    }
  }
}

/// حالات طلب الإجازة
enum LeaveStatus { pending, approved, rejected }

extension LeaveStatusExtension on LeaveStatus {
  String get arabicName {
    switch (this) {
      case LeaveStatus.pending:  return 'قيد المراجعة';
      case LeaveStatus.approved: return 'موافق عليه';
      case LeaveStatus.rejected: return 'مرفوض';
    }
  }
  static LeaveStatus fromString(String s) {
    switch (s) {
      case 'approved': return LeaveStatus.approved;
      case 'rejected': return LeaveStatus.rejected;
      default:         return LeaveStatus.pending;
    }
  }
}

/// يمثّل طلب إجازة مقدَّم من موظف.
class LeaveRequestModel {
  final String id;
  final String employeeId;
  final String leaveType;      // نص مطابق للقيمة في DB
  final DateTime startDate;
  final DateTime endDate;
  final String reason;
  final String status;         // نص مطابق للقيمة في DB
  final String? adminNotes;
  final String? approvedBy;
  final DateTime? createdAt;

  const LeaveRequestModel({
    required this.id,
    required this.employeeId,
    required this.leaveType,
    required this.startDate,
    required this.endDate,
    required this.reason,
    required this.status,
    this.adminNotes,
    this.approvedBy,
    this.createdAt,
  });

  factory LeaveRequestModel.fromMap(Map<String, dynamic> map) {
    return LeaveRequestModel(
      id:          (map['id'] ?? '') as String,
      employeeId:  (map['employee_id'] ?? '') as String,
      leaveType:   (map['leave_type'] ?? 'annual') as String,
      startDate:   DateTime.parse(map['start_date'] as String),
      endDate:     DateTime.parse(map['end_date'] as String),
      reason:      (map['reason'] ?? '') as String,
      status:      (map['status'] ?? 'pending') as String,
      adminNotes:  map['admin_notes'] as String?,
      approvedBy:  map['approved_by'] as String?,
      createdAt:   map['created_at'] != null
                       ? DateTime.parse(map['created_at'] as String)
                       : null,
    );
  }

  /// عدد أيام الإجازة المطلوبة
  int get daysCount => endDate.difference(startDate).inDays + 1;

  bool get isPending  => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';
}
