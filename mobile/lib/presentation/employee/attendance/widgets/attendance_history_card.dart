// سجل دوام الموظف لآخر 30 يوم: الحضور والانصراف والحالة لكل يوم.
// كان زر "سجل الدوام" بالرئيسية يفتح شاشة البصمة فقط، وماكو مكان يشوف بيه الموظف أيامه السابقة.

import 'package:flutter/material.dart';

import '../../../../core/services/supabase_service.dart';
import '../../../../core/utils/app_log.dart';
import '../../../../data/repositories/attendance_repository.dart';
import '../../../shared/ui/ui.dart';

class AttendanceHistoryCard extends StatefulWidget {
  const AttendanceHistoryCard({super.key, this.days = 30});
  final int days;

  @override
  State<AttendanceHistoryCard> createState() => _AttendanceHistoryCardState();
}

class _AttendanceHistoryCardState extends State<AttendanceHistoryCard> {
  List<Map<String, dynamic>>? _rows;
  bool _failed = false;
  bool _expanded = false;

  static const _collapsedCount = 5;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    final today = DateTime.now();
    try {
      final rows = await AttendanceRepository().fetchRecentHistory(user.id, today: today, days: widget.days);
      if (mounted) setState(() => _rows = rows);
    } catch (e) {
      appLog('تعذّر تحميل سجل الدوام: $e');
      if (mounted) setState(() => _failed = true);
    }
  }

  static DateTime? _parse(Object? v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

  static (String, AppTone) _status(Object? s) => switch (s) {
        'late' => ('متأخر', AppTone.warning),
        'absent' => ('غياب', AppTone.danger),
        'present' => ('حاضر', AppTone.success),
        _ => ('—', AppTone.neutral),
      };

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final visible = rows == null ? const <Map<String, dynamic>>[] : (_expanded ? rows : rows.take(_collapsedCount).toList());
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('سجل الدوام · آخر ${widget.days} يوم', style: AppText.label),
          const SizedBox(height: AppSpace.sm),
          if (_failed)
            const Text('تعذّر تحميل السجل، اسحب للتحديث.', style: AppText.caption)
          else if (rows == null)
            const Skeleton(height: 48, radius: AppRadius.sm)
          else if (rows.isEmpty)
            const Text('ماكو أيام مسجّلة بهذي الفترة.', style: AppText.caption)
          else ...[
            for (final r in visible)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
                child: Row(
                  children: [
                    Expanded(child: Text(Fmt.dateWithDay(DateTime.tryParse(r['work_date']?.toString() ?? '')), style: AppText.bodySm)),
                    Text(
                      '${r['check_in_time'] == null ? '--:--' : Fmt.time(_parse(r['check_in_time']))} ← ${r['check_out_time'] == null ? '--:--' : Fmt.time(_parse(r['check_out_time']))}',
                      style: AppText.caption,
                    ),
                    const SizedBox(width: AppSpace.sm),
                    () {
                      final (label, tone) = _status(r['status']);
                      return StatusBadge(label, tone: tone);
                    }(),
                  ],
                ),
              ),
            if (rows.length > _collapsedCount)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: AppButton.ghost(
                  label: _expanded ? 'عرض أقل' : 'عرض الكل (${rows.length})',
                  size: AppButtonSize.small,
                  onPressed: () => setState(() => _expanded = !_expanded),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
