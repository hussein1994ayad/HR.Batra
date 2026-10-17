// السياج الجغرافي القديم (مناطق مخصّصة لكل موظف عبر employee_geofence_assignments): ماكو واجهة تعيين، والجدول فارغ،
// ففحص الدخول/الخروج انشال (تدقيق 14/10، المرحلة 9: CODE-006). يبقى:
//   • رفع أحداث مخزّنة أوفلاين من نسخ قديمة (حتى ما تضيع)،
//   • خوارزمية النقطة داخل المضلّع (أداة عامة).

import 'package:latlong2/latlong.dart';

import '../../utils/app_log.dart';
import '../supabase_service.dart';
import 'offline_json_queue.dart';

class GeofenceMonitor {
  GeofenceMonitor._();

  static final OfflineJsonQueue _queue = OfflineJsonQueue('geofence_events_offline.json');

  /// خوارزمية Ray-Casting للتحقق من وقوع إحداثي داخل مضلع جغرافي
  static bool isPointInPolygon(LatLng point, List<LatLng> polygon) {
    int i, j = polygon.length - 1;
    bool oddNodes = false;
    final double x = point.longitude;
    final double y = point.latitude;

    for (i = 0; i < polygon.length; i++) {
      final double latI = polygon[i].latitude;
      final double lngI = polygon[i].longitude;
      final double latJ = polygon[j].latitude;
      final double lngJ = polygon[j].longitude;

      if ((latI < y && latJ >= y || latJ < y && latI >= y) &&
          (lngI + (y - latI) / (latJ - latI) * (lngJ - lngI) < x)) {
        oddNodes = !oddNodes;
      }
      j = i;
    }
    return oddNodes;
  }

  /// مزامنة أحداث السياج الجغرافي المخزنة أوفلاين — بالطابع الزمني الأصلي للحدث
  static Future<void> syncOffline() async {
    try {
      final list = await _queue.readAll();
      if (list.isEmpty) return;

      final remaining = <Map<String, dynamic>>[];
      for (final raw in list) {
        if (raw is! Map) continue;
        final ev = Map<String, dynamic>.from(raw);
        try {
          // مزامنة السجل في جدول المخالفات فقط (للوحة الإدارة) — بدون إشعار للموظف
          await SupabaseService.client
              .from('geofence_violations')
              .insert({
                'employee_id': ev['employee_id'],
                'zone_id': ev['zone_id'],
                'violation_type': ev['violation_type'],
                'timestamp': ev['timestamp'],
              })
              .timeout(const Duration(seconds: 8));
        } catch (_) {
          remaining.add(ev);
        }
      }
      await _queue.replace(remaining);
      appLog('✅ مزامنة أحداث السياج: ${list.length - remaining.length} رُفعت، ${remaining.length} بالانتظار.');
    } catch (e) {
      appLog('⚠️ فشل مزامنة أحداث السياج الجغرافي: $e');
    }
  }
}
