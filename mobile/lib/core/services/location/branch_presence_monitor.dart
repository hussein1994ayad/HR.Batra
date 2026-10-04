// دخول وخروج الفروع (دائرة كل فرع: الموقع + نصف القطر): كل انتقال يصير إشعار حضور للموظف.
// يعمل أوفلاين — الحدث ينحفظ ويُرفع لاحقاً بعنوان "(مؤرشف)".

import 'package:geolocator/geolocator.dart';

import '../../utils/app_log.dart';
import '../supabase_service.dart';
import 'offline_json_queue.dart';

class BranchPresenceMonitor {
  BranchPresenceMonitor._();

  static List<Map<String, dynamic>>? _cachedBranches;
  static DateTime? _lastBranchesFetchTime;
  static final Map<String, bool> _lastBranchInsideStates = {};

  static final OfflineJsonQueue _queue = OfflineJsonQueue('branch_events_offline.json');

  /// يفحص إذا الموظف دخل أو غادر أي فرع، وينشئ إشعار مناسب.
  /// يعمل أوفلاين — يخزن الأحداث ويزامنها لاحقاً.
  static Future<void> check(String employeeId, Position position) async {
    try {
      final now = DateTime.now();

      // تحديث cache الفروع كل 15 دقيقة
      if (_cachedBranches == null ||
          _lastBranchesFetchTime == null ||
          now.difference(_lastBranchesFetchTime!) > const Duration(minutes: 15)) {
        try {
          final data = await SupabaseService.client
              .from('branches')
              .select('id, name, latitude, longitude, radius_meters')
              .timeout(const Duration(seconds: 8));
          _cachedBranches = List<Map<String, dynamic>>.from(data);
          _lastBranchesFetchTime = now;
        } catch (_) {
          // نستخدم الـ cache القديم لو الشبكة غير متاحة
        }
      }

      if (_cachedBranches == null || _cachedBranches!.isEmpty) return;

      for (final branch in _cachedBranches!) {
        final id = branch['id']?.toString();
        if (id == null) continue;
        final name = branch['name']?.toString() ?? 'فرع';
        final bLat = (branch['latitude'] as num?)?.toDouble() ?? 0;
        final bLng = (branch['longitude'] as num?)?.toDouble() ?? 0;
        final radius = (branch['radius_meters'] as num?)?.toDouble() ?? 100;

        final distance = Geolocator.distanceBetween(
          position.latitude, position.longitude, bLat, bLng,
        );
        final isInside = distance <= radius;
        final wasInside = _lastBranchInsideStates[id];

        if (wasInside != null && wasInside != isInside) {
          final event = {
            'employee_id': employeeId,
            'branch_id': id,
            'branch_name': name,
            'event_type': isInside ? 'enter' : 'exit',
            'latitude': position.latitude,
            'longitude': position.longitude,
            'timestamp': DateTime.now().toUtc().toIso8601String(),
          };
          await _recordOrCacheEvent(event);
        }
        _lastBranchInsideStates[id] = isInside;
      }
    } catch (e) {
      appLog('⚠️ فشل فحص دخول/خروج الفروع: $e');
    }
  }

  /// يحاول تسجيل حدث الدخول/الخروج مباشرة، ولو فشل يخزنه للمزامنة لاحقاً.
  static Future<void> _recordOrCacheEvent(Map<String, dynamic> event) async {
    try {
      // نسجّله في notifications (يظهر للموظف وللأدمن بحسب حاجتك)
      await SupabaseService.client.from('notifications').insert({
        'employee_id': event['employee_id'],
        'title': event['event_type'] == 'enter'
            ? 'دخول فرع ${event['branch_name']}'
            : 'خروج من فرع ${event['branch_name']}',
        'body': 'تم رصد ${event['event_type'] == 'enter' ? 'دخولك إلى' : 'خروجك من'} فرع '
            '${event['branch_name']} في ${event['timestamp']}',
        'type': 'attendance',
      }).timeout(const Duration(seconds: 8));
      appLog('📍 branch event uploaded: ${event['event_type']} ${event['branch_name']}');
    } catch (_) {
      // فشل الرفع → نضيفه للـ cache للمزامنة لاحقاً
      try {
        final pending = await _queue.append(event);
        appLog('💾 branch event cached offline ($pending pending).');
      } catch (e) {
        appLog('⚠️ فشل حفظ حدث الفرع محلياً: $e');
      }
    }
  }

  /// مزامنة الأحداث المخزنة أوفلاين
  static Future<void> syncOffline() async {
    try {
      final list = await _queue.readAll();
      if (list.isEmpty) return;

      final remaining = <Map<String, dynamic>>[];
      for (final raw in list) {
        if (raw is! Map) continue;
        final ev = Map<String, dynamic>.from(raw);
        try {
          await SupabaseService.client.from('notifications').insert({
            'employee_id': ev['employee_id'],
            'title': ev['event_type'] == 'enter'
                ? 'دخول فرع ${ev['branch_name']} (مؤرشف)'
                : 'خروج من فرع ${ev['branch_name']} (مؤرشف)',
            'body': 'تم رصد ${ev['event_type'] == 'enter' ? 'دخولك إلى' : 'خروجك من'} فرع '
                '${ev['branch_name']} في ${ev['timestamp']}',
            'type': 'attendance',
          });
        } catch (_) {
          remaining.add(ev);
        }
      }
      await _queue.replace(remaining);
      appLog('✅ branch-events sync: ${list.length - remaining.length} uploaded, ${remaining.length} pending.');
    } catch (e) {
      appLog('⚠️ branch-events sync failed: $e');
    }
  }
}
