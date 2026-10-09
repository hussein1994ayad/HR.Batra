// =========================================================================
// HR Pro — تنسيق موحّد للمال والتواريخ والأوقات بالعربي (العراق)
// =========================================================================
// المال: "1,500,000 د.ع" — التاريخ: "الخميس 26/9" — الشهر: "الشهر التاسع 2026" — الوقت: "8:05 ص"
// الوقت النسبي: "قبل 5 دقائق". الأرقام لاتينية (0-9) كما هو شائع بالعراق.
// =========================================================================

import '../utils/arabic_format.dart';

abstract final class Fmt {
  /// ترتيب الأشهر: نكتب «الشهر العاشر» بدل «تشرين الأول» (نفس الموقع).
  static const List<String> monthOrdinals = [
    'الأول', 'الثاني', 'الثالث', 'الرابع', 'الخامس', 'السادس',
    'السابع', 'الثامن', 'التاسع', 'العاشر', 'الحادي عشر', 'الثاني عشر',
  ];

  /// DateTime.weekday: 1 = الاثنين ... 7 = الأحد
  static const List<String> weekdays = ['الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];

  /// مبلغ بالدينار: 1500000 → "1,500,000 د.ع"
  static String iqd(num? value, {bool withUnit = true}) {
    final v = value ?? 0;
    final s = (v < 0 ? '-' : '') + formatThousands(v.abs());
    return withUnit ? '$s د.ع' : s;
  }

  /// "8:05 ص" / "4:30 م"
  static String time(DateTime? t) {
    if (t == null) return '--:--';
    final l = t.toLocal();
    final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
    return '$h:${l.minute.toString().padLeft(2, '0')} ${l.hour >= 12 ? 'م' : 'ص'}';
  }

  /// نص وقت من القاعدة "08:00:00" → "8:00 ص"
  static String timeOfDay(String? hhmmss) {
    if (hhmmss == null || !hhmmss.contains(':')) return '--:--';
    final p = hhmmss.split(':');
    final h = int.tryParse(p[0]) ?? 0;
    final m = int.tryParse(p[1]) ?? 0;
    return time(DateTime(2000, 1, 1, h, m));
  }

  /// "26/9" أو "26/9/2026" إذا ليست السنة الحالية (بالأرقام، بدون أسماء الأشهر)
  static String date(DateTime? d, {bool withYear = false}) {
    if (d == null) return '—';
    final l = d.toLocal();
    final y = withYear || l.year != DateTime.now().year ? '/${l.year}' : '';
    return '${l.day}/${l.month}$y';
  }

  /// "الخميس 26/9"
  static String dateWithDay(DateTime? d) => d == null ? '—' : '${weekdays[d.toLocal().weekday - 1]} ${date(d)}';

  /// مدة بالدقائق: "45 د" / "2 س" / "2 س 45 د"
  static String minutesLabel(int m) {
    final h = m ~/ 60;
    final r = m % 60;
    if (h == 0) return '$r د';
    return r == 0 ? '$h س' : '$h س $r د';
  }

  /// "الشهر الخامس 2026" — ترتيب الشهر (كما يُكتب بكشوف الرواتب والسلف والإشعارات)
  static String monthNumber(int month, int year) =>
      'الشهر ${month >= 1 && month <= 12 ? monthOrdinals[month - 1] : month} $year';

  /// "الشهر الحادي عشر 2026" لتاريخ
  static String monthOf(DateTime? d) => d == null ? '—' : monthNumber(d.month, d.year);

  /// "قبل 5 دقائق"، "قبل ساعتين"، "أمس"، أو التاريخ.
  static String relative(DateTime? t, {DateTime? now}) {
    if (t == null) return '';
    final n = now ?? DateTime.now();
    final diff = n.difference(t.toLocal());
    if (diff.isNegative || diff.inSeconds < 60) return 'الآن';
    if (diff.inMinutes < 60) return 'قبل ${_count(diff.inMinutes, 'دقيقة', 'دقيقتين', 'دقائق')}';
    if (diff.inHours < 24) return 'قبل ${_count(diff.inHours, 'ساعة', 'ساعتين', 'ساعات')}';
    if (diff.inDays == 1) return 'أمس';
    if (diff.inDays < 7) return 'قبل ${_count(diff.inDays, 'يوم', 'يومين', 'أيام')}';
    return date(t);
  }

  /// "شهر واحد" / "شهرين" / "3 أشهر" / "12 شهر"
  static String monthCount(int n) => n == 1 ? 'شهر واحد' : _count(n, 'شهر', 'شهرين', 'أشهر');

  /// "يوم واحد" / "يومين" / "3 أيام" / "11 يوم"
  static String days(int n) => n == 1 ? 'يوم واحد' : _count(n, 'يوم', 'يومين', 'أيام');

  static String _count(int n, String one, String two, String few) {
    if (n == 1) return one;
    if (n == 2) return two;
    if (n >= 3 && n <= 10) return '$n $few';
    return '$n $one';
  }

  /// تحية حسب الوقت.
  static String greeting([DateTime? now]) {
    final h = (now ?? DateTime.now()).hour;
    if (h >= 5 && h < 12) return 'صباح الخير';
    if (h >= 12 && h < 17) return 'نهارك سعيد';
    return 'مساء الخير';
  }
}
