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
import '../shared/ui/ui.dart';
import 'widgets/auth_shell.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();

  bool _isPasswordVisible = false;
  bool _isLoading = false;
  String? _errorMessage;
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
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
    return AuthShell(
      icon: Icons.badge_rounded,
      title: 'أهلاً بك في HR Pro',
      subtitle: 'سجّل دخولك بحساب العمل لمتابعة دوامك وطلباتك.',
      footer: Text(
        _appVersion.isEmpty ? '© 2026 HR Pro' : '© 2026 HR Pro · $_appVersion',
        style: AppText.caption,
        textAlign: TextAlign.center,
      ),
      child: Form(
        key: _formKey,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppTextField(
                controller: _emailController,
                focusNode: _emailFocus,
                label: 'البريد الإلكتروني',
                hint: 'name@company.com',
                icon: Icons.alternate_email_rounded,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.username, AutofillHints.email],
                textDirection: TextDirection.ltr,
                onSubmitted: (_) => _passwordFocus.requestFocus(),
                validator: (v) {
                  final val = v?.trim() ?? '';
                  if (val.isEmpty) return 'اكتب بريدك الإلكتروني';
                  if (!RegExp(r'^[\w.\-]+@([\w\-]+\.)+[\w\-]{2,}$').hasMatch(val)) {
                    return 'صيغة البريد غير صحيحة';
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppSpace.lg),
              AppTextField(
                controller: _passwordController,
                focusNode: _passwordFocus,
                label: 'كلمة المرور',
                hint: '••••••••',
                icon: Icons.lock_outline_rounded,
                obscureText: !_isPasswordVisible,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                textDirection: TextDirection.ltr,
                onSubmitted: (_) => _handleLogin(),
                suffix: PasswordVisibilityButton(
                  visible: _isPasswordVisible,
                  onPressed: () => setState(() => _isPasswordVisible = !_isPasswordVisible),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'اكتب كلمة المرور';
                  if (v.length < 6) return 'كلمة المرور 6 خانات على الأقل';
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
                label: 'تسجيل الدخول',
                icon: Icons.login_rounded,
                size: AppButtonSize.large,
                expand: true,
                loading: _isLoading,
                onPressed: _handleLogin,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
