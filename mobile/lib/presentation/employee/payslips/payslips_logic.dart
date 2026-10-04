// منطق كشوف الرواتب بدون واجهة: تواريخ الدورة المالية، أي البنود تخص الكشف،
// وتحويل أسطر محرّك الرواتب لشكل التفاصيل القديم.

import '../../../core/models/models.dart';

/// تواريخ الدورة المالية لشهر مالي (YYYY-MM): من يوم البداية (قد يكون بالشهر السابق) ليوم النهاية،
/// مقصوصة على آخر يوم بالشهر. نص غير صالح = تواريخ فارغة.
Map<String, String> payslipCycleDates(String monthStr, {required int startDay, required int endDay}) {
  try {
    final parts = monthStr.split('-');
    final int year = int.parse(parts[0]);
    final int month = int.parse(parts[1]);

    // Get last day of selected month
    final lastDaySelected = DateTime(year, month + 1, 0).day;

    if (startDay <= endDay) {
      // Same calendar month cycle
      final actualStartDay = startDay < lastDaySelected ? startDay : lastDaySelected;
      final actualEndDay = endDay < lastDaySelected ? endDay : lastDaySelected;

      final String startStr = "$year-${month.toString().padLeft(2, '0')}-${actualStartDay.toString().padLeft(2, '0')}";
      final String endStr = "$year-${month.toString().padLeft(2, '0')}-${actualEndDay.toString().padLeft(2, '0')}";
      return {'start': startStr, 'end': endStr};
    } else {
      // Cross-month cycle (starts in previous month, ends in selected month)
      final lastDayPrev = DateTime(year, month, 0).day;
      final prevMonthDate = DateTime(year, month - 1);
      final int prevYear = prevMonthDate.year;
      final int prevMonthNum = prevMonthDate.month;

      final actualStartDay = startDay < lastDayPrev ? startDay : lastDayPrev;
      final actualEndDay = endDay < lastDaySelected ? endDay : lastDaySelected;

      final String startStr = "$prevYear-${prevMonthNum.toString().padLeft(2, '0')}-${actualStartDay.toString().padLeft(2, '0')}";
      final String endStr = "$year-${month.toString().padLeft(2, '0')}-${actualEndDay.toString().padLeft(2, '0')}";
      return {'start': startStr, 'end': endStr};
    }
  } catch (e) {
    return {'start': '', 'end': ''};
  }
}

/// (الشهر، السنة) من "YYYY-MM".
(int month, int year) payslipMonthOf(String workMonth) {
  final p = workMonth.split('-');
  return (p.length > 1 ? int.tryParse(p[1]) ?? 1 : 1, int.tryParse(p.first) ?? DateTime.now().year);
}

/// فقط البنود التي دخلت في هذا الكشف: المرتبطة به (salary_slip_id)، أو اليدوية
/// المسجلة قبل اعتماده. البنود المضافة بعد الاعتماد تخص كشفاً قادماً.
List<PayslipDetail> itemsIncludedInSlip(List<Map<String, dynamic>> rows, {required String slipId, required DateTime? slipCreated}) {
  return rows.where((d) {
    final linked = d['salary_slip_id']?.toString();
    if (linked != null) return linked == slipId;
    final created = DateTime.tryParse((d['created_at'] ?? '').toString());
    return slipCreated == null || created == null || !created.isAfter(slipCreated);
  }).map(PayslipDetail.fromMap).toList();
}

const _lineLabels = {
  'absence': 'غياب',
  'late': 'تأخير',
  'early_leave': 'خروج مبكر',
  'unpaid_leave': 'إجازة بدون راتب',
  'overtime': 'ساعات إضافية',
  'manual_deduction': 'خصم',
  'bonus': 'مكافأة',
  'allowance': 'مخصصات',
  'adjustment': 'تسوية',
};

/// أسطر كشف المحرّك (salary_slip_lines) بنفس شكل تفاصيل الكشف القديمة
/// (reason / amount / issue_date / type) — أقساط السلف لها سطرها الخاص في الكشف،
/// والإجازات المدفوعة بلا مبلغ لا تظهر.
List<PayslipDetail> slipLinesToDetails(List<Map<String, dynamic>> lines) => [
      for (final l in lines)
        if (l['line_type'] != 'loan' && ((l['amount'] as num?) ?? 0) > 0)
          PayslipDetail(
            reason: _lineReason(l),
            amount: (l['amount'] as num).toDouble(),
            issueDate: l['event_date']?.toString(),
            type: ((l['direction'] as num?) ?? -1) > 0 ? 'bonus' : 'deduction',
          ),
    ];

String _lineReason(Map<String, dynamic> l) {
  final type = (l['line_type'] ?? '').toString();
  final label = _lineLabels[type] ?? 'بند';
  final minutes = ((l['minutes'] as num?) ?? 0).round();
  final notes = (l['notes'] ?? '').toString().trim();
  final base = type == 'bonus' || type == 'manual_deduction' || type == 'adjustment'
      ? (notes.isNotEmpty ? notes : label)
      : minutes > 0
          ? '$label $minutes دقيقة'
          : label;
  final carried = (l['carried_from'] ?? '').toString();
  return carried.isEmpty ? base : '$base (مرحّل من $carried)';
}
