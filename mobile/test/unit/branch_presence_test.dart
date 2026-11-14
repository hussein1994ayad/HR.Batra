// دخول وخروج الفرع ما ينخدع بقفزات الموقع (بلاغ 14/11/2026: الموظف واقف بالفرع والموبايل نطى نقاط على بعد 123–204 م
// لثواني ورجع، فطلع «خروج» وبعدها «دخول»). الأرقام من نقاط ذاك اليوم الحقيقية (نصف قطر الفرع 100 م).

import 'package:flutter_test/flutter_test.dart';
import 'package:hr_pro/core/services/location/branch_presence.dart';
import 'package:hr_pro/core/services/location/branch_presence_monitor.dart';

void main() {
  final t0 = DateTime(2026, 11, 14, 9, 40, 22);
  DateTime at(int seconds) => t0.add(Duration(seconds: seconds));

  test('standing in the branch while the phone jumps 123–204 m away for seconds: no exit, no enter', () {
    final p = BranchPresence();
    final events = [
      p.update(distance: 13, radius: 100, accuracy: 10, at: at(0)),
      p.update(distance: 12, radius: 100, accuracy: 10, at: at(23)),
      p.update(distance: 123, radius: 100, accuracy: 30, at: at(53)),
      p.update(distance: 202, radius: 100, accuracy: 30, at: at(58)),
      p.update(distance: 204, radius: 100, accuracy: 30, at: at(68)),
      p.update(distance: 8, radius: 100, accuracy: 10, at: at(83)),
      p.update(distance: 154, radius: 100, accuracy: 30, at: at(119)),
      p.update(distance: 9, radius: 100, accuracy: 10, at: at(123)),
    ];
    expect(events.whereType<bool>(), isEmpty);
  });

  test('really leaving: exit once, after staying out two minutes', () {
    final p = BranchPresence();
    expect(p.update(distance: 10, radius: 100, accuracy: 10, at: at(0)), isNull, reason: 'first point only sets the state');
    expect(p.update(distance: 160, radius: 100, accuracy: 15, at: at(60)), isNull, reason: 'one minute out is not enough');
    expect(p.update(distance: 400, radius: 100, accuracy: 15, at: at(190)), isFalse, reason: 'out for more than two minutes = exit');
    expect(p.update(distance: 450, radius: 100, accuracy: 15, at: at(250)), isNull, reason: 'no second exit');
  });

  test('coming back: enter once, after staying in two minutes', () {
    final p = BranchPresence();
    p.update(distance: 500, radius: 100, accuracy: 10, at: at(0));
    expect(p.update(distance: 40, radius: 100, accuracy: 10, at: at(30)), isNull);
    expect(p.update(distance: 20, radius: 100, accuracy: 10, at: at(160)), isTrue);
  });

  test('a point that could still be inside (distance minus its error is within the radius) changes nothing', () {
    final p = BranchPresence();
    p.update(distance: 10, radius: 100, accuracy: 10, at: at(0));
    // 140 m away but ±60 m: could be 80 m = inside → not a sure exit
    expect(p.update(distance: 140, radius: 100, accuracy: 60, at: at(30)), isNull);
    expect(p.update(distance: 140, radius: 100, accuracy: 60, at: at(300)), isNull);
  });

  test('a jump back inside cancels a half-confirmed exit', () {
    final p = BranchPresence();
    p.update(distance: 10, radius: 100, accuracy: 10, at: at(0));
    p.update(distance: 300, radius: 100, accuracy: 10, at: at(10)); // starts counting
    p.update(distance: 15, radius: 100, accuracy: 10, at: at(70)); // back in: counting stops
    expect(p.update(distance: 300, radius: 100, accuracy: 10, at: at(140)), isNull,
        reason: 'the two minutes start again from 140 s, not from 10 s');
  });

  test('the alert says the Baghdad time in plain words (not a long cut-off server time)', () {
    final event = {'employee_id': 'e', 'branch_name': 'مكتب بغداد الرئيسي', 'event_type': 'exit', 'timestamp': '2026-11-14T06:41:15.000Z'};
    final live = BranchPresenceMonitor.notificationFor(event);
    expect(live['title'], 'خروج من فرع مكتب بغداد الرئيسي');
    expect(live['body'], 'تم رصد خروجك من فرع مكتب بغداد الرئيسي الساعة 9:41 ص');
    expect(BranchPresenceMonitor.notificationFor({...event, 'event_type': 'enter'}, archived: true)['title'],
        'دخول فرع مكتب بغداد الرئيسي (مؤرشف)');
  });
}
