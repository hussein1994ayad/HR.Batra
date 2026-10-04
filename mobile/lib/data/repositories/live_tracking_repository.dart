// =========================================================================
// التتبع الحي للإدارة: الفروع، الموظفون النشطون مع فروعهم، بصمات اليوم ونقاط اليوم،
// والاشتراك الفوري بأي حركة أو بصمة.
// =========================================================================

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/services/supabase_service.dart';

class LiveTrackingRepository {
  LiveTrackingRepository({SupabaseClient? client}) : _db = client ?? SupabaseService.client;
  final SupabaseClient _db;

  Future<List<Map<String, dynamic>>> fetchBranches() async {
    return List<Map<String, dynamic>>.from(await _db.from('branches').select().order('name'));
  }

  Future<List<Map<String, dynamic>>> fetchActiveEmployees() async {
    return List<Map<String, dynamic>>.from(await _db
        .from('employees')
        .select('id, full_name, avatar_url, role, branch_id, branches(id, name, latitude, longitude, radius_meters)')
        .eq('is_active', true)
        .order('full_name'));
  }

  /// [بصمات اليوم، نقاط اليوم] بالتوازي.
  Future<List<dynamic>> fetchDay({required String date, required String start, required String end}) {
    return Future.wait<dynamic>([
      _db.from('attendance').select().eq('work_date', date),
      fetchDayLocations(start, end),
    ]);
  }

  /// نقاط اليوم لكل الموظفين تتجاوز حد الـ 1000 صف للطلب الواحد، فتُجلب على صفحات
  /// حتى لا ينقطع مسار الحركة على الخريطة بصمت.
  Future<List<Map<String, dynamic>>> fetchDayLocations(String start, String end) async {
    const pageSize = 1000;
    final rows = <Map<String, dynamic>>[];
    for (var from = 0;; from += pageSize) {
      final page = await _db
          .from('location_tracking')
          .select()
          .gte('timestamp', start)
          .lte('timestamp', end)
          .order('timestamp', ascending: true)
          .order('id', ascending: true)
          .range(from, from + pageSize - 1);
      rows.addAll(page);
      if (page.length < pageSize) return rows;
    }
  }

  /// تحديث لحظي عند أي حركة (location_tracking) أو بصمة (attendance).
  RealtimeChannel subscribe(void Function() onChange) {
    return _db.channel('live-admin-tracking')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'location_tracking',
        callback: (_) => onChange(),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'attendance',
        callback: (_) => onChange(),
      )
      ..subscribe();
  }

  Future<String> removeChannel(RealtimeChannel channel) => _db.removeChannel(channel);
}
