// منطق شاشة الإعدادات بدون واجهة.

/// مسار الصورة الشخصية داخل حاوية avatars من رابطها العام، حتى تُحذف القديمة بعد التبديل.
/// التنسيق: /storage/v1/object/public/avatars/YOUR_OLD_PATH — رابط فارغ أو غير مطابق = null.
String? avatarStoragePath(String avatarUrl) {
  String? oldPath;
  if (avatarUrl.isNotEmpty) {
    try {
      final uri = Uri.parse(avatarUrl);
      final segments = uri.pathSegments;
      final int avatarsIndex = segments.indexOf('avatars');
      if (avatarsIndex != -1 && avatarsIndex + 1 < segments.length) {
        oldPath = segments.sublist(avatarsIndex + 1).join('/');
      }
    } catch (_) {}
  }
  return oldPath;
}
