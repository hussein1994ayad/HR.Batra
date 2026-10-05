import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hr_pro/core/services/location/geofence_monitor.dart';
import 'package:hr_pro/core/services/location/offline_json_queue.dart';
import 'package:hr_pro/core/services/location/tracking_schedule.dart';
import 'package:latlong2/latlong.dart';

void main() {
  group('OfflineJsonQueue', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('queue_test'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('appends, reads back, keeps the remainder and deletes when empty', () async {
      final q = OfflineJsonQueue('q.json', directory: () async => dir);
      expect(await q.readAll(), isEmpty);
      expect(await q.append({'a': 1}), 1);
      expect(await q.append({'a': 2}), 2);
      expect(await q.readAll(), [{'a': 1}, {'a': 2}]);
      await q.replace([{'a': 2}]);
      expect(await q.readAll(), [{'a': 2}]);
      await q.replace([]);
      expect(File('${dir.path}/q.json').existsSync(), isFalse);
    });
  });

  test('isPointInPolygon (ray casting)', () {
    const square = [LatLng(33.0, 44.0), LatLng(33.0, 44.1), LatLng(33.1, 44.1), LatLng(33.1, 44.0)];
    expect(GeofenceMonitor.isPointInPolygon(const LatLng(33.05, 44.05), square), isTrue);
    expect(GeofenceMonitor.isPointInPolygon(const LatLng(33.2, 44.05), square), isFalse);
  });

  test('isCurrentTimeBetween handles normal and overnight shifts', () {
    final noon = DateTime(2026, 10, 4, 12);
    expect(TrackingSchedule.isCurrentTimeBetween('08:00:00', '16:00:00', now: noon), isTrue);
    expect(TrackingSchedule.isCurrentTimeBetween('13:00:00', '16:00:00', now: noon), isFalse);
    final night = DateTime(2026, 10, 4, 23);
    expect(TrackingSchedule.isCurrentTimeBetween('22:00:00', '06:00:00', now: night), isTrue);
    expect(TrackingSchedule.isCurrentTimeBetween('bad', '06:00', now: night), isFalse);
  });
}
