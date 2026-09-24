// =========================================================================
// HR Pro v6.0 — أدوات عامة للتطبيق (General App Utilities)
// =========================================================================
// دوال مساعدة متنوعة تُستخدم في أكثر من شاشة.
// =========================================================================

import 'package:flutter/material.dart';

/// دوال مساعدة عامة للتطبيق.
class AppUtils {
  AppUtils._();

  // ─── تنسيق الأرقام ────────────────────────────────────────────────────

  /// يُنسّق رقم بفواصل الآلاف (مثال: 1500000 → "1,500,000")
  static String formatNumber(num? value) {
    if (value == null) return '0';
    return value.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );
  }

  /// يُنسّق مبلغ بالدينار العراقي (مثال: "1,500,000 د.ع")
  static String formatCurrency(num? amount) {
    return '${formatNumber(amount)} د.ع';
  }

  // ─── UI Helpers ───────────────────────────────────────────────────────

  /// يُظهر SnackBar بلون النجاح (أخضر)
  static void showSuccess(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontFamily: 'Cairo')),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  /// يُظهر SnackBar بلون الخطأ (أحمر)
  static void showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontFamily: 'Cairo')),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  /// يُظهر SnackBar معلوماتي (أزرق)
  static void showInfo(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontFamily: 'Cairo')),
        backgroundColor: Colors.blue.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  /// يُظهر نافذة تأكيد ويُرجع true عند الضغط على "نعم"
  static Future<bool> showConfirmDialog(
    BuildContext context, {
    required String title,
    required String message,
    String confirmText = 'نعم',
    String cancelText = 'إلغاء',
    Color confirmColor = Colors.red,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title, style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
        content: Text(message, style: const TextStyle(fontFamily: 'Cairo')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(cancelText, style: const TextStyle(fontFamily: 'Cairo')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: confirmColor),
            child: Text(confirmText, style: const TextStyle(fontFamily: 'Cairo', color: Colors.white)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  // ─── التحقق من المدخلات ───────────────────────────────────────────────

  /// يتحقق من صحة البريد الإلكتروني
  static bool isValidEmail(String email) {
    return RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$').hasMatch(email);
  }

  /// يتحقق أن رقم الهاتف العراقي صحيح (07XXXXXXXXX)
  static bool isValidIraqiPhone(String phone) {
    return RegExp(r'^07[3-9]\d{8}$').hasMatch(phone.replaceAll(' ', ''));
  }
}
