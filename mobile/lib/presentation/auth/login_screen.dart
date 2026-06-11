// =========================================================================
// نظام HR Pro v6.0 - شاشة تسجيل الدخول المتميزة (Premium Login Screen)
// =========================================================================

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/routes/app_router.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/notification_service.dart';
import '../../core/theme/app_theme.dart';
import '../shared/widgets/glass_background.dart';
import '../shared/widgets/glass_container.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  
  bool _isPasswordVisible = false;
  bool _isLoading = false;
  String? _errorMessage;

  late AnimationController _animController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await AuthService.signIn(
        _emailController.text.trim(),
        _passwordController.text.trim(),
      );
      
      if (mounted) {
        // Request notification permissions automatically on login
        // We don't await this so it doesn't block navigation, it runs in background
        NotificationService.requestPermissionAndSaveToken();
        
        // إذا نجح تسجيل الدخول، نتوجه إلى الصفحة الرئيسية
        context.go(AppRoutes.employeeHome);
      }
    } on MustChangePasswordException {
      if (mounted) {
        // في حال ضرورة تغيير كلمة المرور المؤقتة
        context.go(AppRoutes.changePassword);
      }
    } on DeviceLockedException catch (e) {
      setState(() {
        _errorMessage = e.message;
      });
    } on InactiveAccountException catch (e) {
      setState(() {
        _errorMessage = e.message;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'خطأ في المصادقة: ${e.toString()}';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GlassBackground(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // شعار الشركة أو شعار النظام المضيء
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDark ? const Color(0xFF1E293B) : Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.neonCyan.withOpacity(0.3),
                        blurRadius: 24,
                        spreadRadius: 4,
                      )
                    ],
                  ),
                  child: const Icon(
                    Icons.business_center_rounded,
                    size: 64,
                    color: AppTheme.neonCyan,
                  ),
                ),
                const SizedBox(height: 24),
                
                // عنوان الواجهة
                const Text(
                  'HR Pro v6.0',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.w900,
                    fontSize: 28,
                    color: AppTheme.neonCyan,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'مرحباً بك مجدداً، يرجى تسجيل الدخول لمتابعة الدوام والطلبات',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                    fontSize: 13,
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 32),

                // بطاقة تسجيل الدخول بتقنية الزجاج البلوري
                GlassContainer(
                  padding: const EdgeInsets.all(28),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // رسالة الخطأ إن وجدت
                        if (_errorMessage != null) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                            decoration: BoxDecoration(
                              color: AppTheme.dangerRed.withAlpha(40),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppTheme.dangerRed.withAlpha(100)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline_rounded, color: AppTheme.dangerRed),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _errorMessage!,
                                    style: const TextStyle(
                                      color: AppTheme.dangerRed,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      fontFamily: 'Cairo',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),
                        ],

                        // حقل البريد الإلكتروني
                        Text(
                          'البريد الإلكتروني للعمل',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            fontFamily: 'Cairo',
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          textAlign: TextAlign.left,
                          style: TextStyle(color: isDark ? Colors.white : Colors.black, fontFamily: 'Cairo', fontSize: 14),
                          decoration: InputDecoration(
                            hintText: 'name@company.com',
                            prefixIcon: const Icon(Icons.email_outlined, color: AppTheme.neonCyan),
                            filled: true,
                            fillColor: isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.02),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.08)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(color: AppTheme.neonCyan, width: 1.5),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'يرجى إدخال البريد الإلكتروني';
                            }
                            if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value.trim())) {
                              return 'صيغة البريد الإلكتروني غير صحيحة';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 20),

                        // حقل كلمة المرور
                        Text(
                          'كلمة المرور',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            fontFamily: 'Cairo',
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: !_isPasswordVisible,
                          textAlign: TextAlign.left,
                          style: TextStyle(color: isDark ? Colors.white : Colors.black, fontFamily: 'Cairo', fontSize: 14),
                          decoration: InputDecoration(
                            hintText: '••••••••',
                            prefixIcon: const Icon(Icons.lock_outline_rounded, color: AppTheme.neonCyan),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _isPasswordVisible 
                                    ? Icons.visibility_off_outlined 
                                    : Icons.visibility_outlined,
                                color: AppTheme.neonCyan,
                              ),
                              onPressed: () {
                                setState(() {
                                  _isPasswordVisible = !_isPasswordVisible;
                                });
                              },
                            ),
                            filled: true,
                            fillColor: isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.02),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.08)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(color: AppTheme.neonCyan, width: 1.5),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'يرجى إدخال كلمة المرور';
                            }
                            if (value.length < 6) {
                              return 'يجب أن تكون كلمة المرور 6 خانات على الأقل';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 32),

                        // زر تسجيل الدخول التفاعلي بنمط النيون
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              if (!_isLoading)
                                BoxShadow(
                                  color: AppTheme.neonCyan.withOpacity(0.3),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                )
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _handleLogin,
                              style: ElevatedButton.styleFrom(
                                padding: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                elevation: 0,
                                shadowColor: Colors.transparent,
                                backgroundColor: Colors.transparent,
                              ),
                              child: Ink(
                                decoration: const BoxDecoration(
                                  gradient: AppTheme.cyberGradient,
                                ),
                                child: Container(
                                  constraints: const BoxConstraints(minHeight: 52.0),
                                  alignment: Alignment.center,
                                  child: _isLoading
                                      ? const SizedBox(
                                          height: 20,
                                          width: 20,
                                          child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2.5,
                                          ),
                                        )
                                      : const Text(
                                          'تسجيل الدخول للنظام',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontFamily: 'Cairo',
                                            fontSize: 15,
                                            color: Colors.white,
                                          ),
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 40),

                // ذيل الصفحة
                Text(
                  '© 2026 HR Pro - جميع الحقوق محفوظة لشركتكم الموقرة',
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'Cairo',
                    color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
