// =========================================================================
// HR Pro v6.0 - شاشة تغيير كلمة المرور الإلزامية
// إعادة تصميم عصرية بنفس أسلوب login_screen الجديد.
// كل منطق الأمان محفوظ كما هو.
// =========================================================================

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';


import '../../core/routes/app_router.dart';
import '../../core/services/auth_service.dart';
import '../shared/ui/ui.dart';
import 'widgets/auth_shell.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen>
    {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleChangePassword() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    unawaited(HapticFeedback.lightImpact());

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await AuthService.changePassword(_passwordController.text.trim())
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;
      AppSnack.success(context, 'تم تحديث كلمة المرور — أهلاً بك');
      context.go(AppRoutes.employeeHome);
    } on TimeoutException {
      _setError('انتهى وقت الطلب — تأكد من جودة اتصالك بالإنترنت');
    } on SocketException {
      _setError('لا يوجد اتصال بالإنترنت — يرجى التحقق من الشبكة');
    } catch (e) {
      _setError('حدث خطأ أثناء تحديث كلمة المرور. يرجى المحاولة لاحقاً.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _setError(String msg) {
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    setState(() => _errorMessage = msg);
  }

  // Password strength: returns 0..3 (weak/medium/strong)
  int _strength(String p) {
    if (p.length < 6) return 0;
    var score = 0;
    if (p.length >= 8) score++;
    if (RegExp(r'\d').hasMatch(p)) score++;
    if (RegExp(r'[A-Z]').hasMatch(p) && RegExp(r'[a-z]').hasMatch(p)) score++;
    if (RegExp(r'[!@#$%^&*()_+\-=\[\]{};:,.<>?/\\|]').hasMatch(p)) score++;
    return score.clamp(0, 3);
  }

  @override
  Widget build(BuildContext context) {
    final strength = _strength(_passwordController.text);
    return AuthShell(
      icon: Icons.lock_reset_rounded,
      title: 'غيّر كلمة المرور',
      subtitle: 'لأمانك، اختر كلمة مرور جديدة بدل المؤقتة قبل البدء.',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextField(
              controller: _passwordController,
              label: 'كلمة المرور الجديدة',
              hint: '••••••••',
              icon: Icons.lock_outline_rounded,
              obscureText: !_isPasswordVisible,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.newPassword],
              textDirection: TextDirection.ltr,
              onChanged: (_) => setState(() {}),
              suffix: PasswordVisibilityButton(
                visible: _isPasswordVisible,
                onPressed: () => setState(() => _isPasswordVisible = !_isPasswordVisible),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'اكتب كلمة المرور الجديدة';
                if (v.length < 6) return 'كلمة المرور 6 خانات على الأقل';
                return null;
              },
            ),
            const SizedBox(height: AppSpace.md),
            _StrengthMeter(strength: strength, empty: _passwordController.text.isEmpty),
            const SizedBox(height: AppSpace.lg),
            AppTextField(
              controller: _confirmPasswordController,
              label: 'تأكيد كلمة المرور',
              hint: '••••••••',
              icon: Icons.check_circle_outline_rounded,
              obscureText: !_isConfirmPasswordVisible,
              textInputAction: TextInputAction.done,
              textDirection: TextDirection.ltr,
              onSubmitted: (_) => _handleChangePassword(),
              suffix: PasswordVisibilityButton(
                visible: _isConfirmPasswordVisible,
                onPressed: () => setState(() => _isConfirmPasswordVisible = !_isConfirmPasswordVisible),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'أعد كتابة كلمة المرور';
                if (v != _passwordController.text) return 'كلمتا المرور غير متطابقتين';
                return null;
              },
            ),
            AnimatedSize(
              duration: AppMotion.of(context),
              child: _errorMessage == null
                  ? const SizedBox(width: double.infinity)
                  : Padding(padding: const EdgeInsets.only(top: AppSpace.lg), child: FormErrorBanner(_errorMessage!)),
            ),
            const SizedBox(height: AppSpace.xl),
            AppButton(
              label: 'حفظ كلمة المرور',
              icon: Icons.check_rounded,
              size: AppButtonSize.large,
              expand: true,
              loading: _isLoading,
              onPressed: _handleChangePassword,
            ),
          ],
        ),
      ),
    );
  }
}

/// مؤشر قوة كلمة المرور: 4 أشرطة + وصف.
class _StrengthMeter extends StatelessWidget {
  const _StrengthMeter({required this.strength, required this.empty});
  final int strength;
  final bool empty;

  @override
  Widget build(BuildContext context) {
    const labels = ['ضعيفة', 'متوسطة', 'جيدة', 'قوية'];
    const tones = [AppTone.danger, AppTone.warning, AppTone.info, AppTone.success];
    final tone = tones[strength];
    return Semantics(
      label: empty ? null : 'قوة كلمة المرور: ${labels[strength]}',
      child: ExcludeSemantics(
        child: Row(
          children: [
            for (var i = 0; i < 4; i++) ...[
              Expanded(
                child: AnimatedContainer(
                  duration: AppMotion.of(context),
                  height: 4,
                  decoration: BoxDecoration(
                    color: !empty && i <= strength ? tone.color : AppColors.surface3,
                    borderRadius: AppRadius.pill,
                  ),
                ),
              ),
              if (i < 3) const SizedBox(width: AppSpace.xs),
            ],
            const SizedBox(width: AppSpace.md),
            Text(empty ? 'قوة كلمة المرور' : labels[strength], style: AppText.caption.copyWith(color: empty ? AppColors.textMuted : tone.color)),
          ],
        ),
      ),
    );
  }
}
