// تدقيق 14/10/2026 — المرحلة 4: تفعيل الحساب بتاريخ رجوع، وسجل الموظف.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hr_pro/core/logic/employee_history.dart';
import 'package:hr_pro/data/repositories/employee_admin_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('the history comes back ready to show, with a label for each kind', () {
    final e = EmployeeHistoryEvent.fromMap({'date': '2026-09-01', 'kind': 'transfer', 'text': 'انتقل من فرع الكرادة إلى فرع المنصور'});
    expect(e.date, DateTime(2026, 9));
    expect(e.kindLabel, 'نقل');
    expect(EmployeeHistoryEvent.fromMap({'date': '2026-10-12', 'kind': 'return', 'text': 'x'}).kindLabel, 'رجوع');
  });

  test('reactivating says how many break days are not counted as absence', () {
    final r = ReactivateResult.fromMap({'gap_days': 6, 'warnings': ['راتب الشهر العاشر 2026 معتمد']});
    expect(r.message('حيدر'), 'رجع حيدر للعمل. 6 يوم انقطاع ما تنحسب غياب');
    expect(r.warnings, hasLength(1));
    expect(const ReactivateResult().message('حيدر'), 'رجع حيدر للعمل');
  });

  test('the return date goes to the server; before the database update the app still reactivates', () async {
    var oldServer = false;
    final calls = <String>[];
    Map<String, dynamic>? body;
    final client = SupabaseClient('https://fake.supabase.test', 'anon', httpClient: MockClient((req) async {
      const json = {'content-type': 'application/json'};
      calls.add('${req.method} ${req.url.path}');
      if (req.url.path.startsWith('/rest/v1/rpc/')) {
        body = jsonDecode(req.body) as Map<String, dynamic>;
        if (oldServer) return http.Response(jsonEncode({'code': 'PGRST202', 'message': 'function not found'}), 404, headers: json, request: req);
        if (req.url.path.endsWith('get_employee_history')) {
          return http.Response(jsonEncode([{'date': '2026-01-01', 'kind': 'join', 'text': 'باشر بالعمل'}]), 200, headers: json, request: req);
        }
        return http.Response(jsonEncode({'gap_days': 6, 'warnings': <String>[]}), 200, headers: json, request: req);
      }
      return http.Response(jsonEncode([{'id': 'e1'}]), 200, headers: json, request: req);
    }));
    final repo = EmployeeAdminRepository(client: client);

    final r = await repo.reactivate('e1', DateTime(2026, 10, 12));
    expect(r.gapDays, 6);
    expect(body, {'p_employee_id': 'e1', 'p_return_date': '2026-10-12'});
    expect((await repo.employeeHistory('e1'))?.single.kindLabel, 'مباشرة');

    oldServer = true;
    calls.clear();
    expect((await repo.reactivate('e1', DateTime(2026, 10, 12))).gapDays, 0);
    expect(calls.last, 'PATCH /rest/v1/employees');
    expect(await repo.employeeHistory('e1'), isNull);
  });
}
