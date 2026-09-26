// روابط الملفات الخاصة (المستندات، التعهدات، مرفقات الإجازات).
//
// الحاويات employee-documents و loan-pledges و documents خاصة: الرابط المحفوظ
// في القاعدة (بصيغة /object/public/...) لا يفتح بدون صلاحية. هنا نحوّله لرابط
// موقّع مؤقت، والسيرفر يتحقق أن الطالب صاحب الملف أو أدمن (أو مدير لمرفق إجازة).

import 'package:flutter/material.dart';

import 'supabase_service.dart';

class StorageLinks {
  StorageLinks._();

  static const privateBuckets = {'employee-documents', 'loan-pledges', 'documents'};
  static final _pattern = RegExp(r'/storage/v1/object/(?:public|sign|authenticated)/([^/]+)/([^?]+)');
  static final _cache = <String, ({String url, DateTime expires})>{};

  /// (الحاوية، المسار) لرابط ملف خاص، أو null إذا كان الملف عاماً (مثل الصورة الشخصية).
  @visibleForTesting
  static ({String bucket, String path})? parse(String url) {
    final m = _pattern.firstMatch(url);
    if (m == null || !privateBuckets.contains(m.group(1))) return null;
    return (bucket: m.group(1)!, path: Uri.decodeComponent(m.group(2)!));
  }

  static bool isPrivate(String url) => parse(url) != null;

  /// رابط قابل للفتح الآن. [validity] أطول عند المشاركة مع جهة خارجية.
  static Future<String> resolve(String url, {Duration validity = const Duration(hours: 1)}) async {
    final ref = parse(url);
    if (ref == null) return url;

    final key = '${validity.inSeconds}|$url';
    final hit = _cache[key];
    if (hit != null && hit.expires.isAfter(DateTime.now())) return hit.url;

    final signed = await SupabaseService.client.storage.from(ref.bucket).createSignedUrl(ref.path, validity.inSeconds);
    _cache[key] = (url: signed, expires: DateTime.now().add(validity - const Duration(minutes: 5)));
    return signed;
  }

  static void clearCache() => _cache.clear();
}

/// صورة من ملف قد يكون خاصاً: تجلب الرابط الموقّع أولاً.
class SignedNetworkImage extends StatelessWidget {
  const SignedNetworkImage(
    this.url, {
    super.key,
    this.fit,
    this.width,
    this.height,
    this.cacheWidth,
    this.errorBuilder,
    this.loadingBuilder,
  });

  final String url;
  final BoxFit? fit;
  final double? width;
  final double? height;
  final int? cacheWidth;
  final ImageErrorWidgetBuilder? errorBuilder;
  final ImageLoadingBuilder? loadingBuilder;

  @override
  Widget build(BuildContext context) {
    if (!StorageLinks.isPrivate(url)) return _image(url);
    return FutureBuilder<String>(
      future: StorageLinks.resolve(url),
      builder: (context, snap) {
        if (snap.hasData) return _image(snap.data!);
        if (snap.hasError) {
          return errorBuilder?.call(context, snap.error!, null) ?? const Center(child: Icon(Icons.broken_image_rounded));
        }
        return SizedBox(width: width, height: height, child: const Center(child: CircularProgressIndicator(strokeWidth: 2)));
      },
    );
  }

  Widget _image(String src) => Image.network(
        src,
        fit: fit,
        width: width,
        height: height,
        cacheWidth: cacheWidth,
        errorBuilder: errorBuilder,
        loadingBuilder: loadingBuilder,
      );
}
