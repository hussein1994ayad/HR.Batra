// تدقيق 14/10/2026 — المرحلة 3: معاينة «إنهاء الخدمات» قبل التعطيل، وسطور الكشف الجديدة.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hr_pro/core/logic/end_of_service.dart';
import 'package:hr_pro/core/models/salary_slip_model.dart';
import 'package:hr_pro/data/repositories/employee_admin_repository.dart';
import 'package:hr_pro/presentation/employee/payslips/payslips_logic.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Map<String, dynamic> _preview() => {
      'last_day': '2026-10-28',
      'total_net': 853333,
      'loans_left_after': 150000,
      'periods': [
        {
          'month': '2026-10', 'start_date': '2026-10-01', 'cutoff_date': '2026-10-26', 'can_approve_now': false,
          'expected_net': 800000, 'loan_cut': 0, 'excess_deductions': 0,
          'summary': {'basic': 800000, 'basic_note': 'راتب المسير كامل: 800,000 د.ع', 'earnings': 0, 'deductions': 0, 'loans': 0, 'net': 800000},
        },
        {
          'month': '2026-11', 'start_date': '2026-10-27', 'cutoff_date': '2026-11-26', 'can_approve_now': false,
          'expected_net': 0, 'loan_cut': 50000, 'excess_deductions': 20000,
          'summary': {
            'basic': 53333, 'basic_note': 'نهاية خدمة: 2 يوم دوام من 27/10 لحد 28/10', 'earnings': 0, 'deductions': 73333,
            'loans': 50000, 'net': -70000, 'pending_count': 1,
          },
        },
      ],
    };

void main() {
  test('the preview explains every period in plain words before deactivating', () {
    final text = EndOfServicePreview.fromMap(_preview()).describe();
    expect(text, contains('مسير الشهر العاشر 2026:'));
    expect(text, contains('راتب المسير كامل: 800,000 د.ع'));
    expect(text, contains('مسير الشهر الحادي عشر 2026:'));
    expect(text, contains('نهاية خدمة: 2 يوم دوام'));
    expect(text, contains('ينخصم منه 0 د.ع بس'));
    expect(text, contains('خصومات أكثر من الراتب بـ 20,000 د.ع'));
    expect(text, contains('1 حركة تنتظر قرارك'));
    // آخر يوم 28 بعد يوم القطع 26: الأول ينعتمد بعد 26/10، والثاني بعد آخر يوم 28/10
    expect(text, contains('ينعتمد بعد 26/10'));
    expect(text, contains('ينعتمد بعد 28/10'));
    expect(text, contains('المجموع المستحق: 853,333 د.ع'));
    expect(text, contains('باقي عليه سلف 150,000 د.ع'));
  });

  test('the preview comes from the server; before the database update the app still deactivates', () async {
    var oldServer = false;
    Map<String, dynamic>? body;
    final client = SupabaseClient('https://fake.supabase.test', 'anon', httpClient: MockClient((req) async {
      const json = {'content-type': 'application/json'};
      body = jsonDecode(req.body) as Map<String, dynamic>;
      return oldServer
          ? http.Response(jsonEncode({'code': 'PGRST202', 'message': 'function not found'}), 404, headers: json, request: req)
          : http.Response(jsonEncode(_preview()), 200, headers: json, request: req);
    }));
    final repo = EmployeeAdminRepository(client: client);
    final p = await repo.endOfServicePreview('e1', DateTime(2026, 10, 28));
    expect(p?.periods, hasLength(2));
    expect(body, {'p_employee_id': 'e1', 'p_last_day': '2026-10-28'});
    oldServer = true;
    expect(await repo.endOfServicePreview('e1', DateTime(2026, 10, 28)), isNull);
  });

  test('new slip lines have plain labels', () {
    expect(kPayrollEventLabels['rounding'], 'فرق تقريب');
    final details = slipLinesToDetails([
      {'line_type': 'excess_deduction', 'amount': 100000, 'direction': 1, 'event_date': '2026-10-26'},
      {'line_type': 'rounding', 'amount': 1, 'direction': -1, 'event_date': '2026-10-26'},
    ]);
    expect(details.first.reason, contains('أكثر من الراتب'));
    expect(details.last.reason, 'فرق تقريب');
    expect(details.last.type, 'deduction');
  });
}
