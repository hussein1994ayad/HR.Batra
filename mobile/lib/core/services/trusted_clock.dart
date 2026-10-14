// =========================================================================
// الوقت الموثوق للبصمة بدون إنترنت: يحفظ آخر وقت سيرفر ويا عدّاد الموبايل (الحساب بـ core/logic/offline_punch_time.dart)
// =========================================================================

import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../logic/offline_punch_time.dart';
import '../utils/app_log.dart';
import 'supabase_service.dart';

abstract final class TrustedClock {
  static const MethodChannel _channel = MethodChannel('com.batra.hrpro/device');
  static const String _key = 'trusted_clock_anchor';

  /// لقطة العدّاد من الموبايل (null إذا ما متوفر، مثل الفحوصات أو نسخة نظام قديمة).
  static Future<ClockSnapshot?> snapshot() async {
    try {
      final m = await _channel.invokeMapMethod<String, dynamic>('clockSnapshot');
      final elapsed = m?['elapsedMs'];
      final boot = m?['bootId'];
      if (elapsed is int && boot is String) return ClockSnapshot(elapsedMs: elapsed, bootId: boot);
    } catch (_) {}
    return null;
  }

  /// يحفظ وقت السيرفر ويا لقطة العدّاد لحظتها.
  static Future<void> anchor(DateTime serverTime) async {
    final s = await snapshot();
    if (s == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(ClockAnchor(serverTime: serverTime, elapsedMs: s.elapsedMs, bootId: s.bootId).toJson()));
    } catch (e) {
      appLog('تعذّر حفظ وقت السيرفر: $e');
    }
  }

  /// ياخذ وقت السيرفر (server_now) ويحفظه. بدون إنترنت أو سيرفر قديم: ما يصير شي.
  static Future<void> anchorFromServer() async {
    try {
      final t = await SupabaseService.client.rpc<dynamic>('server_now').timeout(const Duration(seconds: 8));
      final serverTime = DateTime.tryParse('$t');
      if (serverTime != null) await anchor(serverTime);
    } catch (_) {}
  }

  /// وقت بصمة بدون إنترنت هسه: محسوب من آخر وقت سيرفر، أو «غير معروف» (السيرفر يعلّمها للمراجعة).
  static Future<OfflinePunchTime> offlinePunchTime() async {
    ClockAnchor? anchor;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null) anchor = ClockAnchor.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {}
    return computeOfflinePunchTime(anchor, await snapshot());
  }
}
