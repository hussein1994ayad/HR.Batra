// =========================================================================
// نظام HR Pro v6.0 - خدمة ضغط الصور والملفات الذكية (Image Compression Service)
// =========================================================================

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../constants/constants.dart';

class ImageCompressionService {
  // هل الملف الممرر صورة؟
  static bool isImage(String filePath) {
    final extension = p.extension(filePath).toLowerCase();
    return extension == '.jpg' || extension == '.jpeg' || extension == '.png' || extension == '.webp';
  }

  // ضغط الصورة تلقائياً وإرجاع الملف الجديد المضغوط مع حذف EXIF
  static Future<File> compressImage(File file) async {
    final filePath = file.path;

    // إذا لم يكن الملف صورة (مثل PDF أو Excel)، يتم إرجاعه كما هو دون أي تغيير
    if (!isImage(filePath)) {
      if (kDebugMode) {
        print("الملف ليس صورة، سيتم رفعه دون ضغط: ${p.basename(filePath)}");
      }
      return file;
    }

    try {
      final originalSize = await file.length();
      if (kDebugMode) {
        print("حجم الصورة الأصلي: ${(originalSize / 1024).toStringAsFixed(2)} كيلوبايت");
      }

      // الحصول على مجلد التخزين المؤقت (Temporary Directory) لحفظ الصورة المضغوطة مؤقتاً
      final tempDir = await getTemporaryDirectory();
      final targetPath = p.join(
        tempDir.path, 
        'compressed_${DateTime.now().millisecondsSinceEpoch}${p.extension(filePath).toLowerCase() == '.png' ? '.png' : '.jpg'}'
      );

      // استدعاء مكتبة الضغط مع تطبيق المعايير
      final XFile? compressedXFile = await FlutterImageCompress.compressAndGetFile(
        filePath,
        targetPath,
        minWidth: AppConstants.maxImageWidthHeight,
        minHeight: AppConstants.maxImageWidthHeight,
        quality: AppConstants.imageQuality,
        keepExif: false, // تعني إزالة بيانات EXIF (مثل إحداثيات GPS الملتقطة بالكاميرا لأمن الخصوصية)
        format: p.extension(filePath).toLowerCase() == '.png' ? CompressFormat.png : CompressFormat.jpeg,
      );

      if (compressedXFile == null) {
        if (kDebugMode) {
          print("فشل ضغط الصورة، سيتم استخدام الملف الأصلي كبديل.");
        }
        return file;
      }

      final compressedFile = File(compressedXFile.path);
      final compressedSize = await compressedFile.length();
      final spaceSaved = ((originalSize - compressedSize) / originalSize) * 100;

      if (kDebugMode) {
        print("حجم الصورة بعد الضغط: ${(compressedSize / 1024).toStringAsFixed(2)} كيلوبايت");
        print("المساحة الموفرة بالسيرفر: ${spaceSaved.toStringAsFixed(1)}%");
      }

      return compressedFile;

    } catch (e) {
      if (kDebugMode) {
        print("حدث خطأ غير متوقع أثناء محاولة ضغط الصورة: $e");
      }
      return file; // إرجاع الصورة الأصلية كخطة بديلة (Fallback) في حال حدوث خطأ مفاجئ
    }
  }
}
