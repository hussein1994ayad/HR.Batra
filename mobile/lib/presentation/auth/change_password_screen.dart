// =========================================================================
// نظام HR Pro v6.0 - شاشة تغيير كلمة المرور الإجبارية (Mandatory Password Change Screen)
// =========================================================================

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/routes/app_router.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../shared/widgets/glass_background.dart';
import '../shared/widgets/glass_container.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
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
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await AuthService.changePassword(_passwordController.text.trim());
      
      if (mounted) {
        // إشعار المستخدم بالنجاح
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'تم تحديث كلمة المرور بنجاح! أهلاً بك في نظامك المالي والإداري الجديد.',
              style: TextStyle(fontFamily: 'Cairo'),
            ),
            backgroundColor: AppTheme.successGreen,
          ),
        );
        // التوجيه للرئيسية بعد النجاح
        context.go(AppRoutes.employeeHome);
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'حدث خطأ أثناء تحديث كلمة المرور. يرجى المحاولة لاحقاً.';
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
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // أيقونة قفل الأمان الأنيقة مع توهج
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDark ? const Color(0xFF1E293B) : Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.warningOrange.withOpacity(0.3),
                      blurRadius: 24,
                      spreadRadius: 4,
                    )
                  ],
                ),
                child: const Icon(
                  Icons.security_rounded,
                  size: 64,
                  color: AppTheme.warningOrange,
                ),
              ),
              const SizedBox(height: 24),

              const Text(
                'تأمين الحساب الإلزامي 🔒',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.w900,
                  fontSize: 24,
                  color: AppTheme.warningOrange,
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Text(
                  'لقد قمت بتسجيل الدخول بكلمة مرور مؤقتة لأول مرة. كإجراء أمان إلزامي، يرجى تعيين كلمة مرور قوية وجديدة لحماية حسابك وجلساتك.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                    fontSize: 13,
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                    height: 1.6,
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // نموذج ملء كلمات المرور داخل GlassContainer
              GlassContainer(
                padding: const EdgeInsets.all(28),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
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

                      // كلمة المرور الجديدة
                      Text(
                        'كلمة المرور الجديدة',
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
                          hintText: 'كلمة مرور جديدة قوية',
                          prefixIcon: const Icon(Icons.lock_outline, color: AppTheme.neonCyan),
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
                            return 'يرجى إدخال كلمة المرور الجديدة';
                          }
                          if (value.length < 8) {
                            return 'يجب أن تكون كلمة المرور 8 خانات فأكثر';
                          }
                          // التحقق من احتواء كلمة المرور على رقم ورمز لتأمينها بامتياز
                          if (!value.contains(RegExp(r'[0-9]')) || !value.contains(RegExp(r'[a-zA-Z]'))) {
                            return 'يجب أن تحتوي كلمة المرور على أحرف وأرقام معاً';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),

                      // تأكيد كلمة المرور الجديدة
                      Text(
                        'تأكيد كلمة المرور الجديدة',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          fontFamily: 'Cairo',
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _confirmPasswordController,
                        obscureText: !_isConfirmPasswordVisible,
                        textAlign: TextAlign.left,
                        style: TextStyle(color: isDark ? Colors.white : Colors.black, fontFamily: 'Cairo', fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'أعد كتابة كلمة المرور تأكيداً لها',
                          prefixIcon: const Icon(Icons.lock_reset_rounded, color: AppTheme.neonCyan),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _isConfirmPasswordVisible 
                                  ? Icons.visibility_off_outlined 
                                  : Icons.visibility_outlined,
                              color: AppTheme.neonCyan,
                            ),
                            onPressed: () {
                              setState(() {
                                _isConfirmPasswordVisible = !_isConfirmPasswordVisible;
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
                            return 'يرجى تأكيد كلمة المرور';
                          }
                          if (value != _passwordController.text) {
                            return 'كلمتا المرور غير متطابقتين';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 32),

                      // زر تحديث كلمة المرور المضيء بنمط النيون
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            if (!_isLoading)
                              BoxShadow(
                                color: AppTheme.warningOrange.withOpacity(0.3),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              )
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _handleChangePassword,
                            style: ElevatedButton.styleFrom(
                              padding: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              elevation: 0,
                              shadowColor: Colors.transparent,
                              backgroundColor: Colors.transparent,
                            ),
                            child: Ink(
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [AppTheme.warningOrange, Colors.orangeAccent],
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                ),
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
                                        'حفظ وتأمين الحساب',
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
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }
}
