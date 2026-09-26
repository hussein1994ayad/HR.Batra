import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../core/design/design.dart';
import 'app_button.dart';

/// نافذة سفلية موحّدة مع عنوان، تتمدد مع الكيبورد وتبقى داخل عرض مريح على التابلت.
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  String? title,
  bool scrollable = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: AppColors.surface1,
    builder: (ctx) {
      final content = Padding(
        padding: EdgeInsets.fromLTRB(AppSpace.xl, 0, AppSpace.xl, AppSpace.xl + MediaQuery.viewInsetsOf(ctx).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              Semantics(header: true, child: Text(title, style: AppText.title)),
              const SizedBox(height: AppSpace.lg),
            ],
            Builder(builder: builder),
          ],
        ),
      );
      return scrollable ? SingleChildScrollView(child: content) : content;
    },
  );
}

/// تأكيد قبل فعل مهم. على iOS يظهر بشكل Cupertino تلقائياً.
Future<bool> showAppConfirm(
  BuildContext context, {
  required String title,
  String? message,
  String confirmLabel = 'تأكيد',
  String cancelLabel = 'إلغاء',
  bool destructive = false,
}) async {
  final platform = Theme.of(context).platform;
  if (platform == TargetPlatform.iOS || platform == TargetPlatform.macOS) {
    final r = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(title),
        content: message == null ? null : Text(message),
        actions: [
          CupertinoDialogAction(onPressed: () => Navigator.pop(ctx, false), child: Text(cancelLabel)),
          CupertinoDialogAction(
            isDestructiveAction: destructive,
            isDefaultAction: !destructive,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return r ?? false;
  }
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actionsPadding: const EdgeInsets.fromLTRB(AppSpace.lg, 0, AppSpace.lg, AppSpace.lg),
      actions: [
        AppButton.ghost(label: cancelLabel, onPressed: () => Navigator.pop(ctx, false)),
        AppButton(
          label: confirmLabel,
          variant: destructive ? AppButtonVariant.danger : AppButtonVariant.primary,
          onPressed: () => Navigator.pop(ctx, true),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// رسائل سريعة موحّدة، مع زر "تراجع" اختياري.
abstract final class AppSnack {
  static void show(BuildContext context, String message, {AppTone tone = AppTone.neutral, String? actionLabel, VoidCallback? onAction, IconData? icon}) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    if (tone == AppTone.danger) AppHaptics.error();
    final ic = icon ??
        switch (tone) {
          AppTone.success => Icons.check_circle_rounded,
          AppTone.danger => Icons.error_rounded,
          AppTone.warning => Icons.warning_amber_rounded,
          _ => Icons.info_rounded,
        };
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(ic, color: tone == AppTone.neutral ? AppColors.textSecondary : tone.color, size: 20),
              const SizedBox(width: AppSpace.md),
              Expanded(child: Text(message)),
            ],
          ),
          action: actionLabel == null ? null : SnackBarAction(label: actionLabel, onPressed: onAction ?? () {}),
          duration: Duration(seconds: actionLabel == null ? 3 : 5),
        ),
      );
  }

  static void success(BuildContext context, String message) => show(context, message, tone: AppTone.success);
  static void error(BuildContext context, String message) => show(context, message, tone: AppTone.danger);
  static void info(BuildContext context, String message) => show(context, message, tone: AppTone.info);

  /// رسالة مع زر تراجع — يُنفَّذ [onUndo] إذا ضغطه المستخدم.
  static void undo(BuildContext context, String message, VoidCallback onUndo) => show(context, message, actionLabel: 'تراجع', onAction: onUndo);
}
