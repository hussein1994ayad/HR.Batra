import 'package:flutter/material.dart';

import '../../shared/ui/ui.dart';

/// هيكل شاشات الدخول: شعار، عنوان، نموذج، وتذييل — يتمرر مع الكيبورد
/// ويبقى بعرض مريح على التابلت.
class AuthShell extends StatelessWidget {
  const AuthShell({super.key, required this.icon, required this.title, required this.subtitle, required this.child, this.footer});

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) => SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxl, vertical: AppSpace.xl),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: c.maxHeight - AppSpace.xl * 2),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: FadeSlideIn(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(color: AppColors.brandContainer, borderRadius: BorderRadius.circular(AppRadius.lg)),
                            child: Icon(icon, color: AppColors.brand, size: 36),
                          ),
                        ),
                        const SizedBox(height: AppSpace.xl),
                        Semantics(header: true, child: Text(title, style: AppText.headline, textAlign: TextAlign.center)),
                        const SizedBox(height: AppSpace.sm),
                        Text(subtitle, style: AppText.bodySm, textAlign: TextAlign.center),
                        const SizedBox(height: AppSpace.x3),
                        AppCard(padding: const EdgeInsets.all(AppSpace.xl), child: child),
                        if (footer != null) ...[const SizedBox(height: AppSpace.xxl), footer!],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// رسالة خطأ داخل النموذج (بدل نافذة منبثقة).
class FormErrorBanner extends StatelessWidget {
  const FormErrorBanner(this.message, {super.key});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpace.md),
        decoration: const BoxDecoration(color: AppColors.dangerContainer, borderRadius: AppRadius.control),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 20),
            const SizedBox(width: AppSpace.sm),
            Expanded(child: Text(message, style: AppText.bodySm.copyWith(color: AppColors.textPrimary))),
          ],
        ),
      ),
    );
  }
}

/// زر إظهار/إخفاء كلمة المرور.
class PasswordVisibilityButton extends StatelessWidget {
  const PasswordVisibilityButton({super.key, required this.visible, required this.onPressed});
  final bool visible;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: visible ? 'إخفاء كلمة المرور' : 'إظهار كلمة المرور',
        onPressed: onPressed,
        icon: Icon(visible ? Icons.visibility_off_rounded : Icons.visibility_rounded),
      );
}
