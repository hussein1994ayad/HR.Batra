// بيانات وهمية ثابتة لاختبارات الواجهة ولقطات الشاشة — لا تلمس القاعدة الحقيقية.

const String kTestUserId = '00000000-0000-4000-8000-000000000001';
const String kTestBranchId = '00000000-0000-4000-8000-0000000000b1';

String _today() {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
}

String _daysAgo(int d) {
  final t = DateTime.now().subtract(Duration(days: d));
  return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
}

String _monthKey(int monthsAgo) {
  final n = DateTime.now();
  final d = DateTime(n.year, n.month - monthsAgo);
  return '${d.year}-${d.month.toString().padLeft(2, '0')}';
}

String _iso(int daysAgo, int hour, int minute) {
  final t = DateTime.now().subtract(Duration(days: daysAgo));
  return DateTime(t.year, t.month, t.day, hour, minute).toUtc().toIso8601String();
}

const Map<String, dynamic> _branch = {
  'id': kTestBranchId,
  'name': 'فرع المنصور',
  'address': 'بغداد - المنصور',
  'latitude': 33.3152,
  'longitude': 44.3661,
  'radius_meters': 150,
  'created_at': '2026-01-01T00:00:00Z',
};

Map<String, dynamic> _employee(String id, String name, String role, {String code = 'E-001'}) => {
      'id': id,
      'full_name': name,
      'email': '$code@batra.test',
      'phone': '07700000000',
      'phone_number': '07700000000',
      'role': role,
      'branch_id': kTestBranchId,
      'branches': {'name': 'فرع المنصور'},
      'departments': {'name': 'المبيعات'},
      'department_id': null,
      'employee_code': code,
      'monthly_salary_iqd': 900000,
      'is_active': true,
      'must_change_password': false,
      'join_date': '2025-03-01',
      'avatar_url': null,
      'device_id_lock': null,
      'created_at': '2025-03-01T00:00:00Z',
    };

/// الصفوف التي يرجعها الخادم الوهمي لكل جدول.
Map<String, List<Map<String, dynamic>>> buildFixtures({String role = 'admin'}) {
  final today = _today();
  final employees = [
    _employee(kTestUserId, 'حسين أياد', role),
    _employee('00000000-0000-4000-8000-000000000002', 'علي كريم', 'employee', code: 'E-002'),
    _employee('00000000-0000-4000-8000-000000000003', 'زينب حسن', 'employee', code: 'E-003'),
    _employee('00000000-0000-4000-8000-000000000004', 'مصطفى جاسم', 'manager', code: 'E-004'),
  ];
  final attendance = [
    for (var d = 0; d < 6; d++)
      {
        'id': 'att-$d',
        'employee_id': kTestUserId,
        'branch_id': kTestBranchId,
        'work_date': _daysAgo(d),
        'check_in_time': _iso(d, 8, d == 2 ? 25 : 2),
        'check_out_time': d == 0 ? null : _iso(d, 16, 5),
        'status': d == 2 ? 'late' : 'present',
        'is_mock_detected': false,
        'deduction_applied': false,
        'employees': {'full_name': 'حسين أياد', 'branch_id': kTestBranchId},
        'created_at': _iso(d, 8, 2),
      },
  ];
  return {
    'employees': employees,
    'v_employee_directory': employees,
    'branches': [_branch],
    'attendance': attendance,
    'work_schedules': [
      {
        'id': 'ws-1',
        'branch_id': kTestBranchId,
        'name': 'الدوام الصباحي',
        'check_in_time': '08:00:00',
        'check_out_time': '16:00:00',
        'grace_period_minutes': 15,
        'work_days': [0, 1, 2, 3, 4, 6],
        'created_at': '2026-01-01T00:00:00Z',
      },
    ],
    'notifications': [
      {'id': 'n1', 'employee_id': kTestUserId, 'title': 'تمت الموافقة على إجازتك', 'body': 'إجازة اعتيادية 3 أيام', 'type': 'leave', 'is_read': false, 'created_at': _iso(0, 9, 10)},
      {'id': 'n2', 'employee_id': kTestUserId, 'title': 'كشف راتب جديد', 'body': 'صدر كشف راتب الشهر', 'type': 'salary', 'is_read': true, 'created_at': _iso(2, 11, 0)},
    ],
    'leave_requests': [
      {'id': 'lr1', 'employee_id': kTestUserId, 'leave_type': 'annual', 'start_date': today, 'end_date': today, 'reason': 'ظرف عائلي', 'status': 'pending', 'is_hourly': false, 'is_paid': true, 'employees': {'full_name': 'حسين أياد'}, 'created_at': _iso(1, 10, 0)},
      {'id': 'lr2', 'employee_id': '00000000-0000-4000-8000-000000000002', 'leave_type': 'sick', 'start_date': _daysAgo(10), 'end_date': _daysAgo(9), 'reason': 'مراجعة طبية', 'status': 'approved', 'is_hourly': false, 'is_paid': true, 'employees': {'full_name': 'علي كريم'}, 'created_at': _iso(11, 10, 0)},
    ],
    'leave_balances': [
      {'employee_id': kTestUserId, 'year': DateTime.now().year, 'annual_total': 20, 'annual_used': 6, 'sick_total': 10, 'sick_used': 1},
    ],
    'loans': [
      {
        'id': 'ln1',
        'employee_id': kTestUserId,
        'amount': 600000,
        'installment_count': 6,
        'installment_amount': 100000,
        'remaining_amount': 400000,
        'status': 'approved',
        'notes': null,
        'created_at': _iso(40, 10, 0),
        'employees': {'full_name': 'حسين أياد', 'branch_id': kTestBranchId, 'monthly_salary_iqd': 900000, 'branches': {'name': 'فرع المنصور'}},
        'loan_installments': [
          for (var i = 0; i < 6; i++)
            {'id': 'i$i', 'loan_id': 'ln1', 'amount': 100000, 'due_date': _daysAgo(30 - i * 30), 'is_paid': i < 2, 'paid_at': i < 2 ? _iso(30 - i * 30, 12, 0) : null},
        ],
      },
      {
        'id': 'ln2',
        'employee_id': '00000000-0000-4000-8000-000000000002',
        'amount': 300000,
        'installment_count': 3,
        'installment_amount': 100000,
        'remaining_amount': 300000,
        'status': 'pending',
        'created_at': _iso(1, 9, 0),
        'employees': {'full_name': 'علي كريم', 'branch_id': kTestBranchId, 'monthly_salary_iqd': 750000, 'branches': {'name': 'فرع المنصور'}},
        'loan_installments': <Map<String, dynamic>>[],
      },
    ],
    'salary_slips': [
      for (var i = 1; i <= 6; i++)
        {
          'id': 'ss$i',
          'employee_id': kTestUserId,
          'work_month': _monthKey(i),
          'basic_salary': 900000,
          'allowances': i.isEven ? 50000 : 0,
          'deductions': i == 2 ? 30000 : 0,
          'loans_deduction': i <= 2 ? 100000 : 0,
          'net_salary': 900000 + (i.isEven ? 50000 : 0) - (i == 2 ? 30000 : 0) - (i <= 2 ? 100000 : 0),
          'status': 'published',
          'created_at': _iso(20 + i * 30, 10, 0),
        },
    ],
    'bonuses_deductions': [
      {'id': 'bd1', 'employee_id': kTestUserId, 'type': 'bonus', 'amount': 50000, 'reason': 'مكافأة أداء', 'created_at': _iso(20, 10, 0)},
    ],
    'employee_devices': [
      {'id': 'd1', 'employee_id': '00000000-0000-4000-8000-000000000003', 'device_id': 'dev-abc', 'model': 'Samsung A54', 'os_version': 'Android 14', 'status': 'pending', 'created_at': _iso(0, 7, 50), 'employees': {'full_name': 'زينب حسن'}},
    ],
    'announcements': [
      {'id': 'a1', 'title': 'عطلة رسمية', 'body': 'الخميس القادم عطلة رسمية لجميع الفروع', 'created_at': _iso(3, 9, 0)},
    ],
    'system_settings': [
      {'key': 'tracking_enabled', 'value': 'true'},
    ],
    'deleted_files': <Map<String, dynamic>>[],
    'location_tracking': <Map<String, dynamic>>[],
    'geofence_violations': <Map<String, dynamic>>[],
    'mock_gps_attempts': <Map<String, dynamic>>[],
    'tracking_schedules': <Map<String, dynamic>>[],
    'employee_geofence_assignments': <Map<String, dynamic>>[],
    'app_versions': <Map<String, dynamic>>[],
    'fcm_tokens': <Map<String, dynamic>>[],
    'device_tokens': <Map<String, dynamic>>[],
  };
}
