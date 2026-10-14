// =========================================================================
// وقت البصمة بدون إنترنت (تدقيق 14/10/2026، BUG-001)
// =========================================================================
// ساعة الموبايل ممكن تتغيّر (وضع الطيران + تغيير الساعة كان يخفي التأخير). فالتطبيق يحفظ آخر وقت سيرفر
// ويا «عدّاد الموبايل منذ التشغيل» (يكمل والشاشة مطفية، وما يتأثر بتغيير الساعة)، ووقت البصمة الحقيقي =
// وقت السيرفر + اللي عدّه العدّاد من وقتها. إذا الموبايل انطفى وشغل (العدّاد يرجع صفر) أو ماكو وقت سيرفر محفوظ،
// الوقت ما ينعرف بثقة: السيرفر يسجّل ساعة الموبايل ويعلّم البصمة «تحتاج مراجعة».
// =========================================================================

/// لقطة من عدّاد الموبايل منذ التشغيل، و«رقم التشغيل» (أندرويد: عدد مرات التشغيل، آيفون: وقت التشغيل).
class ClockSnapshot {
  const ClockSnapshot({required this.elapsedMs, required this.bootId});

  final int elapsedMs;
  final String bootId;
}

/// آخر وقت سيرفر محفوظ مع لقطة العدّاد لحظتها.
class ClockAnchor {
  const ClockAnchor({required this.serverTime, required this.elapsedMs, required this.bootId});

  final DateTime serverTime;
  final int elapsedMs;
  final String bootId;

  Map<String, dynamic> toJson() => {'server_time': serverTime.toUtc().toIso8601String(), 'elapsed_ms': elapsedMs, 'boot_id': bootId};

  static ClockAnchor? fromJson(Map<String, dynamic> m) {
    final t = DateTime.tryParse('${m['server_time']}');
    final e = m['elapsed_ms'];
    final b = m['boot_id'];
    if (t == null || e is! int || b is! String) return null;
    return ClockAnchor(serverTime: t, elapsedMs: e, bootId: b);
  }
}

/// الوقت اللي ينرسل ويا البصمة المحفوظة: [trustedTime] محسوب (أو null)، و[check] للسيرفر.
class OfflinePunchTime {
  const OfflinePunchTime.anchored(DateTime this.trustedTime) : check = 'anchored';
  const OfflinePunchTime.unknown()
      : trustedTime = null,
        check = 'no_anchor';

  final DateTime? trustedTime;

  /// 'anchored' = وقت مؤكد، 'no_anchor' = ساعة الموبايل (تحتاج مراجعة)
  final String check;
}

/// أقصى عمر لوقت السيرفر المحفوظ (بعده نعتبره قديم).
const Duration kClockAnchorMaxAge = Duration(days: 7);

/// نفس التشغيل؟ أندرويد: الرقم نفسه. آيفون: وقت التشغيل يتحرك ثواني مع ضبط الساعة التلقائي، فنسمح بدقيقتين.
bool sameBoot(String a, String b) {
  if (a.startsWith('time:') && b.startsWith('time:')) {
    final x = int.tryParse(a.substring(5));
    final y = int.tryParse(b.substring(5));
    return x != null && y != null && x > 0 && y > 0 && (x - y).abs() <= 120;
  }
  return a == b && !a.endsWith(':-1');
}

/// وقت البصمة الحقيقي من آخر وقت سيرفر والعدّاد هسه، أو «غير معروف».
OfflinePunchTime computeOfflinePunchTime(ClockAnchor? anchor, ClockSnapshot? now) {
  if (anchor == null || now == null) return const OfflinePunchTime.unknown();
  final passed = now.elapsedMs - anchor.elapsedMs;
  if (!sameBoot(anchor.bootId, now.bootId) || passed < 0 || passed > kClockAnchorMaxAge.inMilliseconds) {
    return const OfflinePunchTime.unknown();
  }
  return OfflinePunchTime.anchored(anchor.serverTime.toUtc().add(Duration(milliseconds: passed)));
}
