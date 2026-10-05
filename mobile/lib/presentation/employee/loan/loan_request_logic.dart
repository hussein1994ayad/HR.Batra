// حاسبة طلب السلفة بدون واجهة: عدد الأشهر، آخر قسط، شروط الطلب، وتنبيه الراتب.

import '../../../core/design/formatters.dart';
import '../../../core/logic/loan_rules.dart';
import '../../../core/models/models.dart';

/// عدد الأقساط (تقريب للأعلى).
int loanMonths(double amount, double installment) => installment > 0 ? (amount / installment).ceil() : 0;

/// آخر قسط قد يكون أقل من القسط الشهري.
double loanLastInstallment(double amount, double installment) {
  final months = loanMonths(amount, installment);
  if (months <= 0) return 0;
  final rest = amount - installment * (months - 1);
  return rest <= 0 ? installment : rest;
}

/// شروط إرسال الطلب — يرجع رسالة الخطأ أو null.
String? loanRequestError({required double amount, required double installment, required List<LoanModel> history}) {
  if (amount <= 0) return 'اكتب مبلغ السلفة';
  if (installment <= 0) return 'اكتب القسط الشهري';
  if (installment > amount) return 'القسط أكبر من مبلغ السلفة';
  // نفس شروط الاعتماد: نخبر الموظف قبل ما يرسل طلب ما ينعتمد
  final hasActive = history.any((l) => l.isActive);
  if (hasActive) return 'عندك سلفة جارية لم تُسدَّد بعد. تگدر تطلب سلفة جديدة بعد إكمال سدادها.';
  if (amount > 100000000) return 'المبلغ كبير جداً (أكثر من 100,000,000 د.ع). تأكد من الرقم.';
  return null;
}

/// تنبيه فقط (الطلب مسموح): القسط أكثر من نص الراتب، أو أكثر من الراتب كله فيطلع الراتب بالسالب.
String? loanSalaryWarning({required double? salary, required double installment}) {
  final s = salary ?? 0;
  if (s <= 0 || installment <= s * kLoanSalaryWarningRatio) return null;
  if (installment > s) {
    return '⚠️ القسط الشهري (${Fmt.iqd(installment)}) أكثر من راتبك كله (${Fmt.iqd(s)}). راتبك راح يطلع بالسالب، والفرق تدفعه نقداً للإدارة.';
  }
  return '⚠️ القسط الشهري أكثر من نص راتبك (${Fmt.iqd(s * kLoanSalaryWarningRatio)}). راح يبقى لك من الراتب ${Fmt.iqd(s - installment)} بس.';
}
