// =========================================================================
// HR Pro — عناصر التعاميم والمجازين (مشتركة بين الرئيسية وصفحة التعاميم)
// =========================================================================
// التعميم: بطاقة بتدرّج لوني خفيف، أيقونة، نص واضح، وشريط يبيّن كم بقي من مدة
// عرضه. في الرئيسية تُعرض كشرائح تُسحب أفقياً مع نقاط التنقل.
// المجازون: صورة بحلقة ملوّنة (يومية بنفسجي، زمنية أزرق)، الاسم، الفرع، ومتى يعود.
// =========================================================================

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

/// نسبة ما مضى من مدة عرض التعميم (0..1)، أو null بدون نهاية.
double? announcementProgress(AnnouncementModel a, {DateTime? now}) {
  final starts = a.shownFrom;
  final ends = a.endsAt;
  if (starts == null || ends == null || !ends.isAfter(starts)) return null;
  final t = (now ?? DateTime.now()).difference(starts).inMinutes / ends.difference(starts).inMinutes;
  return t.clamp(0.0, 1.0);
}

/// "ينتهي اليوم" / "ينتهي غداً" / "باقي 5 أيام" / "ساري حتى 28 أيلول"
String? announcementRemaining(AnnouncementModel a, {DateTime? now}) {
  final ends = a.endsAt;
  if (ends == null) return null;
  final today = now ?? DateTime.now();
  final days = DateTime(ends.year, ends.month, ends.day).difference(DateTime(today.year, today.month, today.day)).inDays;
  if (days <= 0) return 'ينتهي اليوم';
  if (days == 1) return 'ينتهي غداً';
  if (days <= 10) return 'باقي $days أيام';
  return 'ساري حتى ${Fmt.date(ends)}';
}

/// بطاقة تعميم: أيقونة، العنوان، النص، متى نُشر، وشريط المدة المتبقية.
class AnnouncementCard extends StatelessWidget {
  const AnnouncementCard(this.a, {super.key, this.maxLines = 4, this.expand = false});
  final AnnouncementModel a;
  final int? maxLines;

  /// يملأ ارتفاع الحاوية (شرائح الرئيسية)
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final pinned = a.isPinned;
    final tone = pinned ? AppTone.warning : AppTone.brand;
    final title = a.title;
    final body = a.body;
    final progress = announcementProgress(a);
    final remaining = announcementRemaining(a);

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: tone.color.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: tone.color.withValues(alpha: 0.28)),
              ),
              child: Icon(pinned ? Icons.push_pin_rounded : Icons.campaign_rounded, color: tone.color, size: 22),
            ),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppText.titleSm.copyWith(fontSize: 16), maxLines: 2, overflow: TextOverflow.ellipsis),
                  Text(
                    '${pinned ? 'مثبّت · ' : ''}${Fmt.relative(a.shownFrom)}',
                    style: AppText.caption.copyWith(color: pinned ? AppColors.warning : AppColors.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (body.isNotEmpty) ...[
          const SizedBox(height: AppSpace.md),
          Text(body, style: AppText.body.copyWith(fontSize: 14, color: AppColors.textSecondary), maxLines: maxLines, overflow: maxLines == null ? null : TextOverflow.ellipsis),
        ],
        if (expand) const Spacer() else const SizedBox(height: AppSpace.md),
        if (remaining != null)
          Row(
            children: [
              Icon(Icons.timelapse_rounded, size: 14, color: tone.color),
              const SizedBox(width: AppSpace.xs),
              Text(remaining, style: AppText.caption.copyWith(color: AppColors.textSecondary, fontWeight: FontWeight.w700)),
              if (progress != null) ...[
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: ClipRRect(
                    borderRadius: AppRadius.pill,
                    child: LinearProgressIndicator(
                      value: 1 - progress,
                      minHeight: 4,
                      backgroundColor: AppColors.surface3,
                      valueColor: AlwaysStoppedAnimation(tone.color),
                    ),
                  ),
                ),
              ],
            ],
          ),
      ],
    );

    return Semantics(
      container: true,
      label: 'تعميم: $title',
      child: Container(
        padding: const EdgeInsets.all(AppSpace.lg),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: tone.color.withValues(alpha: 0.22)),
          // توهّج ناعم من زاوية الأيقونة (بداية السطر = اليمين بالعربي)
          gradient: RadialGradient(
            center: Directionality.of(context) == TextDirection.rtl ? const Alignment(0.95, -1) : const Alignment(-0.95, -1),
            radius: 1.25,
            colors: [Color.alphaBlend(tone.color.withValues(alpha: pinned ? 0.14 : 0.16), AppColors.surface1), AppColors.surface1],
          ),
        ),
        child: content,
      ),
    );
  }
}

/// شرائح التعاميم في الرئيسية: تُسحب أفقياً، مع نقاط تبيّن الشريحة الحالية.
class AnnouncementCarousel extends StatefulWidget {
  const AnnouncementCarousel({super.key, required this.items, this.onOpen});
  final List<AnnouncementModel> items;
  final VoidCallback? onOpen;

  @override
  State<AnnouncementCarousel> createState() => _AnnouncementCarouselState();
}

class _AnnouncementCarouselState extends State<AnnouncementCarousel> {
  final _controller = PageController(viewportFraction: 0.92);
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.5);
    final height = 196 * scale;
    if (items.length == 1) {
      return GestureDetector(onTap: widget.onOpen, child: SizedBox(height: height, child: AnnouncementCard(items.first, maxLines: 3, expand: true)));
    }
    return Column(
      children: [
        SizedBox(
          height: height,
          child: PageView.builder(
            controller: _controller,
            padEnds: false,
            itemCount: items.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsetsDirectional.only(end: AppSpace.md),
              child: GestureDetector(onTap: widget.onOpen, child: AnnouncementCard(items[i], maxLines: 3, expand: true)),
            ),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < items.length; i++)
              AnimatedContainer(
                duration: AppMotion.normal,
                curve: AppMotion.standard,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == _page ? 20 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: i == _page ? AppColors.brand : AppColors.surface3,
                  borderRadius: AppRadius.pill,
                ),
              ),
          ],
        ),
      ],
    );
  }
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
