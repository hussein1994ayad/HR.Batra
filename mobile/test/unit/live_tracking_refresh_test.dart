// خريطة التتبع الحي: التحديث يجيب النقاط الجديدة بس ويدمجها (كان يعيد تحميل كل نقاط اليوم لكل الموظفين كل 15 ثانية).

import 'package:flutter_test/flutter_test.dart';
import 'package:hr_pro/core/logic/tracking_rules.dart';

Map<String, dynamic> _p(String id, String timestamp, String createdAt) =>
    {'id': id, 'employee_id': 'e1', 'latitude': 33.3, 'longitude': 44.4, 'timestamp': timestamp, 'created_at': createdAt};

void main() {
  final loaded = [
    _p('a', '2026-10-11T06:00:00Z', '2026-10-11T06:00:01Z'),
    _p('b', '2026-10-11T06:05:00Z', '2026-10-11T06:05:02Z'),
  ];

  test('the next refresh asks only for points that reached the server after the newest loaded one', () {
    expect(latestCreatedAt(loaded), '2026-10-11T06:05:02Z');
    expect(latestCreatedAt(const []), isNull); // أول تحميل: كل نقاط اليوم
    expect(latestCreatedAt([{'id': 'x', 'timestamp': '2026-10-11T06:00:00Z'}]), isNull);
  });

  test('new points are appended once, in the order they happened', () {
    final merged = mergeNewPoints(loaded, [
      _p('b', '2026-10-11T06:05:00Z', '2026-10-11T06:05:02Z'), // مكرر
      _p('c', '2026-10-11T06:10:00Z', '2026-10-11T06:10:01Z'),
      // نقطة قديمة انرفعت متأخر (جان بدون إنترنت): تدخل بمكانها بالمسار
      _p('d', '2026-10-11T06:02:00Z', '2026-10-11T06:11:00Z'),
    ]);
    expect(merged.map((p) => p['id']), ['a', 'd', 'b', 'c']);
    expect(latestCreatedAt(merged), '2026-10-11T06:11:00Z');
  });

  test('nothing new keeps the same list (no rebuild work)', () {
    expect(identical(mergeNewPoints(loaded, const []), loaded), isTrue);
    expect(identical(mergeNewPoints(loaded, [loaded.first]), loaded), isTrue);
  });
}
