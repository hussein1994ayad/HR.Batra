// =========================================================================
// نظام HR Pro v6.0 - البصمة والمزامنة دون اتصال (Attendance Sync Service)
// =========================================================================
// كل بصمة تمر عبر الدالة punch_attendance في السيرفر: هي التي تحسب الوقت،
// المسافة من الفرع، حالة التأخير، وتتحقق من الجهاز المعتمد.
//
// الطابور المحلي يُستعمل فقط عند انقطاع الشبكة فعلياً. أي رد من السيرفر
// (رفض منطقي أو خطأ صلاحية) يُعرض للموظف ولا يُعاد إرساله.
// =========================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/branch_model.dart';
import '../models/work_schedule_model.dart';
import '../utils/app_log.dart';
import '../utils/json_map.dart';
import 'device_service.dart';
import 'notification_service.dart';
import 'supabase_service.dart';
import 'trusted_clock.dart';

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
    double? accuracy,
    bool isMocked = false,
  }) async {
    final punchTime = DateTime.now().toUtc();
    // وقت البصمة الحقيقي (من آخر وقت سيرفر وعدّاد الموبايل) ينحسب لحظة الضغط، قبل محاولة الإرسال
    final trusted = await TrustedClock.offlinePunchTime();
    try {
      return await _sendPunch(
        type: type,
        latitude: latitude,
        longitude: longitude,
        accuracy: accuracy,
        isMocked: isMocked,
      );
    } catch (e) {
      if (!isNetworkError(e)) rethrow;
      appLog('⚠️ لا يوجد اتصال، حفظ البصمة محلياً: $e');
      // علامة الموقع الوهمي وصاحب البصمة تُحفظ معها: بدونها كان وضع الطيران
      // + موقع وهمي يمرّر البصمة، وبصمة موظف تُرسل باسم من يدخل بعده.
      await _queueOfflinePunch({
        'type': type,
        'latitude': latitude,
        'longitude': longitude,
        'accuracy': accuracy,
        'is_mocked': isMocked,
        'user_id': SupabaseService.currentUser?.id,
        'time': punchTime.toIso8601String(),
        // ساعة الموبايل ممكن تتغيّر: الوقت المحسوب يرسل ويا البصمة، وبدونه السيرفر يعلّمها «تحتاج مراجعة»
        if (trusted.trustedTime != null) 'trusted_time': trusted.trustedTime!.toIso8601String(),
        'time_check': trusted.check,
      });
      return const PunchResult.queued();
    }
  }

  static Future<PunchResult> _sendPunch({
    required String type,
    required double latitude,
    required double longitude,
    double? accuracy,
    bool isMocked = false,
    DateTime? offlineTime,
    DateTime? trustedTime,
    String? timeCheck,
  }) async {
    final params = {
      'p_type': type,
      'p_latitude': latitude,
      'p_longitude': longitude,
      'p_device_id': await DeviceService.getDeviceUUID(),
      'p_is_mocked': isMocked,
      // دقة الـ GPS: السيرفر يرفض الموقع التقريبي/الضعيف
      if (accuracy != null) 'p_accuracy': accuracy,
      if (offlineTime != null) 'p_client_time': offlineTime.toIso8601String(),
    };
    final timeParams = {
      if (trustedTime != null) 'p_trusted_time': trustedTime.toIso8601String(),
      if (timeCheck != null) 'p_time_check': timeCheck,
    };
    dynamic response;
    try {
      response = await SupabaseService.client
          .rpc<dynamic>('punch_attendance', params: {...params, ...timeParams})
          .timeout(const Duration(seconds: 15));
    } on PostgrestException catch (e) {
      // سيرفر قبل تحديث 20261019000000 (ما يعرف الوقت المحسوب): نفس البصمة بالطريقة القديمة
      if (e.code != 'PGRST202' || timeParams.isEmpty) rethrow;
      response = await SupabaseService.client.rpc<dynamic>('punch_attendance', params: params).timeout(const Duration(seconds: 15));
    }

    final data = Map<String, dynamic>.from(response as Map);
    // وقت السيرفر بالرد: ينحفظ ويا عدّاد الموبايل حتى البصمة الجاية لو بدون إنترنت ينعرف وقتها
    final serverTime = DateTime.tryParse('${data['server_time'] ?? ''}');
    if (serverTime != null) unawaited(TrustedClock.anchor(serverTime));
    if (data['ok'] == true) {
      // بعد البصمة: لا تذكير بما سُجّل اليوم
      unawaited(NotificationService.refreshLocalAttendanceReminders());
      return PunchResult.saved(data);
    }
    return PunchResult.rejected(data['code'] as String?, data['message'] as String?);
  }

  /// حفظ تفاصيل الفرع والجدول محلياً للعمل دون اتصال بالإنترنت
  static Future<void> cacheBranchAndSchedule({
    required BranchModel branch,
    required WorkScheduleModel? schedule,
  }) async {
    try {
      final file = await _cacheFile;
      final data = {
        'branch': branch.toMap(),
        'schedule': schedule?.toMap(),
        'cached_at': DateTime.now().toUtc().toIso8601String(),
      };
      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      appLog('❌ فشل حفظ كاش الحضور: $e');
    }
  }

  /// الفرع والجدول من الكاش المحلي (null = ماكو فرع محفوظ). كاش النسخ القديمة بنفس الأعمدة، فينقرا عادي.
  static Future<({BranchModel branch, WorkScheduleModel? schedule})?> getCachedBranchAndSchedule() async {
    try {
      final file = await _cacheFile;
      if (file.existsSync()) {
        final content = await file.readAsString();
        if (content.isNotEmpty) {
          final data = rowOf(jsonDecode(content));
          final branch = data?.obj('branch');
          if (data == null || branch == null) return null;
          final schedule = data.obj('schedule');
          return (branch: BranchModel.fromMap(branch), schedule: schedule == null ? null : WorkScheduleModel.fromMap(schedule));
        }
      }
    } catch (e) {
      appLog('❌ فشل قراءة كاش الحضور: $e');
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
      if (file.existsSync()) {
        final content = await file.readAsString();
        if (content.isNotEmpty) {
          return (jsonDecode(content) as List<dynamic>)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        }
      }
    } catch (e) {
      appLog('❌ فشل قراءة طابور البصمات: $e');
    }
    return [];
  }

  static Future<void> _writeQueue(List<Map<String, dynamic>> queue) async {
    final file = await _queueFile;
    if (queue.isEmpty) {
      if (file.existsSync()) await file.delete();
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
    final userId = SupabaseService.currentUser?.id;
    if (userId == null) return const [];

    for (final punch in queue) {
      final time = DateTime.tryParse(punch['time'] as String? ?? '');
      final lat = (punch['latitude'] as num?)?.toDouble();
      final lng = (punch['longitude'] as num?)?.toDouble();
      final type = punch['type'] as String?;
      if (time == null || lat == null || lng == null || type == null) continue;

      // بصمة موظف آخر سجّل على نفس الهاتف: تبقى له (حتى 48 ساعة) ولا تُرسل باسم الحالي.
      // البصمات القديمة بدون صاحب (قبل هذا التحديث) لا تُرسل لأننا لا نعرف لمن هي.
      final owner = punch['user_id'] as String?;
      if (owner != userId) {
        if (owner != null && DateTime.now().toUtc().difference(time) < const Duration(hours: 48)) {
          remaining.add(punch);
        }
        continue;
      }

      try {
        final result = await _sendPunch(
          type: type,
          latitude: lat,
          longitude: lng,
          accuracy: (punch['accuracy'] as num?)?.toDouble(),
          isMocked: punch['is_mocked'] as bool? ?? false,
          offlineTime: time,
          trustedTime: DateTime.tryParse(punch['trusted_time'] as String? ?? ''),
          // بصمة محفوظة بنسخة أقدم من التطبيق (بدون حساب) = السيرفر يعلّمها «تحتاج مراجعة»
          timeCheck: punch['time_check'] as String? ?? 'no_anchor',
        );
        // مكررة = سبق رفعها؛ لا داعي لإزعاج الموظف
        if (!result.ok && !(result.code?.startsWith('already_') ?? false)) {
          rejected.add(result);
        }
      } catch (e) {
        if (isNetworkError(e)) {
          remaining.add(punch);
        } else {
          appLog('⚠️ رفض السيرفر بصمة محفوظة: $e');
          rejected.add(PunchResult.rejected('server_error', e.toString()));
        }
      }
    }

    await _writeQueue(remaining);
    return rejected;
  }
}
