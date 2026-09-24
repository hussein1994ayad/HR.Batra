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
import '../../core/theme/app_theme.dart';
import '../shared/widgets/glass_background.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  bool _isLoading = false;
  String? _errorMessage;

  late final AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _animController.dispose();
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تم تحديث كلمة المرور بنجاح — أهلاً بك في النظام',
            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w600),
          ),
          backgroundColor: AppTheme.successGreen,
          behavior: SnackBarBehavior.floating,
        ),
      );
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final t = theme.textTheme;
    final cs = theme.colorScheme;
    final media = MediaQuery.of(context);

    return GlassBackground(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            padding: EdgeInsets.only(
              left: AppTheme.space6,
              right: AppTheme.space6,
              top: AppTheme.space6,
              bottom: AppTheme.space6 + media.viewInsets.bottom,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: FadeTransition(
                opacity: _animController,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Spacer(),
                    _buildIcon(isDark),
                    const SizedBox(height: AppTheme.space5),
                    _buildTitle(t, isDark),
                    const SizedBox(height: AppTheme.space6),
                    _buildFormCard(isDark, t, cs),
                    const Spacer(flex: 2),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildIcon(bool isDark) {
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isDark ? AppTheme.darkSurface : Colors.white,
        boxShadow: [
          BoxShadow(
            color: AppTheme.warningOrange.withValues(alpha: 0.35),
            blurRadius: 32,
            spreadRadius: 4,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(
          color: AppTheme.warningOrange.withValues(alpha: 0.2),
          width: 1.5,
        ),
      ),
      child: const Icon(
        Icons.security_rounded,
        size: 48,
        color: AppTheme.warningOrange,
      ),
    );
  }

  Widget _buildTitle(TextTheme t, bool isDark) {
    return Column(
      children: [
        Text(
          'تغيير كلمة المرور',
          style: t.displaySmall?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: AppTheme.space2),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.space4),
          child: Text(
            'لأمانك، يجب تغيير كلمة المرور المؤقتة قبل استخدام النظام.',
            textAlign: TextAlign.center,
            style: t.bodyMedium?.copyWith(
              color: isDark
                  ? AppTheme.darkTextSecondary
                  : AppTheme.lightTextSecondary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFormCard(bool isDark, TextTheme t, ColorScheme cs) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 480),
      padding: const EdgeInsets.all(AppTheme.space6),
      decoration: BoxDecoration(
        color: isDark
            ? AppTheme.darkSurface.withValues(alpha: 0.92)
            : Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : AppTheme.lightBorder,
        ),
        boxShadow: AppTheme.shadowLg(isDark),
      ),
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_errorMessage != null) ...[
              _errorBanner(_errorMessage!),
              const SizedBox(height: AppTheme.space5),
            ],
            Text('كلمة المرور الجديدة',
                style: t.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: AppTheme.space2),
            TextFormField(
              controller: _passwordController,
              obscureText: !_isPasswordVisible,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.newPassword],
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: '••••••••',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  icon: Icon(_isPasswordVisible
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined),
                  onPressed: () => setState(
                      () => _isPasswordVisible = !_isPasswordVisible),
                ),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'يرجى إدخال كلمة المرور الجديدة';
                if (v.length < 6) return 'كلمة المرور 6 خانات على الأقل';
                return null;
              },
            ),
            const SizedBox(height: AppTheme.space3),
            _StrengthMeter(strength: _strength(_passwordController.text)),
            const SizedBox(height: AppTheme.space5),
            Text('تأكيد كلمة المرور',
                style: t.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: AppTheme.space2),
            TextFormField(
              controller: _confirmPasswordController,
              obscureText: !_isConfirmPasswordVisible,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _handleChangePassword(),
              decoration: InputDecoration(
                hintText: '••••••••',
                prefixIcon: const Icon(Icons.check_circle_outline_rounded),
                suffixIcon: IconButton(
                  icon: Icon(_isConfirmPasswordVisible
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined),
                  onPressed: () => setState(() =>
                      _isConfirmPasswordVisible = !_isConfirmPasswordVisible),
                ),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'يرجى تأكيد كلمة المرور';
                if (v != _passwordController.text) return 'كلمتا المرور غير متطابقتين';
                return null;
              },
            ),
            const SizedBox(height: AppTheme.space8),
            SizedBox(
              height: 54,
              child: FilledButton.icon(
                onPressed: _isLoading ? null : _handleChangePassword,
                icon: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5))
                    : const Icon(Icons.lock_reset_rounded),
                label: Text(
                  _isLoading ? 'جاري التحديث...' : 'تحديث كلمة المرور',
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: cs.primary,
                  foregroundColor: cs.onPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorBanner(String msg) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.space3),
      decoration: BoxDecoration(
        color: AppTheme.dangerRed.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: AppTheme.dangerRed.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded,
              color: AppTheme.dangerRed, size: 20),
          const SizedBox(width: AppTheme.space2),
          Expanded(
            child: Text(
              msg,
              style: const TextStyle(
                color: AppTheme.dangerRed,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                fontFamily: 'Cairo',
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StrengthMeter extends StatelessWidget {
  final int strength; // 0..3
  const _StrengthMeter({required this.strength});

  @override
  Widget build(BuildContext context) {
    final labels = ['ضعيفة', 'متوسطة', 'جيدة', 'قوية'];
    final colors = [
      AppTheme.dangerRed,
      AppTheme.warningOrange,
      AppTheme.successGreen.withValues(alpha: 0.8),
      AppTheme.successGreen,
    ];
    return Row(
      children: [
        Expanded(
          child: Row(
            children: List.generate(4, (i) {
              return Expanded(
                child: Container(
                  height: 4,
                  margin: EdgeInsets.only(right: i < 3 ? 4 : 0),
                  decoration: BoxDecoration(
                    color: i <= strength
                        ? colors[strength]
                        : Theme.of(context).colorScheme.outline.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(width: AppTheme.space3),
        Text(
          labels[strength],
          style: TextStyle(
            color: colors[strength],
            fontSize: 11,
            fontWeight: FontWeight.w800,
            fontFamily: 'Cairo',
          ),
        ),
      ],
    );
  }
}
