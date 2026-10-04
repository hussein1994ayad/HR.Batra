// =========================================================================
// التعاميم السارية (get_active_announcements)، المجازون الآن (get_on_leave_now)،
// والمتأخرون اليوم (get_late_today) — كما تعرضها الرئيسية ولوحة التعاميم.
// =========================================================================

import '../utils/json_map.dart';

/// قائمة صفوف من نتيجة RPC. صارمة مثل List<Map>.from(value as List): ترمي إذا القيمة مو قائمة صفوف،
/// حتى تبقى حالة الخطأ بالشاشة نفسها.
List<T> rowsStrict<T>(Object? value, T Function(JsonRow row) fromMap) => [
      for (final e in value as List) fromMap(Map<String, dynamic>.from(e as Map)),
    ];

DateTime? _localDate(Object? v) => DateTime.tryParse(v?.toString() ?? '')?.toLocal();

class AnnouncementModel {
  final String title;
  final String body;
  final bool isPinned;

  /// بداية العرض (starts_at، وإذا ما موجود فتاريخ الإنشاء) بالتوقيت المحلي.
  final DateTime? shownFrom;
  final DateTime? endsAt;

  const AnnouncementModel({required this.title, required this.body, this.isPinned = false, this.shownFrom, this.endsAt});

  factory AnnouncementModel.fromMap(JsonRow map) => AnnouncementModel(
        title: (map['title'] ?? 'إعلان إداري').toString(),
        body: (map['content'] ?? map['body'] ?? '').toString(),
        isPinned: map['is_pinned'] == true,
        shownFrom: _localDate(map['starts_at'] ?? map['created_at']),
        endsAt: _localDate(map['ends_at']),
      );
}

/// موظف بصورة واسم وفرع (للمجازين والمتأخرين).
abstract class PersonCardData {
  String get fullName;
  String? get avatarUrl;
  String get branchLabel;
}

class OnLeavePerson implements PersonCardData {
  final String? employeeId;
  @override
  final String fullName;
  @override
  final String? avatarUrl;

  /// اسم الفرع أو '—'.
  @override
  final String branchLabel;
  final bool isHourly;
  final String? startHour;
  final String? endHour;

  /// آخر يوم بالإجازة (عمود DATE: يُقرأ كتاريخ محلي بدون تحويل منطقة).
  final DateTime? toDate;

  const OnLeavePerson({
    this.employeeId,
    required this.fullName,
    this.avatarUrl,
    required this.branchLabel,
    this.isHourly = false,
    this.startHour,
    this.endHour,
    this.toDate,
  });

  factory OnLeavePerson.fromMap(JsonRow map) => OnLeavePerson(
        employeeId: map.str('employee_id'),
        fullName: (map['full_name'] ?? 'موظف').toString(),
        avatarUrl: map['avatar_url']?.toString(),
        branchLabel: (map['branch_name'] ?? '—').toString(),
        isHourly: map['is_hourly'] == true,
        startHour: map['start_hour']?.toString(),
        endHour: map['end_hour']?.toString(),
        toDate: DateTime.tryParse(map['to_date']?.toString() ?? ''),
      );
}

class LatePerson implements PersonCardData {
  @override
  final String fullName;
  @override
  final String? avatarUrl;
  @override
  final String branchLabel;
  final int lateMinutes;
  final DateTime? checkInTime;

  const LatePerson({required this.fullName, this.avatarUrl, required this.branchLabel, this.lateMinutes = 0, this.checkInTime});

  factory LatePerson.fromMap(JsonRow map) => LatePerson(
        fullName: (map['full_name'] ?? 'موظف').toString(),
        avatarUrl: map['avatar_url']?.toString(),
        branchLabel: (map['branch_name'] ?? '—').toString(),
        lateMinutes: (map['late_minutes'] as num?)?.toInt() ?? 0,
        checkInTime: DateTime.tryParse(map['check_in_time']?.toString() ?? ''),
      );
}
