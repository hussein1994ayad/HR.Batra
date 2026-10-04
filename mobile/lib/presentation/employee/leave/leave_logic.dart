// منطق شاشة الإجازات بدون واجهة: أسماء الأنواع، تنسيق المدة، قراءة السياسة، والتحقق من التواريخ.

import '../../../core/models/models.dart';

/// اسم النوع بدون كلمة "إجازة" (أسماء السياسة تبدأ بها أحياناً، والنص يضيفها) — كان يظهر "إجازة إجازة سنوية"
String bareLeaveTypeName(String name) => name.replaceFirst(RegExp(r'^إجازة\s*'), '');

String formatLeaveMinutes(int m) {
  final h = m ~/ 60;
  final r = m % 60;
  if (h == 0) return '$r د';
  return r == 0 ? '$h س' : '$h س $r د';
}

/// أنواع الإجازات من صف leave_policy (value.active_types). فارغة = تبقى الأنواع الافتراضية.
List<Map<String, String>> parseActiveLeaveTypes(Map<String, dynamic>? row) {
  final List<Map<String, String>> mappedTypes = [];
  if (row != null && row['value'] != null) {
    final policy = row['value'] as Map<String, dynamic>;
    if (policy['active_types'] != null) {
      final typesList = policy['active_types'] as List<dynamic>;
      for (final t in typesList) {
        final typeMap = t as Map<String, dynamic>;
        mappedTypes.add({'id': typeMap['id']?.toString() ?? '', 'name': typeMap['name']?.toString() ?? ''});
      }
    }
  }
  return mappedTypes;
}

/// اسم نوع الطلب للعرض: من السياسة أولاً، وإلا الأسماء الثابتة.
String leaveTypeLabel(Object? type, List<Map<String, String>> leaveTypes) {
  final id = (type ?? 'other').toString();
  final fromPolicy = leaveTypes.where((t) => t['id'] == id);
  if (fromPolicy.isNotEmpty) return bareLeaveTypeName(fromPolicy.first['name']!);
  return switch (id) {
    'annual' => 'اعتيادية',
    'sick' => 'مرضية',
    'emergency' => 'طارئة',
    'maternity' => 'أمومة',
    'other' => 'أخرى',
    _ => id,
  };
}

/// "HH:MM:00" لأوقات الإجازة الساعية.
String leaveHourString(int hour, int minute) => '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}:00';

/// التحقق قبل الإرسال — يرجع رسالة الخطأ أو null.
String? validateLeaveDates({
  required DateTime startDay,
  required DateTime endDay,
  required bool isHourly,
  required int hourlyMinutes,
  required List<LeaveRequestModel> history,
  required DateTime now,
}) {
  final today = DateTime(now.year, now.month, now.day);
  if (startDay.isBefore(today.subtract(const Duration(days: 30)))) return 'لا يمكن طلب إجازة لتاريخ مضى عليه أكثر من 30 يوماً';
  if (!isHourly && endDay.isBefore(startDay)) return 'تاريخ النهاية يجب أن يكون بعد تاريخ البداية أو مساوياً له';
  if (isHourly && hourlyMinutes <= 0) return 'وقت النهاية يجب أن يكون بعد وقت البداية';

  // start_date و end_date إلزاميان بالقاعدة (NOT NULL)، والنموذج يحوّلهما للتوقيت المحلي
  for (final req in history) {
    if (req.status == 'rejected' || req.status == 'cancelled') continue;
    final reqStart = req.startDate;
    final reqEnd = req.endDate;
    final rStartDay = DateTime(reqStart.year, reqStart.month, reqStart.day);
    final rEndDay = DateTime(reqEnd.year, reqEnd.month, reqEnd.day);
    if (!(endDay.isBefore(rStartDay) || startDay.isAfter(rEndDay))) {
      return 'توجد إجازة سابقة تتعارض مع التواريخ المحددة';
    }
  }
  return null;
}
