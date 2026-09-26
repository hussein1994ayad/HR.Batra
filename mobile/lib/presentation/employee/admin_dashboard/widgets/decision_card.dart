import 'package:flutter/material.dart';


import '../../../../core/logic/attendance_rules.dart';
import '../../../../core/models/models.dart';
import '../../../../core/utils/arabic_format.dart';
import '../../../../core/utils/input_formatters.dart';
import '../../../shared/ui/ui.dart';
import '../../../shared/widgets/info_row.dart';
import 'request_card.dart';

typedef DecisionCallback = void Function({required bool deduct, required String reason, required double amount});

/// قرار خصم/إعفاء لسجل غياب أو تأخير. الحقول تحتفظ بما كتبه المدير عند إعادة
/// بناء القائمة (كانت المتحكمات تُنشأ داخل itemBuilder فتضيع مع كل setState).
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
  late final TextEditingController _amount;
  late final TextEditingController _reason;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _missedMinutes = item.status == 'late' && item.checkInTime != null
        ? lateMinutes(item.checkInTime!, widget.schedule)
        : item.status == 'half_day' && item.checkOutTime != null
            ? earlyLeaveMinutes(item.checkOutTime!, widget.schedule)
            : 0;
    final suggested = suggestedPenalty(item.status, _missedMinutes);
    _amount = TextEditingController(text: suggested > 0 ? formatThousands(suggested) : '');
    _reason = TextEditingController(
      text: _missedMinutes > 0 ? 'تأخير مفقود: ${formatDurationArabic(_missedMinutes)}' : '',
    );
  }

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  String _reasonOr(String fallback) => _reason.text.trim().isEmpty ? fallback : _reason.text.trim();

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final tone = item.status == 'absent' ? AppTone.danger : AppTone.warning;

    return RequestCard(
      title: item.employeeName,
      subtitle: Fmt.dateWithDay(DateTime.tryParse(item.workDate)),
      tone: tone,
      trailing: StatusBadge(item.statusArabic, tone: tone, dot: true),
      actions: DecisionButtons(
        busy: widget.busy,
        approveLabel: 'تطبيق الخصم',
        rejectLabel: 'إعفاء',
        onApprove: () => widget.onDecide(
          deduct: true,
          reason: _reasonOr('تم الخصم بناءً على تعليمات الإدارة'),
          amount: parseThousands(_amount.text),
        ),
        onReject: () => widget.onDecide(
          deduct: false,
          reason: _reasonOr('تم الإعفاء بناءً على تعليمات الإدارة'),
          amount: 0,
        ),
      ),
      children: [
        if (_missedMinutes > 0) ...[
          InfoRow(
            icon: Icons.hourglass_bottom_rounded,
            label: item.status == 'late' ? 'مدة التأخير' : 'خروج مبكر',
            value: formatDurationArabic(_missedMinutes),
          ),
          const SizedBox(height: AppSpace.sm),
        ],
        if (item.status == 'late' && item.checkInTime != null) ...[
          InfoRow(icon: Icons.login_rounded, label: 'وقت البصمة', value: Fmt.time(item.checkInTime)),
          const SizedBox(height: AppSpace.sm),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: AppTextField(
                controller: _amount,
                label: 'الخصم (د.ع)',
                hint: '0',
                keyboardType: TextInputType.number,
                inputFormatters: [DotThousandsSeparatorInputFormatter()],
              ),
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(flex: 3, child: AppTextField(controller: _reason, label: 'السبب', hint: 'سبب الخصم')),
          ],
        ),
      ],
    );
  }
}
