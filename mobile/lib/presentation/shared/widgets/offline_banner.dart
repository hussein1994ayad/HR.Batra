// =========================================================================
// HR Pro v6.0 - Offline Banner
// =========================================================================
// شريط علوي يظهر تلقائياً عند فقدان الاتصال بالإنترنت.
//
// الاستخدام:
//   Scaffold(
//     body: Column(
//       children: [
//         OfflineBanner(),   // ← أضفه لأي شاشة
//         Expanded(child: ...)
//       ],
//     ),
//   )
//
// يعتمد على `Connectivity()` من `dio` أو مراقبة نتائج طلبات Supabase.
// هنا نستخدم مؤقتاً حالة ثابتة يمكن ربطها لاحقاً بمزود Riverpod.
// =========================================================================

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/design/design.dart';

/// حالة الاتصال العالمية — تُحدَّث من AttendanceSyncService أو مراقبة الشبكة.
class ConnectivityStatus {
  ConnectivityStatus._();
  static final ValueNotifier<bool> isOnline = ValueNotifier<bool>(true);

  /// فحص بسيط للاتصال — ينادى دورياً.
  static Future<void> check() async {
    try {
      final result = await InternetAddress.lookup('supabase.co')
          .timeout(const Duration(seconds: 3));
      isOnline.value = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } on SocketException {
      isOnline.value = false;
    } on TimeoutException {
      isOnline.value = false;
    } catch (_) {
      // نبقي على القيمة الحالية عند أي خطأ آخر
    }
  }

  static Timer? _timer;

  /// ابدأ فحص دوري (كل 30 ثانية). يستدعى من main() مرة واحدة.
  static void startPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => check());
    check();
  }

  static void stopPolling() {
    _timer?.cancel();
    _timer = null;
  }
}

/// شريط "أنت أوفلاين" يظهر أعلى الشاشة عند فقدان الاتصال.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ConnectivityStatus.isOnline,
      builder: (context, isOnline, _) {
        return AnimatedSize(
          duration: AppMotion.normal,
          curve: AppMotion.standard,
          child: isOnline ? const SizedBox.shrink() : _bar(context),
        );
      },
    );
  }

  Widget _bar(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.warning,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.lg,
        vertical: AppSpace.sm,
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            const Icon(Icons.wifi_off_rounded, color: AppColors.textPrimary, size: 18),
            const SizedBox(width: AppSpace.sm),
            const Expanded(
              child: Text(
                'أنت غير متصل بالإنترنت — تُحفظ التغييرات محلياً وسنزامنها فور عودة الاتصال',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Cairo',
                ),
              ),
            ),
            TextButton(
              onPressed: ConnectivityStatus.check,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
              ),
              child: const Text(
                'إعادة محاولة',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Cairo',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
