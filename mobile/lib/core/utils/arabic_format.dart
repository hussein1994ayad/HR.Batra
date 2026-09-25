// =========================================================================
// تنسيقات عربية مشتركة (نفس formatLateDurationArabic في الويب)
// =========================================================================

/// مدة بالدقائق كنص عربي: "ساعتين و 5 دقائق".
String formatDurationArabic(int minutes) {
  if (minutes <= 0) return '0 دقيقة';
  final hrs = minutes ~/ 60;
  final mins = minutes % 60;

  String hrsStr = '';
  if (hrs == 1) {
    hrsStr = 'ساعة';
  } else if (hrs == 2) {
    hrsStr = 'ساعتين';
  } else if (hrs >= 3 && hrs <= 10) {
    hrsStr = '$hrs ساعات';
  } else if (hrs > 10) {
    hrsStr = '$hrs ساعة';
  }

  String minsStr = '';
  if (mins == 1) {
    minsStr = 'دقيقة واحدة';
  } else if (mins == 2) {
    minsStr = 'دقيقتين';
  } else if (mins >= 3 && mins <= 10) {
    minsStr = '$mins دقائق';
  } else if (mins > 10) {
    minsStr = '$mins دقيقة';
  }

  if (hrsStr.isNotEmpty && minsStr.isNotEmpty) return '$hrsStr و $minsStr';
  return hrsStr.isNotEmpty ? hrsStr : minsStr;
}

/// وقت بنظام 12 ساعة: "9:05 AM"، أو "--:--".
String formatTime12h(DateTime? time) {
  if (time == null) return '--:--';
  final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
  return '$hour:${time.minute.toString().padLeft(2, '0')} ${time.hour >= 12 ? 'PM' : 'AM'}';
}

/// تاريخ مختصر: "2026/9/25".
String formatDateSlash(DateTime date) => '${date.year}/${date.month}/${date.day}';

/// YYYY-MM-DD لتاريخ محلي (عمود work_date).
String isoDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

/// رقم بفواصل آلاف نقطية: 1500000 → "1.500.000".
String formatThousands(num value) =>
    value.round().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');

/// عكس [formatThousands]: يحذف النقاط والفواصل.
double parseThousands(String text) => double.tryParse(text.replaceAll('.', '').replaceAll(',', '').trim()) ?? 0;
