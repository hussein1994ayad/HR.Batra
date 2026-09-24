// =========================================================================
// HR Pro v6.0 — أدوات التاريخ والوقت (Date & Time Utilities)
// =========================================================================
// هذا الملف يحتوي على دوال مساعدة للتعامل مع التواريخ والأوقات.
// استخدمه في أي شاشة تحتاج عرض أو معالجة تاريخ/وقت.
//
// مثال الاستخدام:
//   import '../../core/utils/date_utils.dart';
//   Text(HrDateUtils.formatTime(attendance.checkInTime))
// =========================================================================

/// مجموعة دوال ثابتة للتعامل مع التواريخ والأوقات بالعربية.
class HrDateUtils {
  HrDateUtils._(); // منع الإنشاء - استخدم الدوال مباشرة

  // ─── تنسيق الوقت ──────────────────────────────────────────────────────

  /// يحوّل DateTime إلى نص بصيغة 12 ساعة (مثال: "9:30 ص")
  /// [dt] : كائن DateTime (يفضّل أن يكون بالتوقيت المحلي)
  static String formatTime(DateTime? dt) {
    if (dt == null) return '--:--';
    final local = dt.toLocal();
    final hour12 = local.hour > 12
        ? local.hour - 12
        : (local.hour == 0 ? 12 : local.hour);
    final amPm  = local.hour >= 12 ? 'م' : 'ص';
    final min   = local.minute.toString().padLeft(2, '0');
    return '$hour12:$min $amPm';
  }

  /// يحوّل نص وقت بصيغة "HH:MM:SS" إلى "H:MM ص/م"
  static String formatTimeString(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return '--:--';
    try {
      final parts = timeStr.split(':');
      int hour = int.parse(parts[0]);
      final min = parts[1];
      final amPm = hour >= 12 ? 'م' : 'ص';
      if (hour > 12) hour -= 12;
      if (hour == 0) hour = 12;
      return '$hour:$min $amPm';
    } catch (_) {
      return timeStr.length > 5 ? timeStr.substring(0, 5) : timeStr;
    }
  }

  // ─── تنسيق التاريخ ────────────────────────────────────────────────────

  /// يحوّل DateTime إلى تاريخ عربي كامل (مثال: "الخميس، 24 سبتمبر 2026")
  static String formatDateFull(DateTime date) {
    return '${_weekdayAr(date.weekday)}، ${date.day} ${_monthAr(date.month)} ${date.year}';
  }

  /// يحوّل DateTime إلى تاريخ مختصر (مثال: "24/09/2026")
  static String formatDateShort(DateTime date) {
    final d = date.day.toString().padLeft(2, '0');
    final m = date.month.toString().padLeft(2, '0');
    return '$d/$m/${date.year}';
  }

  /// يُرجع تاريخ اليوم بصيغة ISO (YYYY-MM-DD) — للاستعلامات
  static String todayIso() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  // ─── حساب الفترات ─────────────────────────────────────────────────────

  /// يُرجع مدة الدوام كنص (مثال: "7 ساعات 30 دقيقة")
  static String formatDuration(Duration? d) {
    if (d == null) return '--';
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h == 0) return '$m دقيقة';
    if (m == 0) return '$h ساعة';
    return '$h ساعة $m دقيقة';
  }

  /// يُرجع "منذ X دقيقة/ساعة/يوم" للإشعارات
  static String timeAgo(DateTime? dt) {
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt.toLocal());
    if (diff.inMinutes < 1)  return 'الآن';
    if (diff.inMinutes < 60) return 'منذ ${diff.inMinutes} دقيقة';
    if (diff.inHours < 24)   return 'منذ ${diff.inHours} ساعة';
    if (diff.inDays < 7)     return 'منذ ${diff.inDays} يوم';
    return formatDateShort(dt.toLocal());
  }

  // ─── مساعدات خاصة ─────────────────────────────────────────────────────

  static String _weekdayAr(int weekday) {
    const days = ['', 'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];
    return days[weekday];
  }

  static String _monthAr(int month) {
    const months = ['', 'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
                        'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];
    return months[month];
  }
}
