// "اليوم" بتوقيت الشركة (بغداد) — نفس company_timezone() بالسيرفر.
//
// ليش؟ السيرفر يحدد يوم الدوام (work_date) بتوقيت بغداد. لو اعتمدنا ساعة الموبايل، جهاز توقيته غلط (أو مسافر)
// يجيب سجل يوم غلط ويعرض حالة الدوام غلط. العراق ما يستعمل التوقيت الصيفي منذ 2008، فالفرق ثابت +3.
// على جهاز توقيته بغداد (الحالة الطبيعية) النتيجة نفس ساعة الموبايل بالضبط.

/// فرق توقيت الشركة عن UTC (Asia/Baghdad).
const Duration kCompanyUtcOffset = Duration(hours: 3);

/// التاريخ YYYY-MM-DD بتوقيت الشركة للحظة [at] (الآن إذا ما انطت).
String companyDateStr([DateTime? at]) {
  final t = (at ?? DateTime.now()).toUtc().add(kCompanyUtcOffset);
  return '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
}
