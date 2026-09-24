// =========================================================================
// HR Pro v6.0 — نموذج الإشعار (Notification Model)
// =========================================================================
// الجدول المقابل في قاعدة البيانات: public.notifications
//
// الحقول:
//   id           UUID    معرف الإشعار
//   employee_id  UUID    معرف الموظف المستلِم
//   title        TEXT    عنوان الإشعار
//   body         TEXT    نص الإشعار
//   type         TEXT    النوع: 'system'|'leave'|'loan'|'announcement'|'payslip'
//   is_read      BOOL    هل قرأ الموظف الإشعار؟
//   created_at   TIMESTAMPTZ وقت إنشاء الإشعار
// =========================================================================

/// يمثّل إشعاراً داخل التطبيق.
class NotificationModel {
  final String id;
  final String employeeId;
  final String title;
  final String body;

  /// النوع: 'system' | 'leave' | 'loan' | 'announcement' | 'payslip'
  final String type;

  final bool isRead;
  final DateTime? createdAt;

  const NotificationModel({
    required this.id,
    required this.employeeId,
    required this.title,
    required this.body,
    required this.type,
    this.isRead = false,
    this.createdAt,
  });

  factory NotificationModel.fromMap(Map<String, dynamic> map) {
    return NotificationModel(
      id:         (map['id'] ?? '') as String,
      employeeId: (map['employee_id'] ?? '') as String,
      title:      (map['title'] ?? '') as String,
      body:       (map['body'] ?? '') as String,
      type:       (map['type'] ?? 'system') as String,
      isRead:     (map['is_read'] as bool?) ?? false,
      createdAt:  map['created_at'] != null
                      ? DateTime.parse(map['created_at'] as String).toLocal()
                      : null,
    );
  }
}
