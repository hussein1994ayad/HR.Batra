// مشاركة موحّدة: روابط الملفات الخاصة تُحوَّل لروابط موقّعة، ومكان نافذة المشاركة
// يُحدَّد دائماً (إلزامي على iPad وإلا ينهار التطبيق).

import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';

import 'storage_links.dart';

class ShareHelper {
  ShareHelper._();

  /// صلاحية الروابط المُرسلة لجهة خارجية.
  static const sharedLinkValidity = Duration(days: 7);

  /// موضع نافذة المشاركة: العنصر الذي ضُغط إن وُجد، وإلا منتصف الشاشة.
  static Rect origin([BuildContext? context]) {
    final box = context?.findRenderObject();
    if (box is RenderBox && box.hasSize) {
      return box.localToGlobal(Offset.zero) & box.size;
    }
    final view = ui.PlatformDispatcher.instance.views.first;
    final size = view.physicalSize / view.devicePixelRatio;
    return Rect.fromCenter(center: size.center(Offset.zero), width: 1, height: 1);
  }

  static Future<void> shareParams(ShareParams params, [BuildContext? context]) =>
      SharePlus.instance.share(ShareParams(
        text: params.text,
        subject: params.subject,
        title: params.title,
        uri: params.uri,
        files: params.files,
        fileNameOverrides: params.fileNameOverrides,
        sharePositionOrigin: params.sharePositionOrigin ?? origin(context),
      ));

  /// يشارك رابط ملف (خاص أو عام).
  static Future<void> shareLink(String url, [BuildContext? context]) async {
    final at = origin(context);
    final link = await StorageLinks.resolve(url, validity: sharedLinkValidity);
    await shareParams(ShareParams(uri: Uri.parse(link), sharePositionOrigin: at));
  }

  /// يشارك عدة روابط كنص واحد.
  static Future<void> shareLinks(List<String> urls, {String? subject, BuildContext? context}) async {
    final at = origin(context);
    final links = await Future.wait(urls.map((u) => StorageLinks.resolve(u, validity: sharedLinkValidity)));
    await shareParams(ShareParams(text: links.join('\n'), subject: subject, sharePositionOrigin: at));
  }
}
