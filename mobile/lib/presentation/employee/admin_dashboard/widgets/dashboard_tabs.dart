import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/logic/attendance_rules.dart';
import '../../../../core/models/models.dart';
import '../../../../core/routes/app_router.dart';
import '../../../shared/ui/ui.dart';
import '../../../shared/widgets/info_row.dart';
import 'decision_card.dart';
import 'request_card.dart';

const _listPadding = EdgeInsets.fromLTRB(AppSpace.page, AppSpace.md, AppSpace.page, 96);

/// قائمة بعرض مريح على التابلت.
Widget _list(int count, IndexedWidgetBuilder builder, {Widget? header}) {
  return ListView.builder(
    padding: _listPadding,
    itemCount: count + (header == null ? 0 : 1),
    itemBuilder: (context, i) {
      if (header != null && i == 0) return ContentWidth(child: header);
      return ContentWidth(child: builder(context, header == null ? i : i - 1));
    },
  );
}

Widget _empty(String title, {String? message, IconData icon = Icons.task_alt_rounded, AppTone tone = AppTone.success}) => ListView(
      padding: _listPadding,
      children: [EmptyView(title: title, message: message, icon: icon, tone: tone)],
    );

/// تبويب قرارات الغياب والتأخير (يتطلب اختيار تاريخ).
class DecisionsTab extends StatelessWidget {
  const DecisionsTab({
    super.key,
    required this.hasDate,
    required this.decisions,
    required this.scheduleFor,
    required this.onDecide,
    this.busyKey,
  });

  final bool hasDate;
  final List<PendingDecision> decisions;
  final WorkScheduleModel? Function(PendingDecision) scheduleFor;
  final void Function(PendingDecision item, {required bool deduct, required String reason, required double amount}) onDecide;
  final String? busyKey;

  @override
  Widget build(BuildContext context) {
    if (!hasDate) {
      return _empty('اختر يوماً أولاً', message: 'من فلتر التاريخ فوق، حتى تظهر قرارات الغياب والتأخير لذلك اليوم.', icon: Icons.event_rounded, tone: AppTone.warning);
    }
    if (decisions.isEmpty) return _empty('لا توجد قرارات معلقة', message: 'كل الغيابات والتأخيرات لهذا اليوم محسومة.');

    return _list(decisions.length, (context, index) {
      final item = decisions[index];
      return DecisionCard(
        key: ValueKey(item.key),
        item: item,
        schedule: scheduleFor(item),
        busy: busyKey == item.key,
        onDecide: ({required deduct, required reason, required amount}) => onDecide(item, deduct: deduct, reason: reason, amount: amount),
      );
    });
  }
}

class LeavesTab extends StatelessWidget {
  const LeavesTab({super.key, required this.leaves, required this.onDecide, this.busyKey});

  final List<LeaveRequestModel> leaves;
  final void Function(LeaveRequestModel leave, bool approve) onDecide;
  final String? busyKey;

  String _period(LeaveRequestModel l) => l.isHourly
      ? '${Fmt.date(l.startDate)} · ${Fmt.timeOfDay(l.startHour)} - ${Fmt.timeOfDay(l.endHour)}'
      : Fmt.date(l.startDate) == Fmt.date(l.endDate)
          ? Fmt.dateWithDay(l.startDate)
          : '${Fmt.date(l.startDate)} إلى ${Fmt.date(l.endDate)} (${Fmt.days(l.endDate.difference(l.startDate).inDays + 1)})';

  @override
  Widget build(BuildContext context) {
    if (leaves.isEmpty) return _empty('لا توجد طلبات إجازة معلقة');

    return _list(leaves.length, (context, index) {
      final leave = leaves[index];
      return RequestCard(
        title: leave.employeeName ?? 'موظف',
        subtitle: leave.createdAt == null ? null : 'قُدّم ${Fmt.relative(leave.createdAt)}',
        tone: AppTone.accent,
        trailing: StatusBadge(leave.typeArabic, tone: AppTone.accent),
        actions: DecisionButtons(
          busy: busyKey == leave.id,
          confirmRejectTitle: 'رفض إجازة ${leave.employeeName ?? ''}؟',
          onApprove: () => onDecide(leave, true),
          onReject: () => onDecide(leave, false),
        ),
        children: [
          InfoRow(icon: Icons.event_rounded, label: 'المدة', value: _period(leave)),
          const SizedBox(height: AppSpace.sm),
          InfoRow(icon: Icons.notes_rounded, label: 'السبب', value: leave.reason ?? 'بدون سبب'),
          if (leave.hasAttachment) ...[
            const SizedBox(height: AppSpace.sm),
            InfoRow(icon: Icons.attach_file_rounded, label: 'المرفق', value: 'فتح المستند', url: leave.attachmentUrl),
          ],
        ],
      );
    });
  }
}

class LoansTab extends StatelessWidget {
  const LoansTab({super.key, required this.loans, required this.onDecide, this.busyKey});

  final List<LoanModel> loans;
  final void Function(LoanModel loan, bool approve) onDecide;
  final String? busyKey;

  @override
  Widget build(BuildContext context) {
    final shortcut = AppCard(
      onTap: () => context.push(AppRoutes.adminLoans),
      child: const Row(
        children: [
          ToneIcon(Icons.table_chart_rounded),
          SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('سجل المستلفين وكشوف Excel', style: AppText.subtitle),
                Text('المبالغ، الأقساط، التعهدات، والتصدير', style: AppText.caption),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
        ],
      ),
    );

    if (loans.isEmpty) {
      return ListView(
        padding: _listPadding,
        children: [ContentWidth(child: shortcut), const EmptyView(title: 'لا توجد طلبات سلف معلقة', icon: Icons.task_alt_rounded, tone: AppTone.success)],
      );
    }

    return _list(
      loans.length,
      header: Padding(padding: const EdgeInsets.only(bottom: AppSpace.md), child: shortcut),
      (context, index) {
        final loan = loans[index];
        final salary = loan.employeeSalary ?? 0;
        final overHalf = salary > 0 && loan.installmentAmount > salary / 2;
        return RequestCard(
          title: loan.employeeName ?? 'موظف',
          subtitle: loan.createdAt == null ? null : 'قُدّم ${Fmt.relative(loan.createdAt)}',
          tone: AppTone.warning,
          trailing: Text(Fmt.iqd(loan.amount), style: AppText.subtitle.copyWith(color: AppColors.brand)),
          actions: DecisionButtons(
            busy: busyKey == loan.id,
            approveLabel: 'اعتماد',
            confirmRejectTitle: 'رفض سلفة ${loan.employeeName ?? ''}؟',
            onApprove: () => onDecide(loan, true),
            onReject: () => onDecide(loan, false),
          ),
          children: [
            InfoRow(icon: Icons.payments_rounded, label: 'القسط الشهري', value: '${Fmt.iqd(loan.installmentAmount)} × ${Fmt.monthCount(loan.installmentCount)}'),
            if (salary > 0) ...[
              const SizedBox(height: AppSpace.sm),
              InfoRow(icon: Icons.account_balance_rounded, label: 'راتب الموظف', value: Fmt.iqd(salary)),
            ],
            if (overHalf) ...[
              const SizedBox(height: AppSpace.sm),
              Text('القسط أكثر من نصف الراتب — الاعتماد سيُرفض.', style: AppText.caption.copyWith(color: AppColors.warning)),
            ],
            if (loan.pledgeUrl != null && loan.pledgeUrl!.isNotEmpty) ...[
              const SizedBox(height: AppSpace.sm),
              InfoRow(icon: Icons.draw_rounded, label: 'التعهد الموقّع', value: 'فتح الصورة', url: loan.pledgeUrl),
            ],
          ],
        );
      },
    );
  }
}

class DevicesTab extends StatelessWidget {
  const DevicesTab({super.key, required this.devices, required this.onDecide, this.busyKey});

  final List<DeviceRequest> devices;
  final void Function(DeviceRequest request, bool approve) onDecide;
  final String? busyKey;

  @override
  Widget build(BuildContext context) {
    if (devices.isEmpty) return _empty('لا توجد طلبات أجهزة معلقة');

    return _list(devices.length, (context, index) {
      final device = devices[index];
      return RequestCard(
        title: device.employeeName,
        subtitle: 'يطلب الدخول من جهاز جديد',
        tone: AppTone.info,
        trailing: const StatusBadge('جهاز جديد', tone: AppTone.info, icon: Icons.phone_android_rounded),
        actions: DecisionButtons(
          busy: busyKey == device.id,
          approveLabel: 'اعتماد',
          confirmRejectTitle: 'رفض جهاز ${device.employeeName}؟',
          onApprove: () => onDecide(device, true),
          onReject: () => onDecide(device, false),
        ),
        children: [
          InfoRow(icon: Icons.phone_android_rounded, label: 'الطراز', value: device.model ?? 'غير معروف'),
          const SizedBox(height: AppSpace.sm),
          InfoRow(icon: Icons.memory_rounded, label: 'النظام', value: device.osVersion ?? 'غير معروف'),
          const SizedBox(height: AppSpace.sm),
          InfoRow(icon: Icons.fingerprint_rounded, label: 'معرّف الجهاز', value: device.deviceId, isCode: true),
        ],
      );
    });
  }
}

class SecurityTab extends StatelessWidget {
  const SecurityTab({super.key, required this.logs});

  final List<SecurityLog> logs;

  @override
  Widget build(BuildContext context) {
    if (logs.isEmpty) return _empty('لا توجد مخالفات أمنية', message: 'لم تُرصد محاولات موقع مزيّف أو خروج من النطاق.', icon: Icons.verified_user_rounded);

    return _list(logs.length, (context, index) {
      final log = logs[index];
      return RequestCard(
        title: log.employeeName,
        subtitle: Fmt.relative(log.timestamp),
        tone: AppTone.danger,
        highlight: true,
        trailing: const StatusBadge('تنبيه أمني', tone: AppTone.danger, icon: Icons.gpp_maybe_rounded),
        children: [
          InfoRow(icon: Icons.warning_amber_rounded, label: 'التفاصيل', value: log.details),
          const SizedBox(height: AppSpace.sm),
          InfoRow(icon: Icons.schedule_rounded, label: 'الوقت', value: '${Fmt.time(log.timestamp)} · ${Fmt.date(log.timestamp, withYear: true)}'),
          if (log.latLng.isNotEmpty) ...[
            const SizedBox(height: AppSpace.sm),
            InfoRow(icon: Icons.location_on_rounded, label: 'الإحداثيات', value: log.latLng, isCode: true),
          ],
        ],
      );
    });
  }
}

/// جدول الدوام الفعلي لموظف قرار من قائمة الجداول المحمّلة.
WorkScheduleModel? scheduleForDecision(
  PendingDecision item,
  List<WorkScheduleModel> schedules,
  String? departmentId,
) =>
    resolveWorkSchedule(
      employeeId: item.employeeId,
      departmentId: departmentId,
      branchId: item.branchId,
      schedules: schedules,
    );
