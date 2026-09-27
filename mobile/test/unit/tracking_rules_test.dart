import 'package:flutter_test/flutter_test.dart';
import 'package:hr_pro/core/logic/tracking_rules.dart';
import 'package:latlong2/latlong.dart';

void main() {
  const branch = {'id': 'b1', 'name': 'المنصور', 'latitude': 33.3152, 'longitude': 44.3661, 'radius_meters': 150};
  Map<String, dynamic> emp(String id) => {'id': id, 'full_name': 'موظف $id', 'branch_id': 'b1', 'branches': branch};
  String t(int h, int m) => DateTime(2026, 9, 26, h, m).toUtc().toIso8601String();

  test('status per employee: inside, outside, checked out, absent', () {
    final result = buildTracking(
      employees: [emp('a'), emp('b'), emp('c'), emp('d')],
      attendance: [
        {'employee_id': 'a', 'check_in_time': t(8, 0), 'check_in_lat': 33.3152, 'check_in_lng': 44.3661},
        {'employee_id': 'b', 'check_in_time': t(8, 5), 'check_in_lat': 33.3152, 'check_in_lng': 44.3661},
        {'employee_id': 'c', 'check_in_time': t(8, 0), 'check_out_time': t(16, 0), 'check_in_lat': 33.3152, 'check_in_lng': 44.3661},
      ],
      trackingPoints: [
        // b خرج بعيداً (~2 كم)
        {'employee_id': 'b', 'latitude': 33.33, 'longitude': 44.38, 'timestamp': t(10, 0), 'battery_level': 55, 'is_moving': true},
      ],
    );
    final byId = {for (final e in result) e.id: e};
    expect(byId['a']!.status, TrackStatus.inside);
    expect(byId['b']!.status, TrackStatus.outside);
    expect(byId['b']!.batteryLevel, 55);
    expect(byId['b']!.isMoving, isTrue);
    expect(byId['b']!.distanceToBranch, greaterThan(1500));
    expect(byId['c']!.status, TrackStatus.checkedOut);
    expect(byId['d']!.status, TrackStatus.absent);
    expect(byId['d']!.position, isNull);
  });

  test('trail joins check-in, tracking points and check-out without repeats', () {
    final result = buildTracking(
      employees: [emp('a')],
      attendance: [
        {
          'employee_id': 'a',
          'check_in_time': t(8, 0),
          'check_out_time': t(16, 0),
          'check_in_lat': 33.3152,
          'check_in_lng': 44.3661,
          'check_out_lat': 33.3200,
          'check_out_lng': 44.3700,
        },
      ],
      trackingPoints: [
        {'employee_id': 'a', 'latitude': 33.3152, 'longitude': 44.3661, 'timestamp': t(9, 0)},
        {'employee_id': 'a', 'latitude': 33.3180, 'longitude': 44.3680, 'timestamp': t(12, 0)},
      ],
    );
    final a = result.single;
    expect(a.trail, const [LatLng(33.3152, 44.3661), LatLng(33.3180, 44.3680), LatLng(33.3200, 44.3700)]);
    expect(a.totalDistanceKm, closeTo(0.66, 0.1));
    expect(a.position, const LatLng(33.3180, 44.3680), reason: 'last tracking point wins over check-out point');
  });

  test('integer coordinates do not crash', () {
    final result = buildTracking(
      employees: [
        {'id': 'x', 'full_name': 'س', 'branches': {'latitude': 33, 'longitude': 44, 'radius_meters': 100}},
      ],
      attendance: [
        {'employee_id': 'x', 'check_in_time': t(8, 0), 'check_in_lat': 33, 'check_in_lng': 44},
      ],
      trackingPoints: const [],
    );
    expect(result.single.status, TrackStatus.inside);
  });

  test('formatDistance', () {
    expect(formatDistance(350.4), '350 م');
    expect(formatDistance(1450), '1.4 كم');
  });
}
