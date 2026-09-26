// =========================================================================
// HR Pro — شريط "غير متصل بالإنترنت"
// =========================================================================
// يظهر أعلى كل الشاشات تلقائياً (مضاف في main.dart عبر MaterialApp.builder)
// عندما ينقطع الاتصال، ويختفي عند عودته.
// =========================================================================

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/design/design.dart';

class ConnectivityStatus {
  ConnectivityStatus._();
  static final ValueNotifier<bool> isOnline = ValueNotifier<bool>(true);

  static Future<void> check() async {
    try {
      final result = await InternetAddress.lookup('supabase.co').timeout(const Duration(seconds: 3));
      isOnline.value = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } on SocketException {
      isOnline.value = false;
    } on TimeoutException {
      isOnline.value = false;
    } catch (_) {
      // خطأ غير متوقع — لا نغيّر الحالة
    }
  }

  static Timer? _timer;

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

class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ConnectivityStatus.isOnline,
      builder: (context, isOnline, _) {
        return AnimatedSize(
          duration: AppMotion.of(context),
          curve: AppMotion.standard,
          child: isOnline ? const SizedBox(width: double.infinity) : const _Bar(),
        );
      },
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.warningContainer,
      child: SafeArea(
        bottom: false,
        child: Semantics(
          liveRegion: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.xs),
            child: Row(
              children: [
                const Icon(Icons.wifi_off_rounded, color: AppColors.warning, size: 18),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Text(
                    'غير متصل — البصمات تُحفظ بالجهاز وتُرسل عند عودة الإنترنت',
                    style: AppText.caption.copyWith(color: AppColors.warning, fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton(
                  onPressed: ConnectivityStatus.check,
                  style: TextButton.styleFrom(foregroundColor: AppColors.warning, minimumSize: const Size(48, 40)),
                  child: const Text('تحديث'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// غلاف عام للتطبيق: يحدّ تكبير الخط عند 1.3 حتى لا تتكسر التصاميم،
/// ويعرض شريط "غير متصل" أعلى الشاشة ويزيح المحتوى تحته.
class AppChrome extends StatelessWidget {
  const AppChrome({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return MediaQuery(
      data: mq.copyWith(textScaler: mq.textScaler.clamp(maxScaleFactor: 1.3)),
      child: ValueListenableBuilder<bool>(
        valueListenable: ConnectivityStatus.isOnline,
        child: child,
        builder: (context, online, child) => Column(
          children: [
            const OfflineBanner(),
            Expanded(child: MediaQuery.removePadding(context: context, removeTop: !online, child: child!)),
          ],
        ),
      ),
    );
  }
}
