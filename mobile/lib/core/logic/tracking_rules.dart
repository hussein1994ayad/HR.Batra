// =========================================================================
// التتبع الحي — منطق نقي بدون واجهة: حالة كل موظف، موقعه الأخير، مساره،
// المسافة المقطوعة، وبعده عن الفرع. تُختبر في test/unit/tracking_rules_test.dart
// =========================================================================

import 'package:geolocator/geolocator.dart' show Geolocator;
import 'package:latlong2/latlong.dart';

enum TrackStatus { inside, outside, checkedOut, absent }

class TrackedEmployee {
  const TrackedEmployee({
    required this.employee,
    required this.status,
    required this.branchName,
    required this.trail,
    this.branchId,
    this.position,
    this.branchCenter,
    this.branchRadius = 100,
    this.distanceToBranch,
    this.checkIn,
    this.checkOut,
    this.checkInPoint,
    this.lastSeen,
    this.batteryLevel,
    this.isMoving = false,
    this.totalDistanceKm = 0,
  });

  final Map<String, dynamic> employee;
  final TrackStatus status;
  final String branchName;
  final String? branchId;
  final List<LatLng> trail;
  final LatLng? position;
  final LatLng? branchCenter;
  final double branchRadius;
  final double? distanceToBranch;
  final DateTime? checkIn;
  final DateTime? checkOut;
  final LatLng? checkInPoint;
  final DateTime? lastSeen;
  final int? batteryLevel;
  final bool isMoving;
  final double totalDistanceKm;

  String get id => employee['id'].toString();
  String get name => (employee['full_name'] ?? 'بدون اسم').toString();
  bool get hasPunchedIn => checkIn != null;
}

LatLng? _point(Object? lat, Object? lng) => lat is num && lng is num ? LatLng(lat.toDouble(), lng.toDouble()) : null;

DateTime? _time(Object? v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

double _meters(LatLng a, LatLng b) => Geolocator.distanceBetween(a.latitude, a.longitude, b.latitude, b.longitude);

/// يبني حالة كل موظف نشط من سجلات الحضور ونقاط التتبع ليوم واحد.
/// [trackingPoints] مرتبة زمنياً تصاعدياً.
List<TrackedEmployee> buildTracking({
  required List<Map<String, dynamic>> employees,
  required List<Map<String, dynamic>> attendance,
  required List<Map<String, dynamic>> trackingPoints,
}) {
  final attByEmp = {for (final a in attendance) a['employee_id'].toString(): a};
  final pointsByEmp = <String, List<Map<String, dynamic>>>{};
  for (final p in trackingPoints) {
    pointsByEmp.putIfAbsent(p['employee_id'].toString(), () => []).add(p);
  }

  return [
    for (final emp in employees)
      () {
        final id = emp['id'].toString();
        final branch = emp['branches'] is Map ? Map<String, dynamic>.from(emp['branches'] as Map) : const <String, dynamic>{};
        final branchCenter = _point(branch['latitude'], branch['longitude']);
        final radius = (branch['radius_meters'] as num?)?.toDouble() ?? 100.0;
        final att = attByEmp[id] ?? const <String, dynamic>{};
        final checkIn = _time(att['check_in_time']);
        final checkOut = checkIn == null ? null : _time(att['check_out_time']);
        final inPoint = _point(att['check_in_lat'], att['check_in_lng']);
        final outPoint = _point(att['check_out_lat'], att['check_out_lng']);
        final points = pointsByEmp[id] ?? const [];

        // المسار: نقطة البصمة ← نقاط التتبع ← نقطة الانصراف (بدون تكرار متتالٍ)
        final trail = <LatLng>[];
        void add(LatLng? p) {
          if (p != null && (trail.isEmpty || trail.last != p)) trail.add(p);
        }

        add(inPoint);
        for (final p in points) {
          add(_point(p['latitude'], p['longitude']));
        }
        add(outPoint);

        // الموقع الأخير: آخر نقطة تتبع، وإلا الانصراف، وإلا الحضور
        LatLng? position;
        DateTime? lastSeen;
        int? battery;
        var moving = false;
        if (points.isNotEmpty) {
          final last = points.last;
          position = _point(last['latitude'], last['longitude']);
          battery = (last['battery_level'] as num?)?.toInt();
          moving = last['is_moving'] == true;
          lastSeen = _time(last['timestamp']);
        } else if (checkOut != null && outPoint != null) {
          position = outPoint;
          lastSeen = checkOut;
        } else if (checkIn != null && inPoint != null) {
          position = inPoint;
          lastSeen = checkIn;
        }

        final distance = position != null && branchCenter != null ? _meters(position, branchCenter) : null;
        var totalM = 0.0;
        for (var i = 0; i + 1 < trail.length; i++) {
          totalM += _meters(trail[i], trail[i + 1]);
        }

        final status = checkOut != null
            ? TrackStatus.checkedOut
            : checkIn == null
                ? TrackStatus.absent
                : (distance != null && distance <= radius)
                    ? TrackStatus.inside
                    : TrackStatus.outside;

        return TrackedEmployee(
          employee: emp,
          status: status,
          branchName: (branch['name'] ?? 'بدون فرع').toString(),
          branchId: emp['branch_id']?.toString(),
          trail: trail,
          position: position,
          branchCenter: branchCenter,
          branchRadius: radius,
          distanceToBranch: distance,
          checkIn: checkIn,
          checkOut: checkOut,
          checkInPoint: inPoint,
          lastSeen: lastSeen,
          batteryLevel: battery,
          isMoving: moving,
          totalDistanceKm: totalM / 1000,
        );
      }(),
  ];
}

/// "350 م" أو "1.4 كم".
String formatDistance(double meters) => meters < 1000 ? '${meters.round()} م' : '${(meters / 1000).toStringAsFixed(1)} كم';
