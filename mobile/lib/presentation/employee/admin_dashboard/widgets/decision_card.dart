import 'package:flutter/material.dart';

import '../../../../core/logic/attendance_rules.dart';
import '../../../../core/models/models.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/arabic_format.dart';
import '../../../../core/utils/input_formatters.dart';
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

  InputDecoration _field(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white38),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      );

  String _reasonOr(String fallback) => _reason.text.trim().isEmpty ? fallback : _reason.text.trim();

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final color = item.status == 'absent' ? AppTheme.dangerRed : AppTheme.warningOrange;
    const inputStyle = TextStyle(fontFamily: 'Cairo', color: Colors.white, fontSize: 12);

    return RequestCard(
      title: item.employeeName,
      accent: color,
      trailing: StatusBadge(item.statusArabic, color: color),
      actions: DecisionButtons(
        busy: widget.busy,
        approveLabel: 'تطبيق خصم',
        rejectLabel: 'إعفاء / مسامحة',
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
        InfoRow(icon: Icons.calendar_month_rounded, label: 'تاريخ الدوام', value: item.workDate),
        if (_missedMinutes > 0) ...[
          const SizedBox(height: 10),
          InfoRow(
            icon: Icons.hourglass_bottom_rounded,
            label: item.status == 'late' ? 'المدة المفقودة (التأخير)' : 'المدة المفقودة (خروج مبكر)',
            value: formatDurationArabic(_missedMinutes),
          ),
        ],
        if (item.status == 'late' && item.checkInTime != null) ...[
          const SizedBox(height: 10),
          InfoRow(icon: Icons.watch_later_rounded, label: 'توقيت البصمة (دخول)', value: formatTime12h(item.checkInTime)),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: TextField(
                controller: _amount,
                keyboardType: TextInputType.number,
                inputFormatters: [DotThousandsSeparatorInputFormatter()],
                style: inputStyle,
                decoration: _field('مبلغ الخصم (د.ع)'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: TextField(controller: _reason, style: inputStyle, decoration: _field('سبب الخصم...')),
            ),
          ],
        ),
      ],
    );
  }
}
