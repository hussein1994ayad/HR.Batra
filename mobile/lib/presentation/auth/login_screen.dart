// =========================================================================
// نظام HR Pro v6.0 - شاشة تسجيل الدخول (Premium Login)
// إعادة تصميم عصرية: staggered animations، ألوان الثيم، تجربة كيبورد أفضل،
// دعم أجهزة صغيرة (iPhone SE)، ورسائل خطأ واضحة.
// =========================================================================

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../core/routes/app_router.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/notification_service.dart';
import '../../core/theme/app_theme.dart';
import '../shared/widgets/glass_background.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();

  bool _isPasswordVisible = false;
  bool _isLoading = false;
  String? _errorMessage;
  String _appVersion = '';

  late final AnimationController _animController;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnimation = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: AppTheme.curveEmphasized));
    _animController.forward();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _appVersion = 'v${info.version}+${info.buildNumber}');
    } catch (_) {}
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    unawaited(HapticFeedback.lightImpact());
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await AuthService.signIn(
        _emailController.text.trim(),
        _passwordController.text.trim(),
      ).timeout(const Duration(seconds: 15));

      if (mounted) {
        unawaited(NotificationService.requestPermissionAndSaveToken());
        context.go(AppRoutes.employeeHome);
      }
    } on TimeoutException {
      _setError('انتهى وقت الطلب — تأكد من جودة اتصالك بالإنترنت');
    } on SocketException {
      _setError('لا يوجد اتصال بالإنترنت — يرجى التحقق من الشبكة');
    } on MustChangePasswordException {
      if (mounted) context.go(AppRoutes.changePassword);
    } on DeviceLockedException catch (e) {
      _setError(e.message);
    } on InactiveAccountException catch (e) {
      _setError(e.message);
    } catch (e) {
      _setError('خطأ في المصادقة: ${e.toString().replaceFirst('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _setError(String msg) {
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    setState(() => _errorMessage = msg);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final t = Theme.of(context).textTheme;
    final media = MediaQuery.of(context);

    return GlassBackground(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            padding: EdgeInsets.only(
              left: AppTheme.space6,
              right: AppTheme.space6,
              top: AppTheme.space6,
              bottom: AppTheme.space6 + media.viewInsets.bottom,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: SlideTransition(
                    position: _slideAnimation,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Spacer(),
                        _buildLogo(isDark),
                        const SizedBox(height: AppTheme.space6),
                        _buildTitle(t, isDark),
                        const SizedBox(height: AppTheme.space8),
                        _buildFormCard(isDark, t),
                        const Spacer(flex: 2),
                        _buildFooter(t, isDark),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // -------- Widgets --------
  Widget _buildLogo(bool isDark) {
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isDark ? AppTheme.darkSurface : Colors.white,
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryTeal.withValues(alpha: isDark ? 0.45 : 0.25),
            blurRadius: 32,
            spreadRadius: 4,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(
          color: AppTheme.primaryTeal.withValues(alpha: 0.15),
          width: 1.5,
        ),
      ),
      child: const Icon(
        Icons.business_center_rounded,
        size: 48,
        color: AppTheme.primaryTeal,
      ),
    );
  }

  Widget _buildTitle(TextTheme t, bool isDark) {
    return Column(
      children: [
        Text(
          'HR Pro',
          style: t.displaySmall?.copyWith(
            color: isDark ? AppTheme.primaryTealLight : AppTheme.primaryTeal,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: AppTheme.space2),
        Text(
          'مرحباً بعودتك — سجّل الدخول لمتابعة عملك',
          textAlign: TextAlign.center,
          style: t.bodyMedium?.copyWith(
            color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildFormCard(bool isDark, TextTheme t) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 480),
      padding: const EdgeInsets.all(AppTheme.space6),
      decoration: BoxDecoration(
        color: isDark
            ? AppTheme.darkSurface.withValues(alpha: 0.92)
            : Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : AppTheme.lightBorder,
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
              _buildErrorBanner(_errorMessage!),
              const SizedBox(height: AppTheme.space5),
            ],
            _buildFieldLabel('البريد الإلكتروني', isDark, t),
            const SizedBox(height: AppTheme.space2),
            TextFormField(
              controller: _emailController,
              focusNode: _emailFocus,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email, AutofillHints.username],
              onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
              textAlign: TextAlign.left,
              textDirection: TextDirection.ltr,
              enableSuggestions: false,
              autocorrect: false,
              decoration: const InputDecoration(
                hintText: 'name@company.com',
                hintTextDirection: TextDirection.ltr,
                prefixIcon: Icon(Icons.email_outlined),
              ),
              validator: (v) {
                final val = v?.trim() ?? '';
                if (val.isEmpty) return 'يرجى إدخال البريد الإلكتروني';
                if (!RegExp(r'^[\w.\-]+@([\w\-]+\.)+[\w\-]{2,}$').hasMatch(val)) {
                  return 'صيغة البريد الإلكتروني غير صحيحة';
                }
                return null;
              },
            ),
            const SizedBox(height: AppTheme.space5),
            _buildFieldLabel('كلمة المرور', isDark, t),
            const SizedBox(height: AppTheme.space2),
            TextFormField(
              controller: _passwordController,
              focusNode: _passwordFocus,
              obscureText: !_isPasswordVisible,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.password],
              onFieldSubmitted: (_) => _handleLogin(),
              textAlign: TextAlign.left,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                hintText: '••••••••',
                hintTextDirection: TextDirection.ltr,
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  tooltip: _isPasswordVisible ? 'إخفاء' : 'إظهار',
                  icon: AnimatedSwitcher(
                    duration: AppTheme.motionFast,
                    child: Icon(
                      _isPasswordVisible
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      key: ValueKey(_isPasswordVisible),
                    ),
                  ),
                  onPressed: () => setState(() => _isPasswordVisible = !_isPasswordVisible),
                ),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'يرجى إدخال كلمة المرور';
                if (v.length < 6) return 'كلمة المرور 6 خانات على الأقل';
                return null;
              },
            ),
            const SizedBox(height: AppTheme.space8),
            _buildLoginButton(),
            const SizedBox(height: AppTheme.space4),
            Center(
              child: Text(
                'نسيت كلمة المرور؟ راجع إدارة الموارد البشرية',
                textAlign: TextAlign.center,
                style: t.bodySmall?.copyWith(
                  color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFieldLabel(String label, bool isDark, TextTheme t) {
    return Text(
      label,
      style: t.labelLarge?.copyWith(
        color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _buildErrorBanner(String msg) {
    return AnimatedContainer(
      duration: AppTheme.motionNormal,
      padding: const EdgeInsets.all(AppTheme.space3),
      decoration: BoxDecoration(
        color: AppTheme.dangerRed.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: AppTheme.dangerRed.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, color: AppTheme.dangerRed, size: 20),
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

  Widget _buildLoginButton() {
    return AnimatedContainer(
      duration: AppTheme.motionFast,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        boxShadow: _isLoading ? null : AppTheme.glowPrimary(),
      ),
      child: SizedBox(
        height: 54,
        child: ElevatedButton(
          onPressed: _isLoading ? null : _handleLogin,
          style: ElevatedButton.styleFrom(
            padding: EdgeInsets.zero,
            elevation: 0,
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusSm)),
          ),
          child: Ink(
            decoration: const BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.all(Radius.circular(AppTheme.radiusSm)),
            ),
            child: Center(
              child: AnimatedSwitcher(
                duration: AppTheme.motionNormal,
                child: _isLoading
                    ? const SizedBox(
                        key: ValueKey('loading'),
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                      )
                    : const Row(
                        key: ValueKey('label'),
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.login_rounded, color: Colors.white, size: 20),
                          SizedBox(width: 10),
                          Text(
                            'تسجيل الدخول',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontFamily: 'Cairo',
                              fontSize: 16,
                              color: Colors.white,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(TextTheme t, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(top: AppTheme.space6),
      child: Column(
        children: [
          Text(
            '© 2026 HR Pro',
            style: t.bodySmall?.copyWith(
              color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (_appVersion.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              _appVersion,
              style: t.bodySmall?.copyWith(
                color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                fontSize: 10,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
