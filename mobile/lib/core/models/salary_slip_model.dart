// =========================================================================
// كشف الراتب — الجدول: public.salary_slips — وتفاصيله ومسير الشهر الحالي (get_my_payroll_preview)
// =========================================================================

import '../utils/json_map.dart';

class SalarySlipModel {
  final String id;

  /// 'YYYY-MM' (إلزامي بالقاعدة)؛ null فقط إذا الصف ناقص.
  final String? workMonth;
  final double basicSalary;
  final double allowances;
  final double deductions;
  final double loansDeduction;
  final double netSalary;

  /// كشوف محرّك الرواتب: تفاصيلها محفوظة سطراً سطراً في salary_slip_lines.
  final bool computedByEngine;
  final DateTime? createdAt;

  const SalarySlipModel({
    required this.id,
    required this.workMonth,
    required this.basicSalary,
    required this.allowances,
    required this.deductions,
    required this.loansDeduction,
    required this.netSalary,
    this.computedByEngine = false,
    this.createdAt,
  });

  factory SalarySlipModel.fromMap(JsonRow map) => SalarySlipModel(
        id: map.str('id') ?? '',
        workMonth: map.str('work_month'),
        basicSalary: map.dbl('basic_salary') ?? 0,
        allowances: map.dbl('allowances') ?? 0,
        deductions: map.dbl('deductions') ?? 0,
        loansDeduction: map.dbl('loans_deduction') ?? 0,
        netSalary: map.dbl('net_salary') ?? 0,
        computedByEngine: map.boolean('computed_by_engine') ?? false,
        createdAt: map.date('created_at'),
      );
}

/// بند مكافأة أو خصم بتفاصيل الكشف (من bonuses_deductions أو من أسطر المحرّك).
class PayslipDetail {
  final String? reason;
  final double? amount;

  /// التاريخ كما هو من القاعدة ('YYYY-MM-DD')، يُطبع بالـ PDF كنص.
  final String? issueDate;

  /// 'bonus' | 'deduction'
  final String? type;

  const PayslipDetail({this.reason, this.amount, this.issueDate, this.type});

  factory PayslipDetail.fromMap(JsonRow map) => PayslipDetail(
        reason: map.str('reason'),
        amount: map.dbl('amount'),
        issueDate: map.str('issue_date'),
        type: map.str('type'),
      );

  bool get isBonus => type == 'bonus';

  /// الشكل اللي تقراه خدمة الـ PDF.
  Map<String, dynamic> toMap() => {'reason': reason, 'amount': amount, 'issue_date': issueDate, 'type': type};
}

/// حركة بمسير الشهر الحالي (غياب، تأخير، مكافأة...).
class PayrollPreviewEvent {
  final String? eventType;
  final double minutes;
  final String? eventDate;

  /// 'pending' | 'ignored' | غيرها = محتسبة
  final String? status;
  final double amount;

  /// موجب = إضافة، سالب = خصم
  final double direction;

  const PayrollPreviewEvent({this.eventType, this.minutes = 0, this.eventDate, this.status, this.amount = 0, this.direction = 0});

  factory PayrollPreviewEvent.fromMap(JsonRow map) => PayrollPreviewEvent(
        eventType: map.str('event_type'),
        minutes: map.dbl('minutes') ?? 0,
        eventDate: map.str('event_date'),
        status: map.str('status'),
        amount: map.dbl('amount') ?? 0,
        direction: map.dbl('direction') ?? 0,
      );
}

/// مسير الشهر الحالي قبل الاعتماد (get_my_payroll_preview).
class PayrollPreview {
  /// 'YYYY-MM' أو ''.
  final String periodMonth;
  final double basic;
  final double earnings;
  final double deductions;
  final double loans;
  final double net;

  /// صدر الكشف واعتُمد.
  final bool issued;
  final List<PayrollPreviewEvent> events;

  const PayrollPreview({
    required this.periodMonth,
    this.basic = 0,
    this.earnings = 0,
    this.deductions = 0,
    this.loans = 0,
    this.net = 0,
    this.issued = false,
    this.events = const [],
  });

  factory PayrollPreview.fromMap(JsonRow map) {
    final s = map.obj('summary') ?? const <String, dynamic>{};
    return PayrollPreview(
      periodMonth: map.obj('period')?.str('period_month') ?? '',
      basic: s.dbl('basic') ?? 0,
      earnings: s.dbl('earnings') ?? 0,
      deductions: s.dbl('deductions') ?? 0,
      loans: s.dbl('loans') ?? 0,
      net: s.dbl('net') ?? 0,
      issued: s['slip'] != null,
      events: map.list('events').map(PayrollPreviewEvent.fromMap).toList(),
    );
  }
}
