import 'package:flutter_test/flutter_test.dart';
import 'package:hr_pro/presentation/employee/directory/directory_logic.dart';

void main() {
  final people = <Map<String, dynamic>>[
    {'full_name': 'أحمد علي', 'department_name': 'المبيعات', 'branch_name': 'الكرادة', 'employee_code': 'EMP-001', 'phone': '07701234567', 'email': 'Ahmed@x.com'},
    {'full_name': 'إيمان حسن', 'department_name': 'الحسابات', 'branch_name': 'المنصور', 'employee_code': 'EMP-002', 'phone': '', 'email': ''},
    {'full_name': 'سارة', 'department_name': null, 'branch_name': '', 'employee_code': null, 'phone': null, 'email': null},
  ];

  test('directoryBranchOptions: all first, unique, no blanks', () {
    expect(directoryBranchOptions(people), ['all', 'الكرادة', 'المنصور']);
  });

  test('empty query keeps everyone in the selected branch', () {
    expect(filterDirectory(people, query: '', branch: 'all').length, 3);
    expect(filterDirectory(people, query: '', branch: 'المنصور').single['employee_code'], 'EMP-002');
  });

  test('arabic search ignores hamza forms; code, phone and email match', () {
    expect(filterDirectory(people, query: 'ايمان', branch: 'all').single['employee_code'], 'EMP-002');
    expect(filterDirectory(people, query: 'emp-001', branch: 'all').single['full_name'], 'أحمد علي');
    expect(filterDirectory(people, query: '0770', branch: 'all').single['full_name'], 'أحمد علي');
    expect(filterDirectory(people, query: 'AHMED@', branch: 'all').single['full_name'], 'أحمد علي');
  });

  test('branch filter applies before search', () {
    expect(filterDirectory(people, query: 'احمد', branch: 'المنصور'), isEmpty);
  });
}
