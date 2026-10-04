// أجزاء عرض شاشة الإجازات: كارت الرصيد المتبقي وكارت طلب الإجازة بالسجل.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/models/models.dart';
import '../../../../core/services/storage_links.dart';
import '../../../shared/ui/ui.dart';

/// رصيد الموظف: السنوية والمرضية لهذه السنة، والزمنيات لهذا الشهر (get_leave_balance).
/// يبرز المربع المطابق للنوع المختار.
class LeaveBalanceCard extends StatelessWidget {
  const LeaveBalanceCard({super.key, required this.balance, required this.isHourly, required this.leaveType});

  final Map<String, dynamic>? balance;
  final bool isHourly;
  final String leaveType;

  static String _fmt(Object? v) {
    final n = (v as num?)?.toDouble() ?? 0;
    return n == n.roundToDouble() ? n.round().toString() : n.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    final b = balance;
    if (b == null) return const SizedBox.shrink();
    final annual = Map<String, dynamic>.from(b['annual'] as Map);
    final sick = Map<String, dynamic>.from(b['sick'] as Map);
    final hourly = Map<String, dynamic>.from(b['hourly'] as Map);

    Widget item(String label, Object? left, Object? total, String unit, bool active) => Expanded(
      child: Container(
        padding: const EdgeInsets.all(AppSpace.sm),
        decoration: BoxDecoration(
          color: active ? AppColors.brand.withValues(alpha: 0.12) : AppColors.surface2,
          borderRadius: AppRadius.control,
          border: Border.all(color: active ? AppColors.brand : AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppText.caption),
            const SizedBox(height: 2),
            Text('${_fmt(left)} $unit', style: AppText.label.copyWith(color: AppColors.textPrimary)),
            Text('من ${_fmt(total)}', style: AppText.caption),
          ],
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('رصيدك المتبقي', style: AppText.bodySm.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: AppSpace.sm),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                item('السنوية (${b['year']})', annual['left'], annual['entitlement'], 'يوم', !isHourly && leaveType == 'annual'),
                const SizedBox(width: AppSpace.sm),
                item('المرضية', sick['left'], sick['entitlement'], 'يوم', !isHourly && leaveType == 'sick'),
                const SizedBox(width: AppSpace.sm),
                item('زمنيات الشهر', hourly['left_hours'], hourly['allowance_hours'], 'ساعة', isHourly),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class LeaveCard extends StatelessWidget {
  const LeaveCard({super.key, required this.req, required this.typeName, this.onCancel});

  final LeaveRequestModel req;
  final String typeName;
  final void Function(LeaveRequestModel req)? onCancel;

  @override
  Widget build(BuildContext context) {
    final isHourly = req.isHourly;
    final start = req.startDate;
    final end = req.endDate;
    final reason = req.reason;
    final rejection = req.rejectionReason;
    final url = req.attachmentUrl;
    final period = isHourly
        ? '${Fmt.date(start)} · ${Fmt.timeOfDay(req.startHour)} - ${Fmt.timeOfDay(req.endHour)}'
        : Fmt.date(start) == Fmt.date(end)
        ? Fmt.dateWithDay(start)
        : '${Fmt.date(start)} إلى ${Fmt.date(end)}';

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ToneIcon(isHourly ? Icons.schedule_rounded : Icons.event_rounded, tone: AppTone.accent),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('إجازة $typeName${isHourly ? ' زمنية' : ''}', style: AppText.subtitle),
                    Text(period, style: AppText.caption),
                  ],
                ),
              ),
              StatusBadge.request(req.status),
            ],
          ),
          if (reason != null && reason.isNotEmpty) ...[
            const SizedBox(height: AppSpace.md),
            Text(reason, style: AppText.bodySm, maxLines: 3, overflow: TextOverflow.ellipsis),
          ],
          if (rejection != null && rejection.isNotEmpty) ...[
            const SizedBox(height: AppSpace.sm),
            Text('سبب الرفض: $rejection', style: AppText.bodySm.copyWith(color: AppColors.danger)),
          ],
          if (url != null && url.isNotEmpty) ...[
            const SizedBox(height: AppSpace.xs),
            AppButton.ghost(
              label: 'عرض المرفق',
              icon: Icons.attach_file_rounded,
              size: AppButtonSize.small,
              onPressed: () async {
                final uri = Uri.tryParse(await StorageLinks.resolve(url));
                if (uri != null && await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
            ),
          ],
          const SizedBox(height: AppSpace.xs),
          Row(
            children: [
              Expanded(child: Text('قُدّم ${Fmt.relative(req.createdAt)}', style: AppText.overline)),
              if (req.status == 'pending' && onCancel != null)
                AppButton.ghost(
                  label: 'إلغاء الطلب',
                  icon: Icons.close_rounded,
                  size: AppButtonSize.small,
                  onPressed: () => onCancel!(req),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
