// تدقيق 14/10/2026 — المرحلة 1: الراتب من get_employee_pay، والحفظ اللي ما أثّر يطلع خطأ، وأدوات الأدمن ما تنفتح للمدير.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hr_pro/core/routes/app_router.dart';
import 'package:hr_pro/data/repositories/employee_pay.dart';
import 'package:hr_pro/data/repositories/write_guard.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('withPay adds the salary the server allowed, and leaves others untouched', () {
    final pay = {
      'e1': <String, dynamic>{'monthly_salary_iqd': 900000, 'future_salary_iqd': null, 'future_salary_month': null},
    };
    expect(withPay({'id': 'e1', 'full_name': 'زينب'}, pay)['monthly_salary_iqd'], 900000);
    expect(withPay({'id': 'e2', 'full_name': 'مصطفى'}, pay).containsKey('monthly_salary_iqd'), isFalse);
    expect(withPay({'employee_id': 'e1'}, pay, idKey: 'employee_id')['monthly_salary_iqd'], 900000);
  });

  test('salaries come from get_employee_pay; before the database update they are read directly', () async {
    var oldServer = false;
    final paths = <String>[];
    final client = SupabaseClient('https://fake.supabase.test', 'anon', httpClient: MockClient((req) async {
      paths.add(req.url.path);
      const json = {'content-type': 'application/json'};
      if (req.url.path == '/rest/v1/rpc/get_employee_pay') {
        return oldServer
            ? http.Response(jsonEncode({'code': 'PGRST202', 'message': 'function not found'}), 404, headers: json, request: req)
            : http.Response(jsonEncode([{'employee_id': 'e1', 'monthly_salary_iqd': 900000}]), 200, headers: json, request: req);
      }
      return http.Response(jsonEncode([{'id': 'e2', 'monthly_salary_iqd': 750000}]), 200, headers: json, request: req);
    }));
    expect((await fetchEmployeePay(client))['e1']?['monthly_salary_iqd'], 900000);
    expect(paths, ['/rest/v1/rpc/get_employee_pay']);
    oldServer = true;
    expect((await fetchEmployeePay(client, ids: ['e2']))['e2']?['monthly_salary_iqd'], 750000);
    expect(paths.last, '/rest/v1/employees');
  });

  test('the readable employee columns never include the salary', () {
    for (final c in ['monthly_salary_iqd', 'future_salary_iqd', 'future_salary_month', 'plain_password']) {
      expect(kEmployeeColumns.contains(c), isFalse, reason: c);
    }
  });

  test('a write that changed nothing is an error, not a silent success', () {
    expect(() => ensureChanged(const []), throwsA(isA<PostgrestException>()));
    expect(() => ensureChanged(const [{'id': 'b1'}]), returnsNormally);
  });

  test('branches and work schedules are admin-only routes', () {
    expect(kAdminOnlyRoutes, containsAll([AppRoutes.adminBranchManagement, AppRoutes.adminBranchSchedule, AppRoutes.adminLoans]));
    expect(kAdminOnlyRoutes.contains(AppRoutes.adminDashboard), isFalse);
  });
}
