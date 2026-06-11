import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class GlassBackground extends StatelessWidget {
  final Widget child;
  final bool showGlows;

  const GlassBackground({
    super.key,
    required this.child,
    this.showGlows = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // الألوان الافتراضية للخلفية والنيونات طبقاً لوضعية النهار والليل
    final bgColor = isDark ? AppTheme.darkBg : AppTheme.lightBg;
    
    return Scaffold(
      backgroundColor: bgColor,
      body: Stack(
        children: [
          // 1. الدوائر المضيئة النيونية في الخلفية (Neon Blobs)
          if (showGlows)
            RepaintBoundary(
              child: Stack(
                children: [
                  // Blob 1: Teal/Cyan (أعلى اليمين)
                  Positioned(
                    top: -100,
                    right: -50,
                    child: Container(
                      width: 300,
                      height: 300,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            (isDark ? AppTheme.primaryTeal : AppTheme.primaryTealLight).withOpacity(isDark ? 0.3 : 0.15),
                            (isDark ? AppTheme.primaryTeal : AppTheme.primaryTealLight).withOpacity(0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                  
                  // Blob 2: Indigo (منتصف اليسار)
                  Positioned(
                    top: MediaQuery.of(context).size.height * 0.4,
                    left: -100,
                    child: Container(
                      width: 320,
                      height: 320,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            AppTheme.accentIndigo.withOpacity(isDark ? 0.25 : 0.12),
                            AppTheme.accentIndigo.withOpacity(0.0),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Blob 3: Pink/Purple (أسفل اليمين)
                  Positioned(
                    bottom: -50,
                    right: -50,
                    child: Container(
                      width: 280,
                      height: 280,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            AppTheme.neonPink.withOpacity(isDark ? 0.18 : 0.08),
                            AppTheme.neonPink.withOpacity(0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          
          // 2. المحتوى الفعلي الممرر فوق الخلفية
          SafeArea(
            child: child,
          ),
        ],
      ),
    );
  }
}
