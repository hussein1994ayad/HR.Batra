// =========================================================================
// HR Pro — سجل الموظف ورجوعه للعمل (تدقيق 14/10/2026، المرحلة 4: PAY-009، FEATURE-001)
// =========================================================================
// السيرفر يرجّع السجل جاهز (get_employee_history): باشر، انتقل من فرع لفرع، ترك، رجع — بالتاريخ.
// والتفعيل بتاريخ رجوع (reactivate_employee) يرجّع أيام الانقطاع والتنبيهات.
// =========================================================================

/// حدث واحد بسجل الموظف.
class EmployeeHistoryEvent {
  final DateTime date;

  /// join | transfer | exit | return
  final String kind;
  final String text;

  const EmployeeHistoryEvent({required this.date, required this.kind, required this.text});

  factory EmployeeHistoryEvent.fromMap(Map<String, dynamic> m) => EmployeeHistoryEvent(
        date: DateTime.tryParse('${m['date']}') ?? DateTime(2000),
        kind: '${m['kind'] ?? ''}',
        text: '${m['text'] ?? ''}',
      );

  /// اسم نوع الحدث للشارة.
  String get kindLabel => switch (kind) {
        'join' => 'مباشرة',
        'transfer' => 'نقل',
        'exit' => 'ترك',
        'return' => 'رجوع',
        _ => kind,
      };
}

/// نتيجة «تفعيل الحساب» بتاريخ رجوع.
class ReactivateResult {
  final int gapDays;
  final List<String> warnings;

  const ReactivateResult({this.gapDays = 0, this.warnings = const []});

  factory ReactivateResult.fromMap(Map<String, dynamic> m) => ReactivateResult(
        gapDays: (m['gap_days'] as num?)?.toInt() ?? 0,
        warnings: [for (final w in (m['warnings'] as List?) ?? const []) '$w'],
      );

  /// رسالة النجاح: كم يوم انقطاع ما ينحسب غياب.
  String message(String name) => gapDays > 0 ? 'رجع $name للعمل. $gapDays يوم انقطاع ما تنحسب غياب' : 'رجع $name للعمل';
}
