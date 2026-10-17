// منطق كشوف الرواتب بدون واجهة: تواريخ الدورة المالية، أي البنود تخص الكشف،
// وتحويل أسطر محرّك الرواتب لشكل التفاصيل القديم.

import '../../../core/models/models.dart';
import '../../../core/utils/company_time.dart';

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
  return (p.length > 1 ? int.tryParse(p[1]) ?? 1 : 1, int.tryParse(p.first) ?? companyNow().year);
}

/// فقط البنود التي دخلت في هذا الكشف: المرتبطة به (salary_slip_id)، أو اليدوية
/// المسجلة قبل اعتماده. البنود المضافة بعد الاعتماد تخص كشفاً قادماً.
List<PayslipDetail> itemsIncludedInSlip(List<PayslipDetail> rows, {required String slipId, required DateTime? slipCreated}) {
  return rows.where((d) {
    final linked = d.salarySlipId;
    if (linked != null) return linked == slipId;
    final created = d.createdAt;
    return slipCreated == null || created == null || !created.isAfter(slipCreated);
  }).toList();
}

/// أسطر كشف المحرّك (salary_slip_lines) بنفس شكل تفاصيل الكشف القديمة
/// (reason / amount / issue_date / type) — أقساط السلف لها سطرها الخاص في الكشف،
/// والإجازات المدفوعة بلا مبلغ لا تظهر.
List<PayslipDetail> slipLinesToDetails(List<SalarySlipLine> lines) => [
      for (final l in lines)
        if (l.lineType != 'loan' && l.amount > 0)
          PayslipDetail(
            reason: _lineReason(l),
            amount: l.amount,
            issueDate: l.eventDate,
            type: l.direction > 0 ? 'bonus' : 'deduction',
          ),
    ];

String _lineReason(SalarySlipLine l) {
  final type = l.lineType ?? '';
  final label = kPayrollEventLabels[type] ?? 'بند';
  final minutes = l.minutes.round();
  final notes = (l.notes ?? '').trim();
  final base = type == 'bonus' || type == 'manual_deduction' || type == 'adjustment'
      ? (notes.isNotEmpty ? notes : label)
      : minutes > 0
          ? '$label $minutes دقيقة'
          : label;
  final carried = l.carriedFrom ?? '';
  return carried.isEmpty ? base : '$base (مرحّل من $carried)';
}
