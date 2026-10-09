// =========================================================================
// HR Pro — عناصر التعاميم والمجازين (مشتركة بين الرئيسية وصفحة التعاميم)
// =========================================================================
// التعميم: بطاقة بتدرّج لوني خفيف، أيقونة، نص واضح، وشريط يبيّن كم بقي من مدة
// عرضه. في الرئيسية تُعرض كشرائح تُسحب أفقياً مع نقاط التنقل.
// المجازون والمتأخرون في people_widgets.dart (يُصدَّر من هنا).
// =========================================================================

import 'package:flutter/material.dart';

import '../../../core/models/models.dart';
import '../../shared/ui/ui.dart';

export 'people_widgets.dart';

/// نسبة ما مضى من مدة عرض التعميم (0..1)، أو null بدون نهاية.
double? announcementProgress(AnnouncementModel a, {DateTime? now}) {
  final starts = a.shownFrom;
  final ends = a.endsAt;
  if (starts == null || ends == null || !ends.isAfter(starts)) return null;
  final t = (now ?? DateTime.now()).difference(starts).inMinutes / ends.difference(starts).inMinutes;
  return t.clamp(0.0, 1.0);
}

/// "ينتهي اليوم" / "ينتهي غداً" / "باقي 5 أيام" / "ساري حتى 28/9"
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
