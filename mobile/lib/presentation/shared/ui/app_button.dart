import 'package:flutter/material.dart';

import '../../../core/design/design.dart';

enum AppButtonVariant { primary, secondary, ghost, dangerGhost, danger, success, warning }

enum AppButtonSize { small, medium, large }

/// زر موحّد: أساسي / ثانوي / شفاف / خطر / نجاح. يعرض مؤشر تحميل ويمنع الضغط المكرر.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.variant = AppButtonVariant.primary,
    this.size = AppButtonSize.medium,
    this.loading = false,
    this.expand = false,
    this.haptic = true,
  });

  const AppButton.secondary({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.size = AppButtonSize.medium,
    this.loading = false,
    this.expand = false,
    this.haptic = false,
  }) : variant = AppButtonVariant.secondary;

  const AppButton.ghost({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.size = AppButtonSize.medium,
    this.loading = false,
    this.expand = false,
    this.haptic = false,
  }) : variant = AppButtonVariant.ghost;

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final bool loading;
  final bool expand;
  final bool haptic;

  (Color bg, Color fg, BorderSide side) get _colors => switch (variant) {
        AppButtonVariant.primary => (AppColors.brand, AppColors.onBrand, BorderSide.none),
        AppButtonVariant.secondary => (AppColors.surface2, AppColors.textPrimary, const BorderSide(color: AppColors.borderStrong)),
        AppButtonVariant.ghost => (Colors.transparent, AppColors.brand, BorderSide.none),
        AppButtonVariant.dangerGhost => (Colors.transparent, AppColors.danger, BorderSide.none),
        AppButtonVariant.danger => (AppColors.danger, AppColors.onStatus, BorderSide.none),
        AppButtonVariant.success => (AppColors.success, AppColors.onStatus, BorderSide.none),
        AppButtonVariant.warning => (AppColors.warning, AppColors.onStatus, BorderSide.none),
      };

  double get _height => switch (size) {
        AppButtonSize.small => 40,
        AppButtonSize.medium => AppSpace.touch,
        AppButtonSize.large => 56,
      };

  @override
  Widget build(BuildContext context) {
    final (bg, fg, side) = _colors;
    final enabled = onPressed != null && !loading;
    final textStyle = size == AppButtonSize.small ? AppText.label.copyWith(fontSize: 13) : AppText.label.copyWith(fontSize: size == AppButtonSize.large ? 16 : 15);
    final iconSize = size == AppButtonSize.small ? 18.0 : 20.0;

    final child = AnimatedSwitcher(
      duration: AppMotion.of(context, AppMotion.fast),
      child: loading
          ? SizedBox(
              key: const ValueKey('loading'),
              width: iconSize,
              height: iconSize,
              child: CircularProgressIndicator(strokeWidth: 2.2, color: fg),
            )
          : Row(
              key: const ValueKey('label'),
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[Icon(icon, size: iconSize), const SizedBox(width: AppSpace.sm)],
                Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
              ],
            ),
    );

    final button = TextButton(
      onPressed: enabled
          ? () {
              if (haptic) AppHaptics.submit();
              onPressed!();
            }
          : null,
      style: TextButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
        disabledBackgroundColor: variant == AppButtonVariant.ghost || variant == AppButtonVariant.dangerGhost ? Colors.transparent : AppColors.surface2,
        disabledForegroundColor: loading ? fg : AppColors.textDisabled,
        minimumSize: Size(size == AppButtonSize.small ? 0 : 64, _height),
        padding: EdgeInsets.symmetric(horizontal: size == AppButtonSize.small ? AppSpace.md : AppSpace.xl),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.control, side: side),
        textStyle: textStyle,
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
      child: child,
    );
    return Semantics(
      button: true,
      enabled: enabled,
      label: loading ? '$label، جاري التنفيذ' : null,
      child: expand ? SizedBox(width: double.infinity, child: button) : button,
    );
  }
}

/// زر أيقونة دائري بمنطقة لمس 48 وتلميح للقارئ الصوتي.
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color = AppColors.textPrimary,
    this.background = AppColors.surface2,
    this.badge,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color color;
  final Color background;
  final int? badge;

  @override
  Widget build(BuildContext context) {
    Widget ic = Icon(icon, color: color, size: 22);
    if (badge != null && badge! > 0) {
      ic = Badge(label: Text(badge! > 99 ? '99+' : '$badge'), child: ic);
    }
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(backgroundColor: background, minimumSize: const Size.square(AppSpace.touch)),
      icon: ic,
    );
  }
}
