// نافذة تعديل وقت الحضور والانصراف لسجل بتقرير الحضور.

import 'package:flutter/material.dart';

import '../../../shared/ui/ui.dart';
import 'report_record_card.dart';

TimeOfDay? _timeOf(Object? v) {
  if (v == null) return null;
  final dt = DateTime.tryParse(v.toString())?.toLocal();
  if (dt != null) return TimeOfDay(hour: dt.hour, minute: dt.minute);
  final p = v.toString().split(':');
  if (p.length < 2) return null;
  final h = int.tryParse(p[0]);
  final m = int.tryParse(p[1]);
  return h == null || m == null ? null : TimeOfDay(hour: h, minute: m);
}

/// ترجع الوقتين الجديدين إذا ضغط "حفظ"، أو null إذا سكّر النافذة.
Future<({TimeOfDay? checkIn, TimeOfDay? checkOut})?> showEditTimesSheet(BuildContext context, ReportTimeEdit record) async {
  TimeOfDay? newCheckIn = _timeOf(record.checkIn);
  TimeOfDay? newCheckOut = _timeOf(record.checkOut);
  String label(TimeOfDay? t) => t == null ? 'لم يُحدد' : Fmt.time(DateTime(2000, 1, 1, t.hour, t.minute));

  final save = await showAppSheet<bool>(
    context,
    title: 'تعديل أوقات ${record.employeeName}',
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('يوم ${Fmt.dateWithDay(DateTime.tryParse(record.workDate))}', style: AppText.bodySm),
          const SizedBox(height: AppSpace.md),
          Row(
            children: [
              Expanded(
                child: AppPickerField(
                  label: 'الحضور',
                  icon: Icons.login_rounded,
                  value: label(newCheckIn),
                  onTap: () async {
                    final t = await showTimePicker(context: ctx, initialTime: newCheckIn ?? const TimeOfDay(hour: 8, minute: 0));
                    if (t != null) setSheet(() => newCheckIn = t);
                  },
                ),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: AppPickerField(
                  label: 'الانصراف',
                  icon: Icons.logout_rounded,
                  value: label(newCheckOut),
                  onTap: () async {
                    final t = await showTimePicker(context: ctx, initialTime: newCheckOut ?? const TimeOfDay(hour: 16, minute: 0));
                    if (t != null) setSheet(() => newCheckOut = t);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.xl),
          AppButton(label: 'حفظ', icon: Icons.check_rounded, expand: true, onPressed: () => Navigator.pop(ctx, true)),
        ],
      ),
    ),
  );
  return save == true ? (checkIn: newCheckIn, checkOut: newCheckOut) : null;
}
