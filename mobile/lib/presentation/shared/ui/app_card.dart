import 'package:flutter/material.dart';

import '../../../core/design/design.dart';

/// بطاقة مسطّحة موحّدة: سطح + حد خفيف + زوايا 16. قابلة للضغط اختيارياً.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpace.lg),
    this.margin,
    this.onTap,
    this.onLongPress,
    this.color = AppColors.surface1,
    this.borderColor = AppColors.border,
    this.radius = AppRadius.card,
    this.tone,
    this.semanticLabel,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color color;
  final Color borderColor;
  final BorderRadius radius;

  /// إذا حُدد: خلفية خفيفة بلون الحالة وحد بنفس اللون.
  final AppTone? tone;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final bg = tone == null ? color : Color.alphaBlend(tone!.container.withValues(alpha: 0.55), AppColors.surface1);
    final border = tone == null ? borderColor : tone!.color.withValues(alpha: 0.28);
    Widget content = Padding(padding: padding, child: child);
    if (onTap != null || onLongPress != null) {
      content = InkWell(onTap: onTap, onLongPress: onLongPress, borderRadius: radius, child: content);
    }
    return Semantics(
      container: true,
      button: onTap != null,
      label: semanticLabel,
      child: Container(
        margin: margin,
        decoration: BoxDecoration(color: bg, borderRadius: radius, border: Border.all(color: border)),
        child: Material(type: MaterialType.transparency, borderRadius: radius, clipBehavior: Clip.antiAlias, child: content),
      ),
    );
  }
}
