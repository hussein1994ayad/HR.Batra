import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

/// Page background: a flat canvas with two soft, static brand glows.
///
/// The glows are painted once inside a [RepaintBoundary] so scrolling content
/// never repaints them. Page content is kept inside the safe area and centred
/// with a maximum width, so layouts stay readable on tablets, foldables and
/// in landscape.
class GlassBackground extends StatelessWidget {
  final Widget child;
  final bool showGlows;

  /// Whether to pad the content above the system gesture/home indicator.
  /// Screens with their own bottom navigation bar turn this off so the bar
  /// can extend to the screen edge and handle the inset itself.
  final bool safeBottom;

  const GlassBackground({
    super.key,
    required this.child,
    this.showGlows = true,
    this.safeBottom = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
      body: Stack(
        children: [
          if (showGlows)
            Positioned.fill(
              child: RepaintBoundary(
                child: IgnorePointer(
                  child: CustomPaint(painter: _GlowPainter(isDark: isDark)),
                ),
              ),
            ),
          SafeArea(
            bottom: safeBottom,
            child: Center(
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: AppTheme.maxContentWidth),
                child: child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlowPainter extends CustomPainter {
  final bool isDark;

  const _GlowPainter({required this.isDark});

  void _glow(Canvas canvas, Offset center, double radius, Color color) {
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [color, color.withValues(alpha: 0)],
        ).createShader(rect),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide * 0.9;
    _glow(
      canvas,
      Offset(size.width * 0.9, -r * 0.15),
      r,
      AppTheme.brand.withValues(alpha: isDark ? 0.20 : 0.10),
    );
    _glow(
      canvas,
      Offset(size.width * 0.05, size.height * 0.55),
      r * 0.85,
      AppTheme.violet.withValues(alpha: isDark ? 0.12 : 0.06),
    );
  }

  @override
  bool shouldRepaint(_GlowPainter oldDelegate) => oldDelegate.isDark != isDark;
}
