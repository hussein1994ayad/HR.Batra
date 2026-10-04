// كارت يوم موظف بتقرير الحضور: الحالة، الملاحظة، وأوقات البصمة مع موقعها وزر التعديل.

import 'package:flutter/material.dart';

import '../../../../core/logic/attendance_report.dart';
import '../../../shared/ui/ui.dart';

class ReportRecordCard extends StatelessWidget {
  const ReportRecordCard({super.key, required this.row, required this.onOpenMap, required this.onEditTimes});

  final ReportRow row;
  final void Function(Object? lat, Object? lng) onOpenMap;
  final void Function(Map<String, dynamic> record) onEditTimes;

  @override
  Widget build(BuildContext context) {
    final r = row;
    final att = r.attendance;
    final tone = switch (r.status) {
      ReportStatus.present => AppTone.success,
      ReportStatus.late => AppTone.warning,
      ReportStatus.earlyLeave => AppTone.warning,
      ReportStatus.leave => AppTone.info,
      _ => AppTone.danger,
    };
    final name = r.employee.name;
    final showTimes = att != null && r.status.attended;

    return AppCard(
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AppAvatar(name: name, size: 40, tone: tone),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: AppText.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(
                      '${r.employee.code.isEmpty ? '' : '${r.employee.code} · '}${Fmt.dateWithDay(r.date)}',
                      style: AppText.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              StatusBadge(r.status.arabic, tone: tone, dot: true),
            ],
          ),
          if (r.note.isNotEmpty) ...[
            const SizedBox(height: AppSpace.sm),
            Row(
              children: [
                Icon(r.leave != null ? Icons.beach_access_rounded : Icons.info_outline_rounded, size: 16, color: AppColors.textMuted),
                const SizedBox(width: AppSpace.xs),
                Expanded(child: Text(r.note, style: AppText.bodySm)),
              ],
            ),
          ],
          if (showTimes) ...[
            const SizedBox(height: AppSpace.sm),
            Row(
              children: [
                Expanded(child: ReportTimeButton(icon: Icons.login_rounded, label: 'حضور', time: att.checkIn, onMap: () => onOpenMap(att.checkInLat, att.checkInLng))),
                const SizedBox(width: AppSpace.sm),
                Expanded(child: ReportTimeButton(icon: Icons.logout_rounded, label: 'انصراف', time: att.checkOut, onMap: () => onOpenMap(att.checkOutLat, att.checkOutLng))),
                IconButton(
                  tooltip: 'تعديل الأوقات',
                  icon: const Icon(Icons.edit_calendar_rounded, color: AppColors.brand),
                  onPressed: () => onEditTimes({
                    'id': att.id,
                    'employee_name': name,
                    'work_date': r.date.toIso8601String().split('T')[0],
                    'check_in': att.checkIn?.toIso8601String(),
                    'check_out': att.checkOut?.toIso8601String(),
                  }),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// وقت البصمة مع زر لفتح موقعها على الخريطة.
class ReportTimeButton extends StatelessWidget {
  const ReportTimeButton({super.key, required this.icon, required this.label, required this.time, required this.onMap});
  final IconData icon;
  final String label;
  final DateTime? time;
  final VoidCallback onMap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: time != null,
      label: '$label ${time == null ? 'غير مسجل' : Fmt.time(time)}',
      child: InkWell(
        onTap: time == null ? null : onMap,
        borderRadius: AppRadius.control,
        child: Container(
          constraints: const BoxConstraints(minHeight: AppSpace.touch),
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
          decoration: const BoxDecoration(color: AppColors.surface2, borderRadius: AppRadius.control),
          child: ExcludeSemantics(
            child: Row(
              children: [
                Icon(icon, size: 16, color: AppColors.textMuted),
                const SizedBox(width: AppSpace.xs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(label, style: AppText.overline),
                      Text(time == null ? '--:--' : Fmt.time(time), style: AppText.bodySm.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                if (time != null) const Icon(Icons.place_outlined, size: 16, color: AppColors.brand),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
