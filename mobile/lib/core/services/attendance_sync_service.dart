// =========================================================================
// نظام HR Pro v6.0 - البصمة والمزامنة دون اتصال (Attendance Sync Service)
// =========================================================================
// كل بصمة تمر عبر الدالة punch_attendance في السيرفر: هي التي تحسب الوقت،
// المسافة من الفرع، حالة التأخير، وتتحقق من الجهاز المعتمد.
//
// الطابور المحلي يُستعمل فقط عند انقطاع الشبكة فعلياً. أي رد من السيرفر
// (رفض منطقي أو خطأ صلاحية) يُعرض للموظف ولا يُعاد إرساله.
// =========================================================================

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'device_service.dart';
import 'supabase_service.dart';

/// نتيجة محاولة البصمة.
class PunchResult {
  const PunchResult._({
    required this.ok,
    this.code,
    this.message,
    this.status,
    this.offline = false,
    this.queued = false,
  });

  /// سُجّلت في السيرفر.
  factory PunchResult.saved(Map<String, dynamic> data) => PunchResult._(
        ok: true,
        status: data['status'] as String?,
        offline: data['offline'] as bool? ?? false,
      );

  /// رفضها السيرفر لسبب منطقي (خارج النطاق، مكررة، موقع وهمي...).
  factory PunchResult.rejected(String? code, String? message) =>
      PunchResult._(ok: false, code: code, message: message);

  /// لا يوجد اتصال — حُفظت محلياً وستُرفع لاحقاً.
  const PunchResult.queued() : this._(ok: true, offline: true, queued: true);

  final bool ok;
  final String? code;
  final String? message;
  final String? status;
  final bool offline;
  final bool queued;
}

class AttendanceSyncService {
  static Future<File> get _cacheFile async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/attendance_cache.json');
  }

  static Future<File> get _queueFile async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/offline_punches.json');
  }

  /// هل الخطأ بسبب الشبكة؟ PostgrestException/AuthException تعني أن السيرفر ردّ.
  static bool isNetworkError(Object error) =>
      error is! PostgrestException && error is! AuthException;

  /// تسجيل بصمة. عند انقطاع الشبكة تُحفظ في الطابور المحلي.
  static Future<PunchResult> punch({
    required String type,
    required double latitude,
    required double longitude,
    bool isMocked = false,
  }) async {
    final punchTime = DateTime.now().toUtc();
    try {
      return await _sendPunch(
        type: type,
        latitude: latitude,
        longitude: longitude,
        isMocked: isMocked,
      );
    } catch (e) {
      if (!isNetworkError(e)) rethrow;
      debugPrint('⚠️ لا يوجد اتصال، حفظ البصمة محلياً: $e');
      await _queueOfflinePunch({
        'type': type,
        'latitude': latitude,
        'longitude': longitude,
        'time': punchTime.toIso8601String(),
      });
      return const PunchResult.queued();
    }
  }

  static Future<PunchResult> _sendPunch({
    required String type,
    required double latitude,
    required double longitude,
    bool isMocked = false,
    DateTime? offlineTime,
  }) async {
    final dynamic response = await SupabaseService.client.rpc<dynamic>(
      'punch_attendance',
      params: {
        'p_type': type,
        'p_latitude': latitude,
        'p_longitude': longitude,
        'p_device_id': await DeviceService.getDeviceUUID(),
        'p_is_mocked': isMocked,
        if (offlineTime != null) 'p_client_time': offlineTime.toIso8601String(),
      },
    ).timeout(const Duration(seconds: 15));

    final data = Map<String, dynamic>.from(response as Map);
    if (data['ok'] == true) return PunchResult.saved(data);
    return PunchResult.rejected(data['code'] as String?, data['message'] as String?);
  }

  /// حفظ تفاصيل الفرع والجدول محلياً للعمل دون اتصال بالإنترنت
  static Future<void> cacheBranchAndSchedule({
    required Map<String, dynamic> branchData,
    required Map<String, dynamic>? scheduleData,
  }) async {
    try {
      final file = await _cacheFile;
      final data = {
        'branch': branchData,
        'schedule': scheduleData,
        'cached_at': DateTime.now().toUtc().toIso8601String(),
      };
      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint('❌ فشل حفظ كاش الحضور: $e');
    }
  }

  /// قراءة تفاصيل الفرع والجدول من الكاش المحلي
  static Future<Map<String, dynamic>?> getCachedData() async {
    try {
      final file = await _cacheFile;
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.isNotEmpty) {
          return jsonDecode(content) as Map<String, dynamic>;
        }
      }
    } catch (e) {
      debugPrint('❌ فشل قراءة كاش الحضور: $e');
    }
    return null;
  }

  static Future<void> _queueOfflinePunch(Map<String, dynamic> punchData) async {
    final queue = await getOfflinePunchesQueue();
    queue.add(punchData);
    await _writeQueue(queue);
  }

  /// قراءة الطابور المحلي للبصمات المعلقة
  static Future<List<Map<String, dynamic>>> getOfflinePunchesQueue() async {
    try {
      final file = await _queueFile;
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.isNotEmpty) {
          return (jsonDecode(content) as List<dynamic>)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        }
      }
    } catch (e) {
      debugPrint('❌ فشل قراءة طابور البصمات: $e');
    }
    return [];
  }

  static Future<void> _writeQueue(List<Map<String, dynamic>> queue) async {
    final file = await _queueFile;
    if (queue.isEmpty) {
      if (await file.exists()) await file.delete();
    } else {
      await file.writeAsString(jsonEncode(queue));
    }
  }

  /// رفع البصمات المعلقة عند عودة الاتصال.
  ///
  /// ترجع البصمات التي رفضها السيرفر (مثلاً أقدم من 48 ساعة) ليُبلَّغ الموظف؛
  /// هذه تُحذف من الطابور ولا يعاد إرسالها. فشل الشبكة يُبقيها للمحاولة القادمة.
  static Future<List<PunchResult>> syncOfflinePunches() async {
    final queue = await getOfflinePunchesQueue();
    if (queue.isEmpty) return const [];

    final remaining = <Map<String, dynamic>>[];
    final rejected = <PunchResult>[];

    for (final punch in queue) {
      final time = DateTime.tryParse(punch['time'] as String? ?? '');
      final lat = (punch['latitude'] as num?)?.toDouble();
      final lng = (punch['longitude'] as num?)?.toDouble();
      final type = punch['type'] as String?;
      if (time == null || lat == null || lng == null || type == null) continue;

      try {
        final result = await _sendPunch(
          type: type,
          latitude: lat,
          longitude: lng,
          offlineTime: time,
        );
        // مكررة = سبق رفعها؛ لا داعي لإزعاج الموظف
        if (!result.ok && !(result.code?.startsWith('already_') ?? false)) {
          rejected.add(result);
        }
      } catch (e) {
        if (isNetworkError(e)) {
          remaining.add(punch);
        } else {
          debugPrint('⚠️ رفض السيرفر بصمة محفوظة: $e');
          rejected.add(PunchResult.rejected('server_error', e.toString()));
        }
      }
    }

    await _writeQueue(remaining);
    return rejected;
  }
}
