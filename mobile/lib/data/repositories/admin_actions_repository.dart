// =========================================================================
// إجراءات الإدارة: قرارات الخصم، الإجازات، السلف، واعتماد الأجهزة
// =========================================================================
// كل دالة ترمي عند فشل أي كتابة حتى تعرض الشاشة الخطأ بدلاً من نجاح وهمي.
// إشعار الموظف بقرار الإجازة/السلفة يُرسل من قاعدة البيانات
// (trg_notify_employee_leave_decision / trg_notify_employee_loan_decision).
// =========================================================================

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/models/models.dart';
import '../../core/services/supabase_service.dart';

class AdminActionsRepository {
  AdminActionsRepository({SupabaseClient? client}) : _db = client ?? SupabaseService.client;
  final SupabaseClient _db;

  String get _adminId {
    final id = _db.auth.currentUser?.id;
    if (id == null) throw StateError('انتهت الجلسة، يرجى تسجيل الدخول مجدداً.');
    return id;
  }

  /// قرار خصم أو إعفاء لغياب/تأخير/نصف يوم (نفس saveDecision في الويب).
  /// الغياب الافتراضي يُنشأ له سجل حضور بحالة غياب.
  Future<void> applyDecision(PendingDecision item, {required bool deduct, required String reason, double amount = 0}) async {
    final status = deduct ? 'applied' : 'ignored';

    if (item.isVirtual && item.branchId == null) {
      throw StateError('الموظف غير مرتبط بفرع، يرجى ربطه بفرع أولاً.');
    }

    if (deduct && amount > 0) {
      await _db.from('bonuses_deductions').insert({
        'employee_id': item.employeeId,
        'type': 'deduction',
        'amount': amount,
        'reason': reason,
        // تاريخ يوم المخالفة حتى يُحتسب في دورة الراتب الصحيحة
        'issue_date': item.workDate,
      });
    }

    final values = {
      'deduction_status': status,
      'deduction_applied': deduct,
      'deduction_reason': reason,
    };
    if (item.isVirtual) {
      final existing = rowOf(await _db
          .from('attendance')
          .select('id')
          .eq('employee_id', item.employeeId)
          .eq('work_date', item.workDate)
          .maybeSingle());
      if (existing != null) {
        await _db.from('attendance').update({...values, 'status': 'absent'}).eq('id', existing.str('id')!);
      } else {
        await _db.from('attendance').insert({
          ...values,
          'employee_id': item.employeeId,
          'branch_id': item.branchId,
          'status': 'absent',
          'work_date': item.workDate,
        });
      }
    } else {
      await _db.from('attendance').update(values).eq('id', item.attendanceId!);
    }

    await _db.from('notifications').insert({
      'employee_id': item.employeeId,
      'title': deduct ? 'إشعار بخصم غياب/تأخير ⚠️' : 'إعفاء من الخصم 🎉',
      'body': deduct
          ? 'تم تطبيق خصم بسبب ${item.statusArabic} ليوم ${item.workDate}. السبب: $reason'
          : 'تم إعفاؤك من خصم ${item.statusArabic} ليوم ${item.workDate}. السبب: $reason',
      'type': 'attendance',
    });
  }

  Future<void> decideLeave(String requestId, {required bool approve, String? rejectionReason}) async {
    await _db.from('leave_requests').update({
      'status': approve ? 'approved' : 'rejected',
      'approved_by': _adminId,
      'approved_at': DateTime.now().toUtc().toIso8601String(),
      if (!approve && rejectionReason != null && rejectionReason.trim().isNotEmpty)
        'rejection_reason': rejectionReason.trim(),
    }).eq('id', requestId);
  }

  /// اعتماد السلفة وتوليد أقساطها في معاملة واحدة على السيرفر (approve_loan).
  Future<void> approveLoan(LoanModel loan, {double? amount, int? months, DateTime? firstDue}) async {
    final due = firstDue ?? _sameDayNextMonth(DateTime.now());
    await _db.rpc<void>('approve_loan', params: {
      'p_loan_id': loan.id,
      'p_amount': amount ?? loan.amount,
      'p_months': months ?? loan.installmentCount,
      'p_first_due': '${due.year}-${due.month.toString().padLeft(2, '0')}-${due.day.toString().padLeft(2, '0')}',
    });
  }

  Future<void> rejectLoan(String loanId, {String? reason}) async {
    await _db.from('loans').update({
      'status': 'rejected',
      'approved_by': _adminId,
      'approved_at': DateTime.now().toUtc().toIso8601String(),
      'rejection_reason': (reason == null || reason.trim().isEmpty) ? null : reason.trim(),
    }).eq('id', loanId);
  }

  /// اعتماد جهاز: يُقفل حساب الموظف على هذا الجهاز ويُرسل له إشعاراً.
  Future<void> approveDevice(DeviceRequest request) async {
    await _db.from('employee_devices').update({
      'is_approved': true,
      'approved_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', request.id);
    await _db.from('employees').update({'device_id_lock': request.deviceId}).eq('id', request.employeeId);
    await _db.from('notifications').insert({
      'employee_id': request.employeeId,
      'title': 'اعتماد جهاز الدخول الجديد 📱',
      'body': 'تمت موافقة الإدارة على اعتماد هاتف تسجيل دخولك الجديد بنجاح.',
      'type': 'device',
    });
  }

  Future<void> rejectDevice(String requestId) async {
    await _db.from('employee_devices').delete().eq('id', requestId);
  }

  /// نفس اليوم من الشهر القادم مع تثبيته على آخر الشهر (31 → 30/28).
  static DateTime _sameDayNextMonth(DateTime now) {
    final lastDay = DateTime(now.year, now.month + 2, 0).day;
    return DateTime(now.year, now.month + 1, now.day > lastDay ? lastDay : now.day);
  }
}
