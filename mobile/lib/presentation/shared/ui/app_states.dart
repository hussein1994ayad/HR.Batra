import 'package:flutter/material.dart';

import '../../../core/design/design.dart';
import 'app_button.dart';

/// حالة فارغة ودّية: أيقونة + عنوان + شرح + زر اختياري.
class EmptyView extends StatelessWidget {
  const EmptyView({
    super.key,
    required this.title,
    this.message,
    this.icon = Icons.inbox_rounded,
    this.tone = AppTone.brand,
    this.actionLabel,
    this.onAction,
    this.compact = false,
  });

  final String title;
  final String? message;
  final IconData icon;
  final AppTone tone;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: AppSpace.xxl, vertical: compact ? AppSpace.xl : AppSpace.x4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: compact ? 56 : 72,
              height: compact ? 56 : 72,
              decoration: BoxDecoration(color: tone.container, shape: BoxShape.circle),
              child: Icon(icon, color: tone.color, size: compact ? 28 : 34),
            ),
            const SizedBox(height: AppSpace.lg),
            Text(title, style: AppText.subtitle, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: AppSpace.xs),
              Text(message!, style: AppText.bodySm, textAlign: TextAlign.center),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpace.lg),
              AppButton.secondary(label: actionLabel!, onPressed: onAction, size: AppButtonSize.small),
            ],
          ],
        ),
      ),
    );
  }
}

/// حالة خطأ مع زر "إعادة المحاولة".
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, this.title = 'تعذّر تحميل البيانات', this.message = 'تأكد من اتصالك بالإنترنت ثم حاول مرة ثانية.', this.onRetry, this.compact = false});

  final String title;
  final String message;
  final VoidCallback? onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return EmptyView(
      title: title,
      message: message,
      icon: Icons.cloud_off_rounded,
      tone: AppTone.danger,
      actionLabel: onRetry == null ? null : 'إعادة المحاولة',
      onAction: onRetry,
      compact: compact,
    );
  }
}

/// مربع هيكلي نابض (skeleton) — بديل مؤشر الدوران أثناء التحميل.
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, this.width, this.height = 14, this.radius = AppRadius.xs});

  final double? width;
  final double height;
  final double radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reduced(context)) {
      _c.value = 0.5;
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.45, end: 1).animate(_c),
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(widget.radius)),
      ),
    );
  }
}

/// قائمة هيكلية جاهزة تشبه بطاقات القوائم.
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.count = 5, this.itemHeight = 76, this.header = false});

  final int count;
  final double itemHeight;
  final bool header;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'جاري التحميل',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (header) ...[
              const Row(children: [Expanded(child: Skeleton(height: 88, radius: AppRadius.md)), SizedBox(width: AppSpace.md), Expanded(child: Skeleton(height: 88, radius: AppRadius.md))]),
              const SizedBox(height: AppSpace.xl),
            ],
            for (var i = 0; i < count; i++) ...[
              Container(
                height: itemHeight,
                padding: const EdgeInsets.all(AppSpace.md),
                decoration: BoxDecoration(color: AppColors.surface1, borderRadius: AppRadius.card, border: Border.all(color: AppColors.border)),
                child: const Row(
                  children: [
                    Skeleton(width: 44, height: 44, radius: AppRadius.sm),
                    SizedBox(width: AppSpace.md),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [Skeleton(width: 140), SizedBox(height: AppSpace.sm), Skeleton(width: 90, height: 10)],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpace.md),
            ],
          ],
        ),
      ),
    );
  }
}

/// ظهور تدريجي متتابع لعناصر القائمة (يُلغى مع "تقليل الحركة").
class FadeSlideIn extends StatelessWidget {
  const FadeSlideIn({super.key, required this.child, this.index = 0});

  final Widget child;
  final int index;

  @override
  Widget build(BuildContext context) {
    if (AppMotion.reduced(context)) return child;
    final delay = (index.clamp(0, 8)) * 40;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 220 + delay),
      curve: Interval(delay / (220 + delay), 1, curve: AppMotion.standard),
      builder: (_, t, c) => Opacity(opacity: t, child: Transform.translate(offset: Offset(0, (1 - t) * 12), child: c)),
      child: child,
    );
  }
}
