// =========================================================================
// نموذج الإشعار — الجدول: public.notifications
// =========================================================================

import '../utils/json_map.dart';

class NotificationModel {
  final String id;
  final String employeeId;
  final String title;
  final String body;

  /// 'leave' | 'loan' | 'bonus_deduction' | 'attendance' | 'device' | 'memo' | ...
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

  factory NotificationModel.fromMap(JsonRow map) => NotificationModel(
        id: map.str('id') ?? '',
        employeeId: map.str('employee_id') ?? '',
        // العنوان الافتراضي هو اللي تعرضه شاشة الإشعارات
        title: map.str('title') ?? 'تنبيه',
        body: map.str('body') ?? '',
        type: map.str('type') ?? 'system',
        isRead: map.boolean('is_read') ?? false,
        createdAt: map.date('created_at'),
      );
}
