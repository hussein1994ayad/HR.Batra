// رفع نقاط التتبع إلى location_tracking: مباشرة إذا الإنترنت متوفر، وإلا طابور محلي
// (offline_locations.json) يُرفع بحزم 50 نقطة مع إزالة المكرر (نفس الموظف ونفس الوقت).

import '../../utils/app_log.dart';
import '../supabase_service.dart';
import 'branch_presence_monitor.dart';
import 'geofence_monitor.dart';
import 'offline_json_queue.dart';

class LocationUploader {
  LocationUploader._();

  static final OfflineJsonQueue _queue = OfflineJsonQueue('offline_locations.json');

  /// تخزين الإحداثي محلياً عند فشل الاتصال بالإنترنت
  static Future<void> cacheOffline(Map<String, dynamic> locationData) async {
    try {
      final total = await _queue.append(locationData);
      appLog('📍 تم تخزين نقطة الموقع محلياً (أوفلاين). الإجمالي المخزن: $total');
    } catch (e) {
      appLog('❌ فشل في تخزين الموقع محلياً: $e');
    }
  }

  /// محاولة مزامنة المواقع المخزنة محلياً ورفعها بحزم (batch) عند توفر الاتصال.
  /// إذا فشلت حزمة، تبقى في المخزن للمحاولة لاحقاً — بدون تكرار في السيرفر.
  /// بعدها تُزامَن أحداث الفروع والسياج المخزّنة أيضاً.
  static Future<void> syncOffline() async {
    try {
      final cachedList = await _queue.readAll();
      if (cachedList.isEmpty) return;

      // إزالة التكرارات (بنفس timestamp + employee_id) قبل الرفع
      final seen = <String>{};
      final dedup = <Map<String, dynamic>>[];
      for (final raw in cachedList) {
        if (raw is! Map) continue;
        final key = '${raw["employee_id"]}|${raw["timestamp"]}';
        if (seen.add(key)) {
          dedup.add(Map<String, dynamic>.from(raw));
        }
      }

      const int batchSize = 50;
      final List<Map<String, dynamic>> remaining = [];
      int uploaded = 0;

      for (int i = 0; i < dedup.length; i += batchSize) {
        final end = (i + batchSize).clamp(0, dedup.length);
        final batch = dedup.sublist(i, end);
        try {
          await SupabaseService.client.from('location_tracking').insert(batch);
          uploaded += batch.length;
        } catch (e) {
          appLog('⚠️ فشل رفع دفعة $i-$end: $e — سنعيد المحاولة لاحقاً.');
          remaining.addAll(batch);
        }
      }

      // احتفظ بالحزم اللي فشلت للمحاولة القادمة
      await _queue.replace(remaining);
      appLog('✅ رُفعت $uploaded نقطة، بقيت ${remaining.length} للمحاولة القادمة.');

      // مزامنة أحداث الدخول/الخروج للفروع (إن وجدت)
      await BranchPresenceMonitor.syncOffline();

      // مزامنة أحداث دخول/خروج السياج الجغرافي (إن وجدت)
      await GeofenceMonitor.syncOffline();
    } catch (e) {
      appLog('⚠️ لم تكتمل مزامنة النقاط المحلية (الشبكة غير متاحة): $e');
    }
  }
}
