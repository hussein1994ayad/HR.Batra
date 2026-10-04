import 'package:flutter_test/flutter_test.dart';
import 'package:hr_pro/presentation/admin/branches/branches_logic.dart';

void main() {
  test('mergeBranchSchedules pairs each branch with its schedule, or {}', () {
    final merged = mergeBranchSchedules(
      [
        {'id': 'b1', 'name': 'الكرادة'},
        {'id': 'b2', 'name': 'المنصور'},
      ],
      [
        {'id': 's1', 'branch_id': 'b2', 'check_in_time': '08:00:00'},
      ],
    );
    expect(merged, [
      {'zone_id': 'b1', 'zone_name': 'الكرادة', 'has_schedule': false, 'schedule': <String, dynamic>{}},
      {
        'zone_id': 'b2',
        'zone_name': 'المنصور',
        'has_schedule': true,
        'schedule': {'id': 's1', 'branch_id': 'b2', 'check_in_time': '08:00:00'},
      },
    ]);
  });

  test('no branches gives an empty list', () {
    expect(mergeBranchSchedules(const [], const [{'branch_id': 'x'}]), isEmpty);
  });
}
