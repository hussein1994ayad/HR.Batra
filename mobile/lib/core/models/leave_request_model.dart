// =========================================================================
// نموذج طلب الإجازة — الجدول: public.leave_requests
// =========================================================================

import '../utils/json_map.dart';

/// الاسم العربي لنوع الإجازة (القيم في leave_type).
String leaveTypeArabic(String? type) {
  switch (type) {
    case 'annual':
      return 'إجازة سنوية';
    case 'sick':
      return 'إجازة مرضية';
    case 'emergency':
      return 'إجازة طارئة';
    case 'maternity':
      return 'إجازة أمومة';
    default:
      return 'إجازة أخرى';
  }
}

String leaveStatusArabic(String? status) {
  switch (status) {
    case 'approved':
      return 'موافق عليه';
    case 'rejected':
      return 'مرفوض';
    default:
      return 'قيد المراجعة';
  }
}

class LeaveRequestModel {
  final String id;
  final String employeeId;
  final String? employeeName;
  final String leaveType;
  final DateTime startDate;
  final DateTime endDate;
  final bool isHourly;

  /// "HH:MM:SS" للإجازة الزمنية
  final String? startHour;
  final String? endHour;
  final bool isPaid;
  final String? reason;

  /// 'pending' | 'approved' | 'rejected'
  final String status;
  final String? attachmentUrl;
  final String? rejectionReason;
  final String? approvedBy;
  final DateTime? approvedAt;
  final DateTime? createdAt;

  const LeaveRequestModel({
    required this.id,
    required this.employeeId,
    required this.leaveType,
    required this.startDate,
    required this.endDate,
    required this.status,
    this.employeeName,
    this.isHourly = false,
    this.startHour,
    this.endHour,
    this.isPaid = true,
    this.reason,
    this.attachmentUrl,
    this.rejectionReason,
    this.approvedBy,
    this.approvedAt,
    this.createdAt,
  });

  factory LeaveRequestModel.fromMap(JsonRow map) => LeaveRequestModel(
        id: map.str('id') ?? '',
        employeeId: map.str('employee_id') ?? '',
        employeeName: map.obj('employees')?.str('full_name'),
        leaveType: map.str('leave_type') ?? 'other',
        startDate: map.date('start_date') ?? DateTime(1970),
        endDate: map.date('end_date') ?? DateTime(1970),
        isHourly: map.boolean('is_hourly') ?? false,
        startHour: map.str('start_hour'),
        endHour: map.str('end_hour'),
        isPaid: map.boolean('is_paid') ?? true,
        reason: map.str('reason'),
        status: map.str('status') ?? 'pending',
        attachmentUrl: map.str('attachment_url'),
        rejectionReason: map.str('rejection_reason'),
        approvedBy: map.str('approved_by'),
        approvedAt: map.date('approved_at'),
        createdAt: map.date('created_at'),
      );

  String get typeArabic => leaveTypeArabic(leaveType);
  String get statusArabic => leaveStatusArabic(status);

  /// عدد الأيام التقويمية (للإجازة اليومية).
  int get daysCount =>
      DateTime(endDate.year, endDate.month, endDate.day)
          .difference(DateTime(startDate.year, startDate.month, startDate.day))
          .inDays +
      1;

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';
  bool get hasAttachment => attachmentUrl != null && attachmentUrl!.isNotEmpty;
}
