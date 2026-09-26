import 'package:flutter/material.dart';

import '../../../core/design/design.dart';
import 'app_badges.dart';
import 'app_card.dart';

/// رقم يتحرك بنعومة عند تغيّره (يحترم "تقليل الحركة").
class AnimatedNumber extends StatelessWidget {
  const AnimatedNumber(this.value, {super.key, this.style = AppText.number, this.format});

  final num value;
  final TextStyle style;
  final String Function(num v)? format;

  @override
  Widget build(BuildContext context) {
    final fmt = format ?? formatInt;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value.toDouble()),
      duration: AppMotion.of(context, AppMotion.slow),
      curve: AppMotion.standard,
      builder: (_, v, __) => Text(fmt(v), style: style, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }

  static String formatInt(num v) => Fmt.iqd(v, withUnit: false);
}

/// مربع مؤشر (KPI): عنوان صغير + رقم كبير + أيقونة ملوّنة.
class KpiTile extends StatelessWidget {
  const KpiTile({super.key, required this.label, required this.value, this.icon, this.tone = AppTone.brand, this.hint, this.onTap, this.format});

  final String label;
  final num value;
  final IconData? icon;
  final AppTone tone;
  final String? hint;
  final VoidCallback? onTap;
  final String Function(num v)? format;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpace.md + 2),
      semanticLabel: '$label: ${(format ?? AnimatedNumber.formatInt)(value)}',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                if (icon != null) ...[ToneIcon(icon!, tone: tone, size: 32), const SizedBox(width: AppSpace.sm)],
                Expanded(child: Text(label, style: AppText.caption.copyWith(color: AppColors.textSecondary), maxLines: 2, overflow: TextOverflow.ellipsis)),
              ],
            ),
            const SizedBox(height: AppSpace.sm),
            AnimatedNumber(value, format: format, style: AppText.number.copyWith(color: tone == AppTone.neutral ? AppColors.textPrimary : tone.color)),
            if (hint != null) Text(hint!, style: AppText.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

/// مخطط أعمدة بسيط بدون مكتبات (مثلاً الحضور آخر 7 أيام).
class MiniBarChart extends StatelessWidget {
  const MiniBarChart({super.key, required this.values, this.labels, this.height = 96, this.tone = AppTone.brand, this.highlightIndex, this.semanticLabel});

  final List<num> values;
  final List<String>? labels;
  final double height;
  final AppTone tone;
  final int? highlightIndex;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final maxV = values.isEmpty ? 1 : values.reduce((a, b) => a > b ? a : b).clamp(1, double.infinity);
    return Semantics(
      label: semanticLabel,
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: height,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < values.length; i++)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: values[i] / maxV),
                          duration: AppMotion.of(context, AppMotion.slow),
                          curve: AppMotion.emphasized,
                          builder: (_, f, __) => FractionallySizedBox(
                            heightFactor: f.clamp(0.04, 1.0),
                            alignment: Alignment.bottomCenter,
                            child: Container(
                              decoration: BoxDecoration(
                                color: i == (highlightIndex ?? values.length - 1) ? tone.color : tone.color.withValues(alpha: 0.35),
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(6), bottom: Radius.circular(2)),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (labels != null) ...[
              const SizedBox(height: AppSpace.xs),
              Row(
                children: [
                  for (final l in labels!)
                    Expanded(child: Text(l, textAlign: TextAlign.center, style: AppText.overline, maxLines: 1, overflow: TextOverflow.clip)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// شريط تقدم أفقي بزوايا دائرية (سداد السلفة، رصيد الإجازات...).
class AppProgressBar extends StatelessWidget {
  const AppProgressBar({super.key, required this.value, this.tone = AppTone.brand, this.height = 8});

  final double value;
  final AppTone tone;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: AppRadius.pill,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: value.clamp(0, 1)),
        duration: AppMotion.of(context, AppMotion.slow),
        curve: AppMotion.standard,
        builder: (_, v, __) => LinearProgressIndicator(value: v, minHeight: height, color: tone.color, backgroundColor: AppColors.surface3),
      ),
    );
  }
}

/// صف "عنوان ← قيمة" للتفاصيل (كشف راتب، تفاصيل سلفة...).
class KeyValueRow extends StatelessWidget {
  const KeyValueRow(this.label, this.value, {super.key, this.valueColor, this.bold = false, this.icon});

  final String label;
  final String value;
  final Color? valueColor;
  final bool bold;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[Icon(icon, size: 18, color: AppColors.textMuted), const SizedBox(width: AppSpace.sm)],
          Expanded(child: Text(label, style: AppText.bodySm)),
          const SizedBox(width: AppSpace.md),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: (bold ? AppText.subtitle : AppText.body.copyWith(fontSize: 14)).copyWith(
                color: valueColor ?? AppColors.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
