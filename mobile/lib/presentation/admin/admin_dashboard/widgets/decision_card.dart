import 'package:flutter/material.dart';

import '../../../../core/logic/attendance_rules.dart';
import '../../../../core/logic/decision_reasons.dart';
import '../../../../core/models/models.dart';
import '../../../../core/utils/arabic_format.dart';
import '../../../../core/utils/input_formatters.dart';
import '../../../shared/ui/ui.dart';
import '../../../shared/widgets/info_row.dart';
import 'request_card.dart';

/// [amount] = مبلغ كتبه المدير بدل المحسوب (null = المبلغ المحسوب).
typedef DecisionCallback = void Function({required bool deduct, required String reason, double? amount});

/// المبلغ اللي ينرسل ويا القرار: null إذا الحقل فارغ أو نفس المحسوب (السيرفر يبقى على حسابه).
double? editedAmount(String text, double computed) {
  if (text.trim().isEmpty) return null;
  final value = parseThousands(text);
  return value.round() == computed.round() ? null : value;
}

/// قرار خصم/إعفاء لسجل غياب أو تأخير أو خروج مبكر. المبلغ يحسبه محرّك الرواتب في السيرفر
/// (أجر اليوم = الراتب ÷ 30، والدقائق بأجر دقيقة دوام الموظف) ويظهر للمدير، ويكدر يعدّله قبل الخصم
/// (مثل: نص يوم بدل يوم). حقل السبب يحتفظ بما كتبه المدير عند إعادة بناء القائمة، وتحته ملاحظات جاهزة
/// تنضغط (مثل: نسي البصمة وهو مداوم). الإعفاء ما يوصل بيه إشعار للموظف.
class DecisionCard extends StatefulWidget {
  const DecisionCard({super.key, required this.item, required this.schedule, required this.onDecide, this.busy = false});

  final PendingDecision item;
  final WorkScheduleModel? schedule;
  final bool busy;
  final DecisionCallback onDecide;

  @override
  State<DecisionCard> createState() => _DecisionCardState();
}

class _DecisionCardState extends State<DecisionCard> {
  late final int _missedMinutes;
  late final TextEditingController _reason;
  late final TextEditingController _amount;

  double get _computed => widget.item.engineAmount ?? 0;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    final isEarly = item.status == 'half_day' || item.status == 'early_leave';
    _missedMinutes = item.engineMinutes ??
        (item.status == 'late' && item.checkInTime != null
            ? lateMinutes(item.checkInTime!, widget.schedule)
            : isEarly && item.checkOutTime != null
                ? earlyLeaveMinutes(item.checkOutTime!, widget.schedule)
                : 0);
    _reason = TextEditingController(
      text: _missedMinutes > 0
          ? '${item.status == 'late' ? 'تأخير' : item.status == 'missing_punch' ? 'بدون بصمة انصراف' : 'خروج مبكر'}: ${formatDurationArabic(_missedMinutes)}'
          : '',
    );
    _amount = TextEditingController(text: _computed > 0 ? formatThousands(_computed) : '');
  }

  @override
  void dispose() {
    _reason.dispose();
    _amount.dispose();
    super.dispose();
  }

  String _reasonOr(String fallback) => _reason.text.trim().isEmpty ? fallback : _reason.text.trim();

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final tone = item.status == 'absent' ? AppTone.danger : AppTone.warning;
    final isMissingPunch = item.status == 'missing_punch' || (item.status == 'half_day' && item.checkInTime == null);
    final amount = _computed;
    // بصمة ناقصة بخصم مقترح (دقائق الدوام بعد آخر تواجد مسجّل) = قرار خصم مثل التأخير؛ بدون مبلغ = تأكيد بس
    final confirmOnly = isMissingPunch && amount <= 0 && _amount.text.trim().isEmpty;

    return RequestCard(
      title: item.employeeName,
      subtitle: Fmt.dateWithDay(DateTime.tryParse(item.workDate)),
      tone: tone,
      trailing: StatusBadge(item.statusArabic, tone: tone, dot: true),
      actions: DecisionButtons(
        busy: widget.busy,
        approveLabel: confirmOnly ? 'تأكيد' : 'تطبيق الخصم',
        rejectLabel: 'إعفاء',
        onApprove: () => widget.onDecide(
          deduct: true,
          reason: _reasonOr('تم الخصم بناءً على تعليمات الإدارة'),
          amount: editedAmount(_amount.text, amount),
        ),
        onReject: () => widget.onDecide(
          deduct: false,
          reason: _reasonOr('تم الإعفاء بناءً على تعليمات الإدارة'),
        ),
      ),
      children: [
        if (_missedMinutes > 0) ...[
          InfoRow(
            icon: Icons.hourglass_bottom_rounded,
            label: item.status == 'late' ? 'مدة التأخير' : isMissingPunch ? 'بعد آخر تواجد مسجّل' : 'خروج مبكر',
            value: formatDurationArabic(_missedMinutes),
          ),
          const SizedBox(height: AppSpace.sm),
        ],
        if (item.status == 'late' && item.checkInTime != null) ...[
          InfoRow(icon: Icons.login_rounded, label: 'وقت البصمة', value: Fmt.time(item.checkInTime)),
          const SizedBox(height: AppSpace.sm),
        ],
        InfoRow(
          icon: Icons.payments_outlined,
          label: 'الخصم المحسوب',
          value: amount > 0
              ? Fmt.iqd(amount)
              : isMissingPunch
                  ? 'بدون خصم'
                  : 'يُحسب تلقائياً من الراتب',
        ),
        const SizedBox(height: AppSpace.sm),
        AppTextField(
          controller: _amount,
          label: 'مبلغ الخصم (د.ع)',
          hint: 'فارغ = المبلغ المحسوب',
          helper: 'تكدر تعدّل المبلغ قبل الخصم (مثلاً نص يوم). فارغ = المبلغ المحسوب.',
          icon: Icons.edit_outlined,
          keyboardType: TextInputType.number,
          inputFormatters: [DotThousandsSeparatorInputFormatter()],
          textDirection: TextDirection.ltr,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppSpace.sm),
        AppTextField(controller: _reason, label: 'السبب', hint: 'سبب الخصم أو الإعفاء'),
        const SizedBox(height: AppSpace.sm),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.xs,
          children: [
            for (final r in [...kExcuseReasons, ...kDeductReasons])
              ActionChip(
                label: Text(r),
                onPressed: widget.busy ? null : () => setState(() => _reason.text = r),
              ),
          ],
        ),
      ],
    );
  }
}
