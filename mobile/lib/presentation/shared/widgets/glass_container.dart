import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

/// Surface card used across the app.
///
/// It used to be a frosted-glass panel built on [BackdropFilter], which forced
/// a full-screen blur pass for every card and made scrolling janky on
/// mid-range phones. It is now a solid, layered surface with a hairline
/// border. The constructor is unchanged so existing screens keep working:
/// [opacity] now controls how much the surface is lifted above the default
/// card colour, and [blur] is ignored.
class GlassContainer extends StatelessWidget {
  final Widget child;
  final double blur;
  final double opacity;
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
    this.blur = 0,
    this.opacity = 0.05,
    this.borderRadius = AppTheme.radiusLg,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final Color fill;
    if (color != null) {
      fill = color!;
    } else if (isDark) {
      // Higher "opacity" values used to mean a more prominent glass panel,
      // so lift the surface slightly for those.
      final lift = ((opacity - 0.05).clamp(0.0, 0.15)) * 0.5;
      fill = Color.alphaBlend(
        Colors.white.withValues(alpha: lift),
        AppTheme.darkSurface,
      );
    } else {
      fill = AppTheme.lightSurface;
    }

    final radius = BorderRadius.circular(borderRadius);

    return Container(
      width: width,
      height: height,
      margin: margin,
      padding: padding,
      alignment: alignment,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: radius,
        border: border ??
            Border.all(
              color: borderColor ??
                  (isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
            ),
        boxShadow: boxShadow ??
            (isDark
                ? null
                : const [
                    BoxShadow(
                      color: Color(0x0F0F172A),
                      blurRadius: 16,
                      offset: Offset(0, 6),
                    ),
                  ]),
      ),
      child: child,
    );
  }
}
