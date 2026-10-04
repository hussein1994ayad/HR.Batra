// أجزاء عرض شاشة الإجازات: كارت الرصيد المتبقي وكارت طلب الإجازة بالسجل.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/models/models.dart';
import '../../../../core/services/storage_links.dart';
import '../../../shared/ui/ui.dart';

/// رصيد الموظف: السنوية والمرضية لهذه السنة، والزمنيات لهذا الشهر (get_leave_balance).
/// يبرز المربع المطابق للنوع المختار.
class LeaveBalanceCard extends StatelessWidget {
  const LeaveBalanceCard({super.key, required this.balance, required this.isHourly, required this.leaveType});

  final LeaveBalance? balance;
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
                item('السنوية (${b.year})', b.annualLeft, b.annualEntitlement, 'يوم', !isHourly && leaveType == 'annual'),
                const SizedBox(width: AppSpace.sm),
                item('المرضية', b.sickLeft, b.sickEntitlement, 'يوم', !isHourly && leaveType == 'sick'),
                const SizedBox(width: AppSpace.sm),
                item('زمنيات الشهر', b.hourlyLeftHours, b.hourlyAllowanceHours, 'ساعة', isHourly),
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

/// تبويب "طلباتي": فلتر الحالة، وكروت الطلبات مع الإلغاء، وسحب للتحديث.
class LeaveHistoryList extends StatelessWidget {
  const LeaveHistoryList({
    super.key,
    required this.loading,
    required this.failed,
    required this.history,
    required this.filter,
    required this.onFilterChanged,
    required this.onRetry,
    required this.onRefresh,
    required this.onNewRequest,
    required this.typeLabel,
    required this.onCancel,
  });

  final bool loading;
  final bool failed;
  final List<LeaveRequestModel> history;

  /// 'all' أو حالة طلب.
  final String filter;
  final ValueChanged<String> onFilterChanged;
  final VoidCallback onRetry;
  final Future<void> Function() onRefresh;
  final VoidCallback onNewRequest;
  final String Function(String type) typeLabel;
  final void Function(LeaveRequestModel req) onCancel;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(padding: EdgeInsets.all(AppSpace.page), child: SkeletonList(count: 4));
    }
    if (failed && history.isEmpty) {
      return ErrorView(onRetry: onRetry);
    }
    final items = filter == 'all' ? history : history.where((r) => r.status == filter).toList();

    return RefreshIndicator.adaptive(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(AppSpace.page, AppSpace.md, AppSpace.page, AppSpace.x4),
        children: [
          AppChoiceChips<String>(
            scrollable: true,
            value: filter,
            onChanged: onFilterChanged,
            options: const [('all', 'الكل', null), ('pending', 'قيد المراجعة', null), ('approved', 'مقبولة', null), ('rejected', 'مرفوضة', null), ('cancelled', 'ملغاة', null)],
          ),
          const SizedBox(height: AppSpace.md),
          if (items.isEmpty)
            EmptyView(
              title: history.isEmpty ? 'ما عندك طلبات إجازة بعد' : 'لا توجد طلبات بهذه الحالة',
              message: history.isEmpty ? 'طلباتك وقرارات الإدارة تظهر هنا.' : null,
              icon: Icons.event_note_rounded,
              actionLabel: history.isEmpty ? 'قدّم طلب' : null,
              onAction: onNewRequest,
            )
          else
            for (var i = 0; i < items.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.md),
                child: FadeSlideIn(
                  index: i,
                  child: ContentWidth(
                    child: LeaveCard(req: items[i], typeName: typeLabel(items[i].leaveType), onCancel: onCancel),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

/// مرفق الطلب (صورة تقرير طبي أو مستند) مع زر الإزالة.
class LeaveAttachmentCard extends StatelessWidget {
  const LeaveAttachmentCard({super.key, required this.file, required this.onPick, required this.onRemove});

  final File? file;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onPick,
      tone: file != null ? AppTone.success : null,
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.md),
      child: Row(
        children: [
          Icon(
            file != null ? Icons.task_alt_rounded : Icons.add_photo_alternate_outlined,
            color: file != null ? AppColors.success : AppColors.brand,
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Text(
              file != null ? 'أُرفقت صورة ${file!.path.split(Platform.pathSeparator).last}' : 'أضف صورة تقرير طبي أو مستند',
              style: AppText.bodySm.copyWith(color: AppColors.textPrimary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (file != null)
            IconButton(
              tooltip: 'إزالة المرفق',
              onPressed: onRemove,
              icon: const Icon(Icons.close_rounded, color: AppColors.textMuted),
            ),
        ],
      ),
    );
  }
}
