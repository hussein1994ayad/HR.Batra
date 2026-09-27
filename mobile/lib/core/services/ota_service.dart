// =========================================================================
// نظام HR Pro v6.0 - خدمة التحديثات الهوائية (OTA Service)
// =========================================================================

import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/design/design.dart';
import '../constants/constants.dart';
import 'supabase_service.dart';

/// الحالات المختلفة لفحص تحديث التطبيق
enum OtaStatus {
  upToDate,
  optionalUpdate,
  mandatoryUpdate,
  failed,
}

/// خدمة لإدارة وفحص وتنزيل التحديثات الهوائية (OTA Updates) للحد من استخدام الإصدارات القديمة
class OtaService {
  /// رابط التحديث يجب أن يكون HTTPS ومن مصدر معروف:
  /// Android → مجلد ota-updates في Supabase Storage الخاص بالمشروع.
  /// iOS → App Store أو TestFlight.
  /// يمنع توجيه الموظفين لتنزيل APK من أي رابط آخر لو عُدّل جدول app_versions.
  static bool isTrustedDownloadUrl(String url, {required bool isIOS}) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') return false;
    if (isIOS) {
      return const {'apps.apple.com', 'testflight.apple.com'}.contains(uri.host);
    }
    final supabaseHost = Uri.parse(AppConstants.supabaseUrl).host;
    return uri.host == supabaseHost &&
        uri.path.startsWith('/storage/v1/object/public/ota-updates/');
  }

  
  /// التحقق من توافر تحديث جديد مقارنة بجدول `app_versions` بقاعدة البيانات
  static Future<Map<String, dynamic>> checkVersion() async {
    try {
      // 1. جلب بيانات الإصدار الحالي المثبت على الجهاز
      final PackageInfo packageInfo = await PackageInfo.fromPlatform();
      final String currentVersionName = packageInfo.version;
      // في بعض البيئات قد يرجع buildNumber فارغاً، لذا نضمن قيمة افتراضية صحيحة
      final int currentVersionCode = int.tryParse(packageInfo.buildNumber) ?? 1;

      // 2. الاستعلام عن أحدث إصدار متاح في قاعدة بيانات Supabase
      final latestRelease = await SupabaseService.client
          .from('app_versions')
          .select()
          .order('version_code', ascending: false)
          .limit(1)
          .maybeSingle();

      if (latestRelease == null) {
        return {'status': OtaStatus.upToDate};
      }

      final int latestVersionCode = latestRelease['version_code'] as int;
      final String latestVersionName = (latestRelease['version_name'] ?? '1.0.0') as String;
      final bool isMandatory = (latestRelease['is_mandatory'] ?? false) as bool;
      // iOS: رابط App Store/TestFlight فقط (Apple ترفض تنزيل تطبيقات من خارج المتجر)
      final String downloadUrl = (Platform.isIOS
              ? latestRelease['ipa_url']
              : latestRelease['apk_url'])
          ?.toString() ?? '';
      if (!isTrustedDownloadUrl(downloadUrl, isIOS: Platform.isIOS)) {
        debugPrint('OTA: تم تجاهل رابط تحديث غير موثوق: $downloadUrl');
        return {'status': OtaStatus.upToDate};
      }
      final String releaseNotes = (latestRelease['release_notes'] ?? 'تحديث أمان وإصلاحات عامة') as String;

      // 3. مقارنة الإصدار الحالي بالإصدار الأخير
      if (latestVersionCode > currentVersionCode) {
        return {
          'status': isMandatory ? OtaStatus.mandatoryUpdate : OtaStatus.optionalUpdate,
          'current_version': currentVersionName,
          'latest_version': latestVersionName,
          'download_url': downloadUrl,
          'release_notes': releaseNotes,
          'is_mandatory': isMandatory,
        };
      }

      return {'status': OtaStatus.upToDate};
    } catch (e) {
      debugPrint('خطأ أثناء فحص إصدار التطبيق (OTA): $e');
      return {'status': OtaStatus.failed};
    }
  }

  /// نافذة التحديث (لا تُغلق إذا كان التحديث إجبارياً).
  static void showUpdatePrompt(BuildContext context, Map<String, dynamic> updateInfo) {
    final bool isMandatory = (updateInfo['is_mandatory'] ?? false) as bool;
    final String latestVersion = (updateInfo['latest_version'] ?? '1.0.0') as String;
    final String releaseNotes = (updateInfo['release_notes'] ?? '') as String;
    final String downloadUrl = (updateInfo['download_url'] ?? '') as String;
    final Color tone = isMandatory ? AppColors.warning : AppColors.brand;
    final Color toneBg = isMandatory ? AppColors.warningContainer : AppColors.brandContainer;

    showDialog<void>(
      context: context,
      barrierDismissible: !isMandatory,
      builder: (BuildContext context) {
        return PopScope(
          canPop: !isMandatory,
          child: AlertDialog(
            contentPadding: const EdgeInsets.fromLTRB(AppSpace.xxl, AppSpace.xxl, AppSpace.xxl, AppSpace.md),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(color: toneBg, shape: BoxShape.circle),
                    child: Icon(Icons.system_update_rounded, size: 36, color: tone),
                  ),
                ),
                const SizedBox(height: AppSpace.lg),
                Text(isMandatory ? 'تحديث مطلوب' : 'إصدار جديد متوفر', textAlign: TextAlign.center, style: AppText.title),
                const SizedBox(height: AppSpace.xs),
                Text(
                  isMandatory ? 'لازم تحدّث حتى تكمل استعمال التطبيق · v$latestVersion' : 'الإصدار v$latestVersion',
                  textAlign: TextAlign.center,
                  style: AppText.bodySm,
                ),
                if (releaseNotes.isNotEmpty) ...[
                  const SizedBox(height: AppSpace.lg),
                  Container(
                    padding: const EdgeInsets.all(AppSpace.md),
                    decoration: const BoxDecoration(color: AppColors.surface1, borderRadius: AppRadius.control),
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('الجديد', style: AppText.label.copyWith(color: tone)),
                          const SizedBox(height: AppSpace.xs),
                          Text(releaseNotes, style: AppText.bodySm),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
            actionsPadding: const EdgeInsets.fromLTRB(AppSpace.xl, 0, AppSpace.xl, AppSpace.xl),
            actions: [
              if (!isMandatory) TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('لاحقاً')),
              FilledButton.icon(
                onPressed: () async {
                  if (downloadUrl.isNotEmpty) {
                    final Uri uri = Uri.parse(downloadUrl);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  }
                },
                icon: const Icon(Icons.download_rounded),
                label: const Text('تحديث الآن'),
              ),
            ],
          ),
        );
      },
    );
  }
}
