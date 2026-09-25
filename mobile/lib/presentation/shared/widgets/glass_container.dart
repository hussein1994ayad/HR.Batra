// =========================================================================
// HR Pro — GlassContainer (للتوافق مع الشاشات القديمة)
// =========================================================================
// صار بطاقة مسطّحة من رموز التصميم (بدون ضبابية ولا ظلال ثقيلة) حتى يكون
// التمرير سريعاً. للشاشات الجديدة استعمل AppCard من shared/ui.
// =========================================================================

import 'package:flutter/material.dart';

import '../../../core/design/design.dart';

class GlassContainer extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final Color? borderColor;
  final Color? color;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;
  final BoxBorder? border;
  final List<BoxShadow>? boxShadow;
  final AlignmentGeometry? alignment;

  const GlassContainer({
    super.key,
    required this.child,
    this.borderRadius = AppRadius.md,
    this.borderColor,
    this.color,
    this.padding,
    this.margin,
    this.width,
    this.height,
    this.border,
    this.boxShadow,
    this.alignment,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      margin: margin,
      padding: padding,
      alignment: alignment,
      decoration: BoxDecoration(
        color: color == null ? AppColors.surface1 : Color.alphaBlend(color!.withValues(alpha: 0.14), AppColors.surface1),
        borderRadius: BorderRadius.circular(borderRadius.clamp(0, AppRadius.lg)),
        border: border ?? Border.all(color: borderColor ?? AppColors.border),
        boxShadow: boxShadow,
      ),
      child: child,
    );
  }
}
