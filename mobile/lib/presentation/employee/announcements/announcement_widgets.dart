// =========================================================================
// HR Pro — عناصر التعاميم والمجازين (مشتركة بين الرئيسية وصفحة التعاميم)
// =========================================================================

import 'package:flutter/material.dart';

import '../../shared/ui/ui.dart';

DateTime? _date(Object? v) => DateTime.tryParse(v?.toString() ?? '');

/// "حتى 28 أيلول" / "آخر يوم اليوم" / "10:00 ص – 12:00 م"
String onLeaveUntil(Map<String, dynamic> p, {DateTime? now}) {
  if (p['is_hourly'] == true) {
    return '${Fmt.timeOfDay(p['start_hour']?.toString())} – ${Fmt.timeOfDay(p['end_hour']?.toString())}';
  }
  final to = _date(p['to_date']);
  if (to == null) return 'مجاز اليوم';
  final today = now ?? DateTime.now();
  if (to.year == today.year && to.month == today.month && to.day == today.day) return 'آخر يوم اليوم';
  return 'حتى ${Fmt.date(to)}';
}

/// بطاقة تعميم: العنوان، النص، متى نُشر، وحتى متى يبقى.
class AnnouncementCard extends StatelessWidget {
  const AnnouncementCard(this.a, {super.key, this.maxLines = 4});
  final Map<String, dynamic> a;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final pinned = a['is_pinned'] == true;
    final body = (a['content'] ?? a['body'] ?? '').toString();
    final ends = _date(a['ends_at']);
    return AppCard(
      tone: pinned ? AppTone.warning : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (pinned) ...[const Icon(Icons.push_pin_rounded, size: 16, color: AppColors.warning), const SizedBox(width: AppSpace.xs)],
              Expanded(child: Text((a['title'] ?? 'إعلان إداري').toString(), style: AppText.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: AppSpace.sm),
              Text(Fmt.relative(_date(a['starts_at'] ?? a['created_at'])), style: AppText.caption),
            ],
          ),
          if (body.isNotEmpty) ...[
            const SizedBox(height: AppSpace.xs),
            Text(body, style: AppText.bodySm, maxLines: maxLines, overflow: maxLines == null ? null : TextOverflow.ellipsis),
          ],
          if (ends != null) ...[
            const SizedBox(height: AppSpace.sm),
            Row(
              children: [
                const Icon(Icons.schedule_rounded, size: 14, color: AppColors.textMuted),
                const SizedBox(width: AppSpace.xs),
                Text('ساري حتى ${Fmt.date(ends)}', style: AppText.caption),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// شريط أفقي بالمجازين الآن: الصورة، الاسم، الفرع، وحتى متى.
class OnLeaveStrip extends StatelessWidget {
  const OnLeaveStrip({super.key, required this.people});
  final List<Map<String, dynamic>> people;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return SizedBox(
      height: 172 * scale.clamp(1.0, 1.4),
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
  final Map<String, dynamic> p;

  @override
  Widget build(BuildContext context) {
    final name = (p['full_name'] ?? 'موظف').toString();
    final hourly = p['is_hourly'] == true;
    return SizedBox(
      width: 136,
      child: AppCard(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Column(
          children: [
            AppAvatar(name: name, url: p['avatar_url']?.toString(), size: 52, tone: hourly ? AppTone.info : AppTone.accent),
            const SizedBox(height: AppSpace.sm),
            Text(name, style: AppText.label, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
            Text((p['branch_name'] ?? '—').toString(), style: AppText.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
            const Spacer(),
            StatusBadge(onLeaveUntil(p), tone: hourly ? AppTone.info : AppTone.accent, icon: hourly ? Icons.schedule_rounded : Icons.beach_access_rounded),
          ],
        ),
      ),
    );
  }
}

/// سطر مجاز في صفحة التعاميم.
class OnLeaveTile extends StatelessWidget {
  const OnLeaveTile(this.p, {super.key});
  final Map<String, dynamic> p;

  @override
  Widget build(BuildContext context) {
    final name = (p['full_name'] ?? 'موظف').toString();
    final hourly = p['is_hourly'] == true;
    return AppListTile(
      leading: AppAvatar(name: name, url: p['avatar_url']?.toString(), tone: hourly ? AppTone.info : AppTone.accent),
      title: name,
      subtitle: '${p['branch_name'] ?? '—'} · ${hourly ? 'زمنية ${onLeaveUntil(p)}' : onLeaveUntil(p)}',
      trailing: ToneIcon(hourly ? Icons.schedule_rounded : Icons.beach_access_rounded, tone: hourly ? AppTone.info : AppTone.accent, size: 34),
    );
  }
}
