// =========================================================================
// نظام HR Pro v6.0 - خدمة التحديثات الهوائية (OTA Service)
// =========================================================================

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'supabase_service.dart';
import '../theme/app_theme.dart';

/// الحالات المختلفة لفحص تحديث التطبيق
enum OtaStatus {
  upToDate,
  optionalUpdate,
  mandatoryUpdate,
  failed,
}

/// خدمة لإدارة وفحص وتنزيل التحديثات الهوائية (OTA Updates) للحد من استخدام الإصدارات القديمة
class OtaService {
  
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
      final String latestVersionName = latestRelease['version_name'] ?? '1.0.0';
      final bool isMandatory = latestRelease['is_mandatory'] ?? false;
      final String apkUrl = latestRelease['apk_url'] ?? '';
      final String releaseNotes = latestRelease['release_notes'] ?? 'تحديث أمان وإصلاحات عامة';

      // 3. مقارنة الإصدار الحالي بالإصدار الأخير
      if (latestVersionCode > currentVersionCode) {
        return {
          'status': isMandatory ? OtaStatus.mandatoryUpdate : OtaStatus.optionalUpdate,
          'current_version': currentVersionName,
          'latest_version': latestVersionName,
          'download_url': apkUrl,
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

  /// إظهار نافذة التنبيه للتحديث (حوار غير قابل للإلغاء في حال التحديث الإجباري)
  static void showUpdatePrompt(BuildContext context, Map<String, dynamic> updateInfo) {
    final bool isMandatory = updateInfo['is_mandatory'] ?? false;
    final String latestVersion = updateInfo['latest_version'] ?? '1.0.0';
    final String releaseNotes = updateInfo['release_notes'] ?? '';
    final String downloadUrl = updateInfo['download_url'] ?? '';

    showDialog(
      context: context,
      barrierDismissible: !isMandatory, // منع الإغلاق بالنقر في الخارج للمجبر
      builder: (BuildContext context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        
        return PopScope(
          canPop: !isMandatory, // منع الرجوع بزر الهاتف الخلفي للمجبر
          child: Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            elevation: 16,
            backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // أيقونة التحديث اللامعة
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isMandatory 
                            ? AppTheme.dangerRed.withAlpha(25) 
                            : AppTheme.primaryTeal.withAlpha(25),
                      ),
                      child: Icon(
                        isMandatory ? Icons.system_update_alt : Icons.cloud_download,
                        size: 48,
                        color: isMandatory ? AppTheme.dangerRed : AppTheme.primaryTeal,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // عنوان التحديث
                  Text(
                    isMandatory ? 'تحديث إجباري مطلوب ⚠️' : 'يتوفر إصدار جديد للتطبيق 🎉',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: isMandatory ? AppTheme.dangerRed : AppTheme.primaryTeal,
                      fontFamily: 'Cairo',
                    ),
                  ),
                  const SizedBox(height: 8),
                  
                  // معلومات الإصدار
                  Text(
                    'الإصدار المتاح: v$latestVersion',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.grey[300] : Colors.grey[700],
                      fontFamily: 'Cairo',
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // تفاصيل التحديث
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF0F172A) : Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'ملاحظات الإصدار الجديد:',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryTeal,
                            fontFamily: 'Cairo',
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          releaseNotes,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.5,
                            color: isDark ? Colors.grey[400] : Colors.grey[800],
                            fontFamily: 'Cairo',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // أزرار التحكم
                  Row(
                    children: [
                      // زر التحديث الفوري
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () async {
                            if (downloadUrl.isNotEmpty) {
                              final Uri uri = Uri.parse(downloadUrl);
                              if (await canLaunchUrl(uri)) {
                                await launchUrl(uri, mode: LaunchMode.externalApplication);
                              }
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isMandatory ? AppTheme.dangerRed : AppTheme.primaryTeal,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'تحديث الآن ⚡',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              fontFamily: 'Cairo',
                            ),
                          ),
                        ),
                      ),
                      
                      // زر التأجيل (فقط في حال لم يكن التحديث إجبارياً)
                      if (!isMandatory) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              side: BorderSide(
                                color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                              ),
                            ),
                            child: Text(
                              'لا حقاً',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.grey[400] : Colors.grey[600],
                                fontFamily: 'Cairo',
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
