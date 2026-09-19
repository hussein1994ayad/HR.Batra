// =========================================================================
// نظام HR Pro v6.0 - خدمة الكاش والمزامنة دون اتصال للحضور (Attendance Sync Service)
// =========================================================================

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'supabase_service.dart';

class AttendanceSyncService {
  static Future<File> get _cacheFile async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/attendance_cache.json');
  }

  static Future<File> get _queueFile async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/offline_punches.json');
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
      debugPrint('💾 تم حفظ بيانات الفرع والجدول في الكاش المحلي للحضور.');
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

  /// إضافة بصمة حضور/انصراف إلى طابور الانتظار (Queue) عند انقطاع الإنترنت
  static Future<void> queueOfflinePunch(Map<String, dynamic> punchData) async {
    try {
      final file = await _queueFile;
      List<dynamic> queue = [];
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.isNotEmpty) {
          queue = jsonDecode(content) as List<dynamic>;
        }
      }

      // إضافة البصمة الجديدة
      queue.add(punchData);
      await file.writeAsString(jsonEncode(queue));
      debugPrint('⏳ تم تسجيل البصمة محلياً وإضافتها لطابور الانتظار. إجمالي المتراكم: ${queue.length}');
    } catch (e) {
      debugPrint('❌ فشل إضافة البصمة للطابور المحلي: $e');
    }
  }

  /// قراءة الطابور المحلي للبصمات المعلقة
  static Future<List<dynamic>> getOfflinePunchesQueue() async {
    try {
      final file = await _queueFile;
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.isNotEmpty) {
          return jsonDecode(content) as List<dynamic>;
        }
      }
    } catch (e) {
      debugPrint('❌ فشل قراءة طابور البصمات: $e');
    }
    return [];
  }

  /// مزامنة البصمات المعلقة مع Supabase عند عودة الاتصال
  static Future<void> syncOfflinePunches() async {
    try {
      final file = await _queueFile;
      if (!await file.exists()) return;

      final content = await file.readAsString();
      if (content.isEmpty) return;

      final List<dynamic> queue = jsonDecode(content) as List<dynamic>;
      if (queue.isEmpty) return;

      debugPrint('🔄 جارٍ مزامنة ${queue.length} بصمة حضور معلقة مع السيرفر...');

      List<dynamic> remainingQueue = [];

      for (var punch in queue) {
        try {
          final String employeeId = punch['employee_id'];
          final String workDate = punch['work_date'];
          final String type = punch['type']; // 'check_in' or 'check_out'
          final double lat = punch['latitude'];
          final double lng = punch['longitude'];
          final String time = punch['time'];
          final String branchId = punch['branch_id'];
          final String status = punch['status'];

          // جلب السجل الموجود لليوم إن وجد لتحديثه (upsert)
          final existing = await SupabaseService.client
              .from('attendance')
              .select()
              .eq('employee_id', employeeId)
              .eq('work_date', workDate)
              .maybeSingle();

          if (existing != null) {
            // تحديث السجل الحالي بالبصمة الجديدة
            if (type == 'check_in') {
              await SupabaseService.client.from('attendance').update({
                'check_in_time': time,
                'check_in_lat': lat,
                'check_in_lng': lng,
                'status': status,
              }).eq('id', existing['id']);
            } else {
              await SupabaseService.client.from('attendance').update({
                'check_out_time': time,
                'check_out_lat': lat,
                'check_out_lng': lng,
                'status': status,
              }).eq('id', existing['id']);
            }
          } else {
            // إدراج سجل جديد
            final Map<String, dynamic> insertData = {
              'employee_id': employeeId,
              'branch_id': branchId,
              'work_date': workDate,
              'status': status,
            };
            if (type == 'check_in') {
              insertData['check_in_time'] = time;
              insertData['check_in_lat'] = lat;
              insertData['check_in_lng'] = lng;
            } else {
              insertData['check_out_time'] = time;
              insertData['check_out_lat'] = lat;
              insertData['check_out_lng'] = lng;
            }
            await SupabaseService.client.from('attendance').insert(insertData);
          }
        } catch (e) {
          debugPrint('⚠️ فشل مزامنة بصمة محددة: $e');
          remainingQueue.add(punch); // Keep failed punches in queue
        }
      }

      if (remainingQueue.isEmpty) {
        // حذف ملف الطابور بعد نجاح المزامنة كلياً
        await file.delete();
        debugPrint('✅ تم مزامنة كافة البصمات المعلقة بنجاح وحذف ملف الطابور.');
      } else {
        // تحديث الملف بالبصمات المتبقية
        await file.writeAsString(jsonEncode(remainingQueue));
        debugPrint('⚠️ تم مزامنة بعض البصمات. تبقى ${remainingQueue.length} بصمة لإعادة المحاولة.');
      }
    } catch (e) {
      debugPrint('⚠️ فشل مزامنة البصمات المعلقة: $e');
    }
  }
}
