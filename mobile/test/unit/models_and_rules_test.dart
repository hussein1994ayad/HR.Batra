import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hr_pro/core/logic/attendance_rules.dart';
import 'package:hr_pro/core/models/models.dart';
import 'package:hr_pro/core/utils/arabic_format.dart';
import 'package:hr_pro/core/utils/input_formatters.dart';

WorkScheduleModel schedule({
  String id = 's',
  String? employeeId,
  String? departmentId,
  String? branchId,
  String checkIn = '08:00:00',
  String checkOut = '16:00:00',
  List<int> days = const [0, 1, 2, 3, 4],
  DateTime? createdAt,
}) =>
    WorkScheduleModel(
      id: id,
      name: id,
      employeeId: employeeId,
      departmentId: departmentId,
      branchId: branchId,
      checkInTime: checkIn,
      checkOutTime: checkOut,
      workDays: days,
      createdAt: createdAt,
    );

void main() {
  group('JsonMap', () {
    test('reads nested joins safely whatever their shape', () {
      final row = <String, dynamic>{
        'amount': '1500.5',
        'count': 3.0,
        'employees': [
          {'full_name': 'علي'},
        ],
        'bad': 7,
      };
      expect(row.dbl('amount'), 1500.5);
      expect(row.integer('count'), 3);
      expect(row.obj('employees')?.str('full_name'), 'علي');
      expect(row.obj('bad'), isNull);
      expect(row.obj('missing')?.str('x'), isNull);
      expect(rowsOf('not a list'), isEmpty);
    });
  });

  group('models', () {
    test('LoanModel parses the real loans columns and sorts installments', () {
      final loan = LoanModel.fromMap({
        'id': 'l1',
        'employee_id': 'e1',
        'amount': 1000000,
        'installment_amount': 333333,
        'installment_count': 3,
        'remaining_amount': 666667,
        'status': 'approved',
        'employees': {'full_name': 'علي', 'monthly_salary_iqd': 900000},
        'loan_installments': [
          {'id': 'b', 'loan_id': 'l1', 'due_date': '2026-03-01', 'amount': 333334, 'is_paid': false},
          {'id': 'a', 'loan_id': 'l1', 'due_date': '2026-02-01', 'amount': 333333, 'is_paid': true, 'payment_type': 'cash'},
        ],
      });
      expect(loan.employeeName, 'علي');
      expect(loan.employeeSalary, 900000);
      expect(loan.installments.map((i) => i.id), ['a', 'b']);
      expect(loan.nextInstallment?.id, 'b');
      expect(loan.paidAmount, 333333);
      expect(loan.isActive, isTrue);
      expect(loan.installments.first.isCash, isTrue);
    });

    test('PendingDecision distinguishes recorded and virtual absences', () {
      final real = PendingDecision.fromAttendance({
        'id': 'a1',
        'employee_id': 'e1',
        'status': 'late',
        'work_date': '2026-09-24',
        'check_in_time': '2026-09-24T06:20:00Z',
        'employees': {'full_name': 'علي', 'branch_id': 'b1'},
      });
      expect(real.isVirtual, isFalse);
      expect(real.branchId, 'b1');
      expect(real.statusArabic, 'تأخير');

      const virtual = PendingDecision(employeeId: 'e2', employeeName: 'x', status: 'absent', workDate: '2026-09-24');
      expect(virtual.isVirtual, isTrue);
      expect(virtual.key, 'virtual_e2_2026-09-24');
    });

    test('LeaveRequestModel counts calendar days and maps Arabic labels', () {
      final leave = LeaveRequestModel.fromMap({
        'id': 'l',
        'employee_id': 'e',
        'leave_type': 'sick',
        'start_date': '2026-10-04T21:00:00Z',
        'end_date': '2026-10-06T21:00:00Z',
        'status': 'pending',
      });
      expect(leave.typeArabic, 'إجازة مرضية');
      expect(leave.daysCount, 3);
      expect(leave.hasAttachment, isFalse);
    });

    test('EmployeeModel reads salary, joins and documents', () {
      final emp = EmployeeModel.fromMap({
        'id': 'e',
        'full_name': 'علي',
        'role': 'manager',
        'monthly_salary_iqd': '750000',
        'branches': {'name': 'الكرادة'},
        'document_urls': ['a.jpg', 5],
        'device_id_lock': 'force_lock_active',
      });
      expect(emp.monthlySalary, 750000);
      expect(emp.branchName, 'الكرادة');
      expect(emp.documentUrls, ['a.jpg']);
      expect(emp.roleArabic, 'مدير موارد');
      expect(emp.isDeviceLocked, isTrue);
    });
  });

  group('attendance rules', () {
    test('schedule priority is employee > department > branch, newest first', () {
      final list = [
        schedule(id: 'branch', branchId: 'b'),
        schedule(id: 'dept', departmentId: 'd'),
        schedule(id: 'old-emp', employeeId: 'e', createdAt: DateTime(2025)),
        schedule(id: 'new-emp', employeeId: 'e', createdAt: DateTime(2026)),
      ];
      expect(resolveWorkSchedule(employeeId: 'e', departmentId: 'd', branchId: 'b', schedules: list)?.id, 'new-emp');
      expect(resolveWorkSchedule(employeeId: 'x', departmentId: 'd', branchId: 'b', schedules: list)?.id, 'dept');
      expect(resolveWorkSchedule(employeeId: 'x', branchId: 'b', schedules: list)?.id, 'branch');
      expect(resolveWorkSchedule(employeeId: 'x', schedules: list), isNull);
    });

    test('late and early minutes follow the schedule, not a fixed 08:30', () {
      final s = schedule(checkIn: '08:00:00', checkOut: '16:00:00');
      expect(lateMinutes(DateTime(2026, 9, 24, 8, 25), s), 25);
      expect(lateMinutes(DateTime(2026, 9, 24, 7, 55), s), 0);
      expect(lateMinutes(DateTime(2026, 9, 24, 9, 10), null), 10); // 09:00 بدون جدول
      expect(earlyLeaveMinutes(DateTime(2026, 9, 24, 15, 0), s), 60);
      expect(suggestedPenalty('late', 25), 1250);
      expect(suggestedPenalty('absent', 0), kAbsencePenalty);
    });

    test('day summary skips days off and approved leave', () {
      // 2026-09-25 جمعة: خارج الدوام الافتراضي
      final friday = DateTime(2026, 9, 25);
      final thursday = DateTime(2026, 9, 24);
      const emps = [
        (id: 'a', departmentId: null, branchId: 'b'),
        (id: 'b', departmentId: null, branchId: 'b'),
        (id: 'c', departmentId: null, branchId: 'b'),
        (id: 'd', departmentId: null, branchId: 'b'),
      ];
      final thu = summarizeDay(
        date: thursday,
        employees: emps,
        statusByEmployee: {'a': 'present', 'b': 'absent'},
        onLeave: {'d'},
        schedules: const [],
      );
      expect((thu.present, thu.absent), (1, 2));
      expect(thu.missingEmployeeIds, ['c']);

      final fri = summarizeDay(date: friday, employees: emps, statusByEmployee: const {}, onLeave: const {}, schedules: const []);
      expect((fri.present, fri.absent), (0, 0));
    });
  });

  group('formatting', () {
    test('Arabic durations and 12h times', () {
      expect(formatDurationArabic(125), 'ساعتين و 5 دقائق');
      expect(formatDurationArabic(60), 'ساعة');
      expect(formatDurationArabic(0), '0 دقيقة');
      expect(formatTime12h(DateTime(2026, 1, 1, 0, 5)), '12:05 AM');
      expect(formatTime12h(DateTime(2026, 1, 1, 13, 30)), '1:30 PM');
      expect(isoDate(DateTime(2026, 3, 7)), '2026-03-07');
      expect(formatThousands(1500000), '1.500.000');
      expect(parseThousands('1.500.000'), 1500000);
    });

    test('thousands formatter keeps the cursor after the typed digit', () {
      final result = DotThousandsSeparatorInputFormatter().formatEditUpdate(
        const TextEditingValue(text: '100.000'),
        const TextEditingValue(text: '1000000', selection: TextSelection.collapsed(offset: 7)),
      );
      expect(result.text, '1.000.000');
      expect(result.selection.baseOffset, 9);
    });
  });
}
