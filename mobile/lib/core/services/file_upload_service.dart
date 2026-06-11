// =========================================================================
// نظام HR Pro v6.0 - خدمة الرفع والتحكم الذكي بالملفات (File Upload Service)
// =========================================================================

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path/path.dart' as p;
import 'supabase_service.dart';
import 'image_compression_service.dart';

class FileUploadService {
  // 1. رفع ملف مع الضغط التلقائي للصور وتطهير الـ EXIF، وإمكانية حذف الملف القديم المستبدل
  static Future<String> uploadFile({
    required File file,
    required String bucketName,
    required String remotePath,
    String? oldRemotePath, // المسار القديم لحذفه تلقائياً لمنع التخمة
  }) async {
    // ضغط الملف تلقائياً إذا كان صورة (مثل الأفاتار، الوثيقة، التعهد)
    final File processedFile = await ImageCompressionService.compressImage(file);

    // الرفع الفعلي إلى Supabase Storage مع ميزة Upsert (الاستبدال في حال تطابق المسار)
    await SupabaseService.client.storage
        .from(bucketName)
        .upload(
          remotePath, 
          processedFile, 
          fileOptions: const FileOptions(upsert: true)
        );

    // استخراج الرابط العام للملف
    final String publicUrl = SupabaseService.client.storage
        .from(bucketName)
        .getPublicUrl(remotePath);

    // حذف الملف القديم المستبدل من التخزين لتوفير المساحة
    if (oldRemotePath != null && oldRemotePath.isNotEmpty && oldRemotePath != remotePath) {
      try {
        await SupabaseService.client.storage
            .from(bucketName)
            .remove([oldRemotePath]);
        
        if (kDebugMode) {
          print("تم مسح الملف المستبدل القديم بنجاح من التخزين: $oldRemotePath");
        }
      } catch (e) {
        if (kDebugMode) {
          print("فشل مسح الملف المستبدل القديم تلقائياً: $e");
        }
      }
    }

    return publicUrl;
  }

  // 2. حذف ملف يدوي مع خيار نقله لسلة المحذوفات (30 يوماً) أو حذفه فورياً نهائياً
  static Future<void> deleteFile({
    required String filePath,
    required String bucketName,
    required String fileType, // 'avatar', 'document', 'pledge', 'logo', 'other'
    required bool isImmediate, // حذف فوري أم سلة محذوفات 30 يوم
    String? relatedTable,
    String? relatedId,
  }) async {
    final supabase = SupabaseService.client;
    final currentUserId = supabase.auth.currentUser?.id;

    if (isImmediate) {
      // حذف فوري ونهائي للملف من التخزين
      await supabase.storage.from(bucketName).remove([filePath]);
      
      if (kDebugMode) {
        print("تم حذف الملف نهائياً وفورياً من التخزين: $filePath");
      }
    } else {
      // نقل الملف لسلة المحذوفات (Deleted Files) لمدة 30 يوماً
      // يتم الاحتفاظ بالملف في التخزين مؤقتاً، وتوثيق حذفه وتاريخ انتهائه في جدول سلة المحذوفات
      int? fileSizeBytes;
      
      try {
        fileSizeBytes = await _getFileSizeInStorage(bucketName, filePath);
      } catch (_) {}

      await supabase.from('deleted_files').insert({
        'file_path': filePath,
        'file_type': fileType,
        'related_table': relatedTable,
        'related_id': relatedId,
        'deleted_by': currentUserId,
        'scheduled_deletion_date': DateTime.now().add(const Duration(days: 30)).toUtc().toIso8601String(),
        'file_size_bytes': fileSizeBytes,
      });

      if (kDebugMode) {
        print("تم نقل الملف لسلة المحذوفات مؤقتاً لمدة 30 يوماً: $filePath");
      }
    }
  }

  // دالة مساعدة لحساب حجم الملف المخزن في Supabase Storage
  static Future<int?> _getFileSizeInStorage(String bucket, String filePath) async {
    try {
      final List<FileObject> list = await SupabaseService.client.storage.from(bucket).list(
        path: p.dirname(filePath),
        searchOptions: const SearchOptions(limit: 100),
      );
      final filename = p.basename(filePath);
      for (var f in list) {
        if (f.name == filename) {
          return f.metadata?['size'] as int?;
        }
      }
    } catch (_) {}
    return null;
  }
}
