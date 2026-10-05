import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/design/design.dart';
import '../../../core/utils/app_log.dart';
import 'app_overlays.dart';

/// اختيار صور من الكاميرا أو المعرض، مع رسالة واضحة وزر "الإعدادات" إذا الصلاحية مرفوضة.
/// الآيفون ما يعيد طلب صلاحية الكاميرا بعد أول رفض، والمكتبة ترمي خطأ؛ بدون هذا يبقى الزر ما يسوي شي
/// (مثلاً تصوير تعهد السلفة الإلزامي).
abstract final class AppImagePicker {
  static Future<XFile?> pickOne(BuildContext context, {required ImageSource source, int? imageQuality}) =>
      _guard<XFile?>(context, () => ImagePicker().pickImage(source: source, imageQuality: imageQuality));

  static Future<List<XFile>> pickMany(BuildContext context) async =>
      await _guard(context, () => ImagePicker().pickMultiImage()) ?? const [];

  static Future<T?> _guard<T>(BuildContext context, Future<T> Function() pick) async {
    try {
      return await pick();
    } on PlatformException catch (e) {
      appLog('image picker: ${e.code} ${e.message}');
      if (context.mounted) AppSnack.show(context, errorMessage(e.code), tone: AppTone.danger, actionLabel: needsSettings(e.code) ? 'الإعدادات' : null, onAction: openAppSettings);
      return null;
    }
  }

  /// الصلاحية مرفوضة أو مقيّدة — الحل الوحيد من إعدادات الهاتف.
  @visibleForTesting
  static bool needsSettings(String code) => code.endsWith('_access_denied') || code.endsWith('_access_restricted');

  @visibleForTesting
  static String errorMessage(String code) {
    if (!needsSettings(code)) return 'تعذّر فتح الكاميرا أو الصور. حاول مرة ثانية.';
    return code.startsWith('camera')
        ? 'صلاحية الكاميرا مرفوضة لتطبيق HR Pro. فعّلها من إعدادات الهاتف.'
        : 'صلاحية الصور مرفوضة لتطبيق HR Pro. فعّلها من إعدادات الهاتف.';
  }
}
