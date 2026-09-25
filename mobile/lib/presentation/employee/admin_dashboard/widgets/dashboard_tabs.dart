import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/constants.dart';
import '../../../../core/design/design.dart';
import '../../../../core/logic/attendance_rules.dart';
import '../../../../core/models/models.dart';
import '../../../../core/routes/app_router.dart';
import '../../../../core/utils/arabic_format.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/info_row.dart';
import 'decision_card.dart';
import 'request_card.dart';

const _listPadding = EdgeInsets.fromLTRB(16, 12, 16, 24);

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
      return const EmptyState(
        'يرجى تحديد تاريخ أولاً لعرض القرارات المعلقة',
        icon: Icons.calendar_today_rounded,
        tone: AppTone.warning,
      );
    }
    if (decisions.isEmpty) return const EmptyState('لا توجد قرارات غياب أو تأخير معلقة لليوم المختار');

    return ListView.builder(
      padding: _listPadding,
      itemCount: decisions.length,
      itemBuilder: (context, index) {
        final item = decisions[index];
        return DecisionCard(
          key: ValueKey(item.key),
          item: item,
          schedule: scheduleFor(item),
          busy: busyKey == item.key,
          onDecide: ({required deduct, required reason, required amount}) =>
              onDecide(item, deduct: deduct, reason: reason, amount: amount),
        );
      },
    );
  }
}

class LeavesTab extends StatelessWidget {
  const LeavesTab({super.key, required this.leaves, required this.onDecide, this.busyKey});

  final List<LeaveRequestModel> leaves;
  final void Function(LeaveRequestModel leave, bool approve) onDecide;
  final String? busyKey;

  String _period(LeaveRequestModel l) => l.isHourly
      ? '${formatDateSlash(l.startDate)} (${l.startHour ?? '--'} - ${l.endHour ?? '--'})'
      : 'من ${formatDateSlash(l.startDate)} إلى ${formatDateSlash(l.endDate)}';

  @override
  Widget build(BuildContext context) {
    if (leaves.isEmpty) return const EmptyState('لا توجد طلبات إجازة معلقة حالياً');

    return ListView.builder(
      padding: _listPadding,
      itemCount: leaves.length,
      itemBuilder: (context, index) {
        final leave = leaves[index];
        return RequestCard(
          title: leave.employeeName ?? 'موظف غير معروف',
          accent: AppColors.brand,
          trailing: StatusBadge(leave.typeArabic, color: AppColors.brand),
          actions: DecisionButtons(
            busy: busyKey == leave.id,
            onApprove: () => onDecide(leave, true),
            onReject: () => onDecide(leave, false),
          ),
          children: [
            InfoRow(icon: Icons.calendar_month_rounded, label: 'الفترة الزمنية', value: _period(leave)),
            const SizedBox(height: 10),
            InfoRow(icon: Icons.comment_rounded, label: 'سبب الإجازة', value: leave.reason ?? 'بدون سبب مذكور'),
            if (leave.hasAttachment) ...[
              const SizedBox(height: 10),
              InfoRow(
                icon: Icons.attachment_rounded,
                label: 'المرفق المرفوع',
                value: 'يوجد مستند رسمي مرفق',
                url: leave.attachmentUrl,
              ),
            ],
          ],
        );
      },
    );
  }
}

class LoansTab extends StatelessWidget {
  const LoansTab({super.key, required this.loans, required this.onDecide, this.busyKey});

  final List<LoanModel> loans;
  final void Function(LoanModel loan, bool approve) onDecide;
  final String? busyKey;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: _listPadding,
      children: [
        const _LoansLedgerShortcut(),
        if (loans.isEmpty)
          const EmptyState('لا توجد طلبات سلف جديدة معلقة حالياً')
        else
          for (final loan in loans)
            RequestCard(
              title: loan.employeeName ?? 'موظف غير معروف',
              accent: AppColors.accent,
              trailing: Text(
                AppConstants.formatMoney(loan.amount),
                style: const TextStyle(color: AppColors.brand, fontWeight: FontWeight.w900, fontSize: 14, fontFamily: 'Cairo'),
              ),
              actions: DecisionButtons(
                busy: busyKey == loan.id,
                onApprove: () => onDecide(loan, true),
                onReject: () => onDecide(loan, false),
              ),
              children: [
                InfoRow(icon: Icons.schedule_rounded, label: 'عدد الأقساط', value: '${loan.installmentCount} أشهر متتالية'),
                const SizedBox(height: 10),
                InfoRow(
                  icon: Icons.price_change_rounded,
                  label: 'القسط الشهري',
                  value: '${AppConstants.formatMoney(loan.installmentAmount)} / الشهر',
                ),
                if (loan.pledgeUrl != null && loan.pledgeUrl!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  InfoRow(
                    icon: Icons.draw_rounded,
                    label: 'تعهد السلفة الموقّع',
                    value: 'رابط التعهد الإلزامي المرفق',
                    url: loan.pledgeUrl,
                  ),
                ],
              ],
            ),
      ],
    );
  }
}

/// بطاقة الانتقال إلى سجل المستلفين وكشوف Excel.
class _LoansLedgerShortcut extends StatelessWidget {
  const _LoansLedgerShortcut();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push(AppRoutes.adminLoans),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.brandStrong.withValues(alpha: 0.35), AppColors.accent.withValues(alpha: 0.25)],
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.brand.withValues(alpha: 0.4), width: 1.5),
          boxShadow: [BoxShadow(color: AppColors.brand.withValues(alpha: 0.12), blurRadius: 16, spreadRadius: 1)],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.brandStrong, borderRadius: BorderRadius.circular(14)),
              child: const Icon(Icons.table_chart_rounded, color: AppColors.textPrimary, size: 24),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'سجل ومتابعة المستلفين وكشوف Excel',
                    style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textPrimary),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'عرض مبالغ السلف، الأقساط المسددة والمتبقية، صور التعهدات، وتصدير كشف Excel احترافي',
                    style: TextStyle(fontFamily: 'Cairo', fontSize: 10, color: AppColors.textSecondary, height: 1.3),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward_ios_rounded, color: AppColors.brand, size: 16),
          ],
        ),
      ),
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
    if (devices.isEmpty) return const EmptyState('لا توجد طلبات اعتماد أجهزة معلقة حالياً');

    return ListView.builder(
      padding: _listPadding,
      itemCount: devices.length,
      itemBuilder: (context, index) {
        final device = devices[index];
        return RequestCard(
          title: device.employeeName,
          accent: AppColors.accent,
          actions: DecisionButtons(
            busy: busyKey == device.id,
            approveLabel: 'اعتماد الجهاز',
            rejectLabel: 'رفض الطلب',
            onApprove: () => onDecide(device, true),
            onReject: () => onDecide(device, false),
          ),
          children: [
            InfoRow(icon: Icons.phone_android_rounded, label: 'طراز الهاتف الجديد', value: device.model ?? 'هاتف غير معروف'),
            const SizedBox(height: 10),
            InfoRow(icon: Icons.adb_rounded, label: 'إصدار نظام التشغيل', value: device.osVersion ?? 'نظام غير معروف'),
            const SizedBox(height: 10),
            InfoRow(icon: Icons.fingerprint_rounded, label: 'معرف الهاتف الفريد', value: device.deviceId, isCode: true),
          ],
        );
      },
    );
  }
}

class SecurityTab extends StatelessWidget {
  const SecurityTab({super.key, required this.logs});

  final List<SecurityLog> logs;

  @override
  Widget build(BuildContext context) {
    if (logs.isEmpty) return const EmptyState('سجل الأمان خالٍ من الخروقات اليوم');

    return ListView.builder(
      padding: _listPadding,
      itemCount: logs.length,
      itemBuilder: (context, index) {
        final log = logs[index];
        return RequestCard(
          title: log.employeeName,
          accent: AppColors.danger,
          opacity: 0.12,
          glow: true,
          trailing: const StatusBadge('خطر أمني', color: AppColors.danger),
          children: [
            InfoRow(icon: Icons.warning_amber_rounded, label: 'تفاصيل الخرق المكتشف', value: log.details),
            const SizedBox(height: 10),
            InfoRow(
              icon: Icons.schedule_rounded,
              label: 'توقيت المحاولة',
              value: '${formatTime12h(log.timestamp)} بتاريخ ${formatDateSlash(log.timestamp)}',
            ),
            if (log.latLng.isNotEmpty) ...[
              const SizedBox(height: 10),
              InfoRow(icon: Icons.location_on_rounded, label: 'الإحداثيات المرصودة', value: log.latLng, isCode: true),
            ],
          ],
        );
      },
    );
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
