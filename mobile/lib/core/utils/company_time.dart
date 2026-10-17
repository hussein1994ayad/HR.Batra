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

// ---------------------------------------------------------------------
// داخل التطبيق «الوقت المحلي» = ساعة بغداد (تدقيق 14/10، المرحلة 9): موبايل مضبوط على توقيت ثاني (مسافر أو غلط)
// كان يعرض الأوقات بساعته ويحسب «اليوم» بتاريخه. على موبايل بتوقيت العراق (الطبيعي) النتيجة نفسها بالضبط.
//   • وقت من السيرفر: [parseServerTime] (أو [toCompanyTime] للحظة UTC).
//   • «الآن» لليوم والساعة: [companyNow]. (مدة بين لحظتين حقيقيتين تبقى بـ DateTime.now)
//   • وقت ساعة بغداد ← السيرفر: [companyWallToUtc].
// ---------------------------------------------------------------------

/// اللحظة [t] بساعة بغداد: DateTime بأرقام بغداد (سنة/شهر/يوم/ساعة/دقيقة) مهما كان توقيت الموبايل.
DateTime toCompanyTime(DateTime t) {
  final u = t.toUtc().add(kCompanyUtcOffset);
  return DateTime(u.year, u.month, u.day, u.hour, u.minute, u.second, u.millisecond, u.microsecond);
}

/// «الآن» بساعة بغداد.
DateTime companyNow() => toCompanyTime(DateTime.now());

/// وقت بساعة بغداد (من [companyNow] أو تاريخ/ساعة اختارها المستخدم) ← لحظة UTC للسيرفر.
DateTime companyWallToUtc(DateTime wall) =>
    DateTime.utc(wall.year, wall.month, wall.day, wall.hour, wall.minute, wall.second, wall.millisecond, wall.microsecond)
        .subtract(kCompanyUtcOffset);

/// قراءة وقت من السيرفر: تاريخ بس («2026-10-15») يبقى نفس اليوم، ووقت بمنطقة زمنية يصير ساعة بغداد.
DateTime? parseServerTime(Object? v) {
  final s = v?.toString().trim() ?? '';
  if (s.isEmpty) return null;
  final t = DateTime.tryParse(s);
  if (t == null) return null;
  return t.isUtc ? toCompanyTime(t) : t;
}
