// السياج الجغرافي (مناطق مضلّعة مخصّصة لكل موظف): يرصد الدخول/الخروج من كل منطقة ويسجّله
// بجدول geofence_violations للوحة الإدارة فقط — بدون إشعار للموظف. يعمل أوفلاين: الحدث ينحفظ
// بطابعه الزمني الأصلي ويُرفع لاحقاً حتى يظهر المسار الحقيقي.

import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../utils/app_log.dart';
import '../supabase_service.dart';
import 'offline_json_queue.dart';

class GeofenceMonitor {
  GeofenceMonitor._();

  static List<dynamic>? _cachedGeofenceZones;
  static DateTime? _lastGeofencesFetchTime;

  // الاحتفاظ بالحالة الأخيرة لكل منطقة جيوفينس لمنع تكرار تسجيل المخالفات المتتالية
  static final Map<String, bool> _lastGeofenceStates = {};

  static final OfflineJsonQueue _queue = OfflineJsonQueue('geofence_events_offline.json');

  /// تُمسح عند الانصراف (أول قراءة بعدها ما تُعتبر انتقالاً).
  static void clearStates() => _lastGeofenceStates.clear();

  /// التحقق من مناطق الجيوفينس ومطابقة الإحداثيات للموظف
  static Future<void> verify(String employeeId, Position position) async {
    try {
      final now = DateTime.now();

      // المناطق تُحدَّث كل 15 دقيقة (وتبقى القديمة إذا ماكو شبكة)
      if (_cachedGeofenceZones == null ||
          _lastGeofencesFetchTime == null ||
          now.difference(_lastGeofencesFetchTime!) > const Duration(minutes: 15)) {
        try {
          final assignments = await SupabaseService.client
              .from('employee_geofence_assignments')
              .select('zone_id, geofence_zones(*)')
              .eq('employee_id', employeeId)
              .timeout(const Duration(seconds: 8));

          _cachedGeofenceZones = assignments;
          _lastGeofencesFetchTime = now;
        } catch (e) {
          appLog('⚠️ فشل جلب السياج الجغرافي من السيرفر: $e');
        }
      }

      if (_cachedGeofenceZones == null || _cachedGeofenceZones!.isEmpty) return;

      final currentLatLng = LatLng(position.latitude, position.longitude);

      for (final assignment in _cachedGeofenceZones!) {
        final Object? zoneRaw = assignment is Map ? assignment['geofence_zones'] : null;
        if (zoneRaw == null) continue;

        Map<String, dynamic>? zone;
        if (zoneRaw is Map<String, dynamic>) {
          zone = zoneRaw;
        } else if (zoneRaw is List && zoneRaw.isNotEmpty && zoneRaw.first is Map) {
          zone = Map<String, dynamic>.from(zoneRaw.first as Map<dynamic, dynamic>);
        }

        if (zone == null) continue;

        final String? zoneId = zone['id']?.toString();
        if (zoneId == null) continue;
        final String zoneName = zone['name']?.toString() ?? 'منطقة مجهولة';

        final dynamic coordsRaw = zone['coordinates'];
        List<LatLng> polygon = [];

        try {
          List<dynamic> coordsList = [];
          if (coordsRaw is String) {
            final decoded = jsonDecode(coordsRaw);
            if (decoded is List) coordsList = decoded;
          } else if (coordsRaw is List) {
            coordsList = coordsRaw;
          }

          for (final item in coordsList) {
            if (item is Map) {
              final double lat = double.tryParse(item['lat']?.toString() ?? '0') ?? 0.0;
              final double lng = double.tryParse(item['lng']?.toString() ?? '0') ?? 0.0;
              if (lat != 0.0 && lng != 0.0) {
                polygon.add(LatLng(lat, lng));
              }
            }
          }
        } catch (e) {
          appLog('خطأ في فك تشفير إحداثيات الجيوفينس للمنطقة $zoneName: $e');
          continue;
        }

        if (polygon.isEmpty) continue;

        final bool isCurrentlyInside = isPointInPolygon(currentLatLng, polygon);
        final bool? lastState = _lastGeofenceStates[zoneId];

        if (lastState != null && lastState != isCurrentlyInside) {
          final String violationType = isCurrentlyInside ? 'entry' : 'exit';

          // نبني الحدث بطابع زمني دقيق لحظة الرصد حتى يظهر المسار الحقيقي
          // حتى لو كان الموظف أوفلاين وقت الخروج/الدخول
          final geoEvent = {
            'employee_id': employeeId,
            'zone_id': zoneId,
            'zone_name': zoneName,
            'violation_type': violationType,
            'latitude': position.latitude,
            'longitude': position.longitude,
            'timestamp': DateTime.now().toUtc().toIso8601String(),
          };

          // يسجّل مباشرة إن توفّر الإنترنت، وإلا يخزّنه محلياً للمزامنة لاحقاً.
          await _recordOrCacheEvent(geoEvent);
        }

        // لا نُحدّث الحالة إلا بعد ضمان تسجيل/تخزين الانتقال (لا يضيع أي خروج)
        _lastGeofenceStates[zoneId] = isCurrentlyInside;
      }
    } catch (e) {
      appLog('خطأ أثناء التحقق من مخالفات السياج الجغرافي: $e');
    }
  }

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

  /// يحاول تسجيل حدث السياج مباشرة، ولو تعذّر (أوفلاين) يخزّنه للمزامنة لاحقاً.
  /// يحافظ على الطابع الزمني الأصلي للحدث ليظهر المسار الحقيقي بعد رجوع الإنترنت.
  static Future<void> _recordOrCacheEvent(Map<String, dynamic> event) async {
    final String violationName = event['violation_type'] == 'entry' ? 'دخول' : 'خروج';
    final String zoneName = event['zone_name']?.toString() ?? 'منطقة';
    try {
      // نسجّل الحدث في جدول المخالفات فقط (للوحة الإدارة) — بدون أي إشعار للموظف
      await SupabaseService.client
          .from('geofence_violations')
          .insert({
            'employee_id': event['employee_id'],
            'zone_id': event['zone_id'],
            'violation_type': event['violation_type'],
            'timestamp': event['timestamp'],
          })
          .timeout(const Duration(seconds: 8));

      appLog('📍 حدث سياج جغرافي مرفوع: $violationName - $zoneName');
    } catch (_) {
      // فشل الرفع → نخزّنه محلياً للمزامنة لاحقاً بنفس طابعه الزمني
      try {
        final pending = await _queue.append(event);
        appLog('💾 حدث سياج جغرافي مخزّن أوفلاين ($pending بالانتظار).');
      } catch (e) {
        appLog('⚠️ فشل حفظ حدث السياج محلياً: $e');
      }
    }
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
