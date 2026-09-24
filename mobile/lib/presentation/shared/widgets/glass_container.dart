import 'package:flutter/material.dart';

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
    this.blur = 4.0,
    this.opacity = 0.05,
    this.borderRadius = 24.0,
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
    
    // الألوان الافتراضية عالية الأداء لنمط الزجاج المعتم والخفيف جداً على المعالج
    final effectiveOpacity = opacity <= 0.1 
        ? (isDark ? 0.75 : 0.85) 
        : opacity;
    
    final baseColor = color ?? (isDark ? const Color(0xFF1E293B) : Colors.white);
    final finalBorderColor = borderColor ?? 
        (isDark ? Colors.white.withAlpha(25) : Colors.black.withAlpha(15));

    final effectiveShadow = boxShadow ?? [
      BoxShadow(
        color: isDark 
            ? Colors.black.withValues(alpha: 0.2) 
            : Colors.black.withValues(alpha: 0.04),
        blurRadius: 16,
        offset: const Offset(0, 4),
      ),
    ];

    return Container(
      width: width,
      height: height,
      margin: margin,
      padding: padding,
      alignment: alignment,
      decoration: BoxDecoration(
        color: baseColor.withValues(alpha: effectiveOpacity),
        borderRadius: BorderRadius.circular(borderRadius),
        border: border ?? Border.all(
          color: finalBorderColor,
        ),
        boxShadow: effectiveShadow,
      ),
      child: child,
    );
  }
}

