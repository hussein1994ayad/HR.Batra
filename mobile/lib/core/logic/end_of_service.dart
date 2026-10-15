// =========================================================================
// HR Pro — معاينة «إنهاء الخدمات» (تدقيق 14/10/2026، المرحلة 3، PAY-001)
// =========================================================================
// السيرفر (end_of_service_preview) يحسب آخر راتب لو آخر يوم = يوم معيّن ويتراجع، فما يتغير شي.
// هنا نحوّل النتيجة لأسطر بسيطة نعرضها قبل تأكيد التعطيل (نفس صياغة الموقع).
// =========================================================================

import '../design/formatters.dart';

/// مسير واحد بالمعاينة.
class EndOfServicePeriod {
  final String month;
  final DateTime cutoffDate;
  final bool canApproveNow;
  final num expectedNet;
  final num loanCut;
  final num excessDeductions;
  final num basic;
  final String? basicNote;
  final num earnings;
  final num deductions;
  final num loans;
  final int pendingCount;

  const EndOfServicePeriod({
    required this.month,
    required this.cutoffDate,
    required this.canApproveNow,
    required this.expectedNet,
    required this.loanCut,
    required this.excessDeductions,
    required this.basic,
    required this.basicNote,
    required this.earnings,
    required this.deductions,
    required this.loans,
    required this.pendingCount,
  });

  factory EndOfServicePeriod.fromMap(Map<String, dynamic> m) {
    final s = Map<String, dynamic>.from((m['summary'] as Map?) ?? const {});
    num n(Object? v) => v is num ? v : num.tryParse('${v ?? ''}') ?? 0;
    return EndOfServicePeriod(
      month: '${m['month'] ?? ''}',
      cutoffDate: DateTime.tryParse('${m['cutoff_date']}') ?? DateTime(2000),
      canApproveNow: m['can_approve_now'] == true,
      expectedNet: n(m['expected_net']),
      loanCut: n(m['loan_cut']),
      excessDeductions: n(m['excess_deductions']),
      basic: n(s['basic']),
      basicNote: s['basic_note'] as String?,
      earnings: n(s['earnings']),
      deductions: n(s['deductions']),
      loans: n(s['loans']),
      pendingCount: n(s['pending_count']).toInt(),
    );
  }

  /// "2026-11" → "الشهر الحادي عشر 2026"
  String get monthName {
    final p = month.split('-');
    final y = int.tryParse(p.first) ?? 0;
    final mo = p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0;
    return Fmt.monthNumber(mo, y);
  }
}

/// نتيجة المعاينة كلها.
class EndOfServicePreview {
  final DateTime lastDay;
  final List<EndOfServicePeriod> periods;
  final num totalNet;
  final num loansLeftAfter;

  const EndOfServicePreview({required this.lastDay, required this.periods, required this.totalNet, required this.loansLeftAfter});

  factory EndOfServicePreview.fromMap(Map<String, dynamic> m) {
    num n(Object? v) => v is num ? v : num.tryParse('${v ?? ''}') ?? 0;
    return EndOfServicePreview(
      lastDay: DateTime.tryParse('${m['last_day']}') ?? DateTime(2000),
      periods: [
        for (final p in (m['periods'] as List?) ?? const [])
          if (p is Map) EndOfServicePeriod.fromMap(Map<String, dynamic>.from(p)),
      ],
      totalNet: n(m['total_net']),
      loansLeftAfter: n(m['loans_left_after']),
    );
  }

  /// الشرح كنص: لكل مسير شلون انحسب، الخصومات، السلفة، الصافي، ومتى ينعتمد.
  String describe() {
    final out = <String>[];
    for (final p in periods) {
      out.add('مسير ${p.monthName}:');
      out.add('• ${p.basicNote ?? 'الأساسي ${Fmt.iqd(p.basic)}'}');
      if (p.earnings > 0) out.add('• مكافآت وإضافي: +${Fmt.iqd(p.earnings)}');
      if (p.deductions > 0) out.add('• خصومات قررتها الإدارة: -${Fmt.iqd(p.deductions)}');
      if (p.loans > 0) {
        out.add(p.loanCut > 0
            ? '• قسط سلفة ${Fmt.iqd(p.loans)}: ينخصم منه ${Fmt.iqd(p.loans - p.loanCut)} بس (الراتب ما يكفي)'
            : '• قسط سلفة: -${Fmt.iqd(p.loans)}');
      }
      if (p.excessDeductions > 0) {
        out.add('• خصومات أكثر من الراتب بـ ${Fmt.iqd(p.excessDeductions)}: ما تنخصم وتتسوى خارج النظام');
      }
      if (p.pendingCount > 0) out.add('• ${p.pendingCount} حركة تنتظر قرارك (غياب/تأخير)');
      final after = p.cutoffDate.isBefore(lastDay) ? p.cutoffDate : lastDay;
      out.add('الصافي: ${Fmt.iqd(p.expectedNet)} · ${p.canApproveNow ? 'تكدر تعتمده هسه' : 'ينعتمد بعد ${Fmt.date(after)}'}');
      out.add('');
    }
    if (periods.length > 1) out.add('المجموع المستحق: ${Fmt.iqd(totalNet)}');
    if (periods.isEmpty) out.add('ما عنده راتب مفتوح لهاليوم (رواتبه معتمدة).');
    if (loansLeftAfter > 0) out.add('باقي عليه سلف ${Fmt.iqd(loansLeftAfter)} بعد آخر راتب: تسويها ويا الموظف خارج النظام.');
    out.add('الجمع والعطل الرسمية ما تنحسب. ينخصم بس اللي قررته أنت.');
    return out.join('\n').trim();
  }
}
