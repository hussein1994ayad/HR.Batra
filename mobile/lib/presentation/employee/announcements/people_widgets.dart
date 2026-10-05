// المجازون الآن والمتأخرون اليوم (الرئيسية ولوحة التعاميم):
// صورة بحلقة ملوّنة (يومية بنفسجي، زمنية أزرق، تأخير برتقالي)، الاسم، الفرع، ومتى يعود أو مدة التأخير.

import 'package:flutter/material.dart';

import '../../../core/models/models.dart';
import '../../shared/ui/ui.dart';

bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// "حتى 28 أيلول" / "آخر يوم اليوم" / "10:00 ص – 12:00 م"
String onLeaveUntil(OnLeavePerson p, {DateTime? now}) {
  if (p.isHourly) {
    return '${Fmt.timeOfDay(p.startHour)} – ${Fmt.timeOfDay(p.endHour)}';
  }
  final to = p.toDate;
  if (to == null) return 'مجاز اليوم';
  final today = now ?? DateTime.now();
  if (_sameDay(to, today)) return 'آخر يوم اليوم';
  return 'حتى ${Fmt.date(to)}';
}

/// "يعود غداً" / "يعود بعد 3 أيام" (للإجازة اليومية فقط)
String? onLeaveReturn(OnLeavePerson p, {DateTime? now}) {
  if (p.isHourly) return null;
  final to = p.toDate;
  if (to == null) return null;
  final today = now ?? DateTime.now();
  final days = DateTime(to.year, to.month, to.day).difference(DateTime(today.year, today.month, today.day)).inDays + 1;
  if (days <= 1) return 'يعود غداً';
  if (days == 2) return 'يعود بعد يومين';
  return 'يعود بعد $days أيام';
}

/// صورة المجاز داخل حلقة ملوّنة مع شارة نوع الإجازة.
class _LeaveAvatar extends StatelessWidget {
  const _LeaveAvatar(this.p, {this.size = 60, this.toneOverride, this.icon});
  final PersonCardData p;
  final double size;

  /// للمتأخرين: لون وأيقونة مختلفة
  final AppTone? toneOverride;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final hourly = p is OnLeavePerson && (p as OnLeavePerson).isHourly;
    final tone = toneOverride ?? (hourly ? AppTone.info : AppTone.accent);
    final name = p.fullName;
    return SizedBox(
      width: size + 8,
      height: size + 8,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.all(2.5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: SweepGradient(colors: [tone.color, tone.color.withValues(alpha: 0.35), tone.color]),
            ),
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.surface1),
              child: AppAvatar(name: name, url: p.avatarUrl, size: size - 1, tone: tone),
            ),
          ),
          PositionedDirectional(
            end: -2,
            bottom: -2,
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: tone.color,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.surface1, width: 2.5),
              ),
              child: Icon(icon ?? (hourly ? Icons.schedule_rounded : Icons.beach_access_rounded), size: 13, color: AppColors.onStatus),
            ),
          ),
        ],
      ),
    );
  }
}

/// شريط أفقي بالمجازين الآن: الصورة، الاسم، الفرع، وحتى متى.
class OnLeaveStrip extends StatelessWidget {
  const OnLeaveStrip({super.key, required this.people});
  final List<OnLeavePerson> people;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return SizedBox(
      height: 196 * scale.clamp(1.0, 1.4),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: people.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpace.md),
        itemBuilder: (context, i) => FadeSlideIn(index: i, child: _OnLeaveCard(people[i])),
      ),
    );
  }
}

class _OnLeaveCard extends StatelessWidget {
  const _OnLeaveCard(this.p);
  final OnLeavePerson p;

  @override
  Widget build(BuildContext context) {
    final name = p.fullName;
    final hourly = p.isHourly;
    final tone = hourly ? AppTone.info : AppTone.accent;
    final back = onLeaveReturn(p);
    return Semantics(
      container: true,
      label: '$name مجاز ${onLeaveUntil(p)}',
      child: Container(
        width: 150,
        padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.lg, AppSpace.md, AppSpace.md),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: tone.color.withValues(alpha: 0.2)),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [tone.color.withValues(alpha: 0.12), AppColors.surface1],
          ),
        ),
        child: Column(
          children: [
            _LeaveAvatar(p),
            const SizedBox(height: AppSpace.sm),
            Text(name, style: AppText.label, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
            Text(p.branchLabel, style: AppText.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
            const Spacer(),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
              decoration: BoxDecoration(color: tone.container, borderRadius: AppRadius.pill),
              child: Text(
                hourly ? 'زمنية حتى ${Fmt.timeOfDay(p.endHour)}' : (back ?? onLeaveUntil(p)),
                style: AppText.caption.copyWith(color: tone.color, fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// سطر مجاز في صفحة التعاميم.
class OnLeaveTile extends StatelessWidget {
  const OnLeaveTile(this.p, {super.key});
  final OnLeavePerson p;

  @override
  Widget build(BuildContext context) {
    final name = p.fullName;
    final hourly = p.isHourly;
    final tone = hourly ? AppTone.info : AppTone.accent;
    final back = onLeaveReturn(p);
    return AppListTile(
      leading: _LeaveAvatar(p, size: 40),
      title: name,
      subtitle: '${p.branchLabel} · ${hourly ? 'زمنية ${onLeaveUntil(p)}' : onLeaveUntil(p)}',
      trailing: back == null ? null : StatusBadge(back, tone: tone),
    );
  }
}

// ---------------------------------------------------------------------------
// المتأخرون اليوم
// ---------------------------------------------------------------------------

/// "40 دقيقة" / "1 س 15 د"
String lateDuration(LatePerson p, {bool short = false}) {
  final mins = p.lateMinutes;
  if (mins >= 60) return '${mins ~/ 60} س ${mins % 60} د';
  return short ? '$mins د' : '$mins دقيقة';
}

String _punchTime(LatePerson p) => Fmt.time(p.checkInTime);

/// شريط أفقي بالمتأخرين اليوم: الصورة، الاسم، الفرع، مدة التأخير ووقت البصمة.
class LateStrip extends StatelessWidget {
  const LateStrip({super.key, required this.people});
  final List<LatePerson> people;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return SizedBox(
      height: 214 * scale.clamp(1.0, 1.4),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: people.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpace.md),
        itemBuilder: (context, i) => FadeSlideIn(index: i, child: _LateCard(people[i])),
      ),
    );
  }
}

class _LateCard extends StatelessWidget {
  const _LateCard(this.p);
  final LatePerson p;

  @override
  Widget build(BuildContext context) {
    const tone = AppTone.warning;
    final name = p.fullName;
    return Semantics(
      container: true,
      label: '$name متأخر ${lateDuration(p)}، البصمة ${_punchTime(p)}',
      child: Container(
        width: 150,
        padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.lg, AppSpace.md, AppSpace.md),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: tone.color.withValues(alpha: 0.2)),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [tone.color.withValues(alpha: 0.10), AppColors.surface1],
          ),
        ),
        child: Column(
          children: [
            _LeaveAvatar(p, toneOverride: tone, icon: Icons.alarm_rounded),
            const SizedBox(height: AppSpace.sm),
            Text(name, style: AppText.label, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
            Text(p.branchLabel, style: AppText.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
            const Spacer(),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
              decoration: BoxDecoration(color: tone.container, borderRadius: AppRadius.pill),
              child: Text(
                'تأخير ${lateDuration(p)}',
                style: AppText.caption.copyWith(color: tone.color, fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: AppSpace.xs),
            Text('البصمة ${_punchTime(p)}', style: AppText.caption, maxLines: 1),
          ],
        ),
      ),
    );
  }
}

/// سطر متأخر في صفحة التعاميم.
class LateTile extends StatelessWidget {
  const LateTile(this.p, {super.key});
  final LatePerson p;

  @override
  Widget build(BuildContext context) {
    final name = p.fullName;
    return AppListTile(
      leading: _LeaveAvatar(p, size: 40, toneOverride: AppTone.warning, icon: Icons.alarm_rounded),
      title: name,
      subtitle: '${p.branchLabel} · البصمة ${_punchTime(p)}',
      trailing: StatusBadge(lateDuration(p, short: true), tone: AppTone.warning),
    );
  }
}
