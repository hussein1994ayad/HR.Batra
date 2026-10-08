// =========================================================================
// HR Pro — الإعدادات: الملف الشخصي، الإشعارات، الوثائق، أمان الجهاز، الخروج
// =========================================================================

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/constants.dart';
import '../../../core/models/models.dart';
import '../../../core/routes/app_router.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/device_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/share_helper.dart';
import '../../../core/services/storage_links.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/utils/app_log.dart';
import '../../../core/utils/error_text.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../shared/ui/ui.dart';
import 'settings_logic.dart';
import 'widgets/settings_widgets.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final ProfileRepository _repo = ProfileRepository();
  String _employeeName = 'جاري التحميل...';
  String _email = '...';
  String _phone = '...';
  String _employeeCode = '...';
  String _avatarUrl = '';
  String _deviceUUID = 'جاري التحميل...';
  String _deviceModel = 'جاري التحميل...';
  String _osVersion = 'جاري التحميل...';
  List<String> _documentUrls = [];
  bool _notificationPermissionGranted = false;

  bool _isLoading = true;
  bool _isUploadingAvatar = false;
  bool _isUploadingDoc = false;
  bool _deletionBusy = false;
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _loadProfileAndDevice();
    _checkNotificationPermission();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _appVersion = '${info.version} (${info.buildNumber})');
    } catch (_) {}
  }

  Future<void> _checkNotificationPermission() async {
    final granted = await NotificationService.isPermissionGranted();
    if (mounted) setState(() => _notificationPermissionGranted = granted);
  }

  // تحميل ملف الموظف الشخصي ومعلومات حماية جهازه المقفل
  Future<void> _loadProfileAndDevice() async {
    setState(() => _isLoading = true);
    final user = SupabaseService.currentUser;
    if (user == null) return;

    try {
      // 1. جلب معلومات الموظف من الـ view الآمن
      final data = await _repo.fetchProfile(user.id);

      if (data != null && mounted) {
        setState(() {
          _employeeName = (data['full_name'] ?? 'موظف') as String;
          _email = (data['email'] ?? 'name@company.com') as String;
          _phone = (data['phone'] ?? 'لا يوجد هاتف مسجل') as String;
          _employeeCode = (data['employee_code'] ?? 'EMP-000') as String;
          _avatarUrl = (data['avatar_url'] ?? '') as String;
          if (data['document_urls'] != null) {
            _documentUrls = List<String>.from(data['document_urls'] as Iterable<dynamic>);
          }
        });
      }

      // 2. جلب معرّفات الجهاز المقفل للحماية المتقدمة
      final uuid = await DeviceService.getDeviceUUID();
      final model = await DeviceService.getDeviceModel();
      final os = await DeviceService.getOSVersion();

      if (mounted) {
        setState(() {
          _deviceUUID = uuid;
          _deviceModel = model;
          _osVersion = os;
        });
      }
    } catch (e) {
      appLog('خطأ في تحميل ملف الموظف: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // تحديث الصورة الشخصية (الأفاتار) مع ضغطها تلقائياً واستبدال القديمة فورياً لتنظيف الـ Storage
  Future<void> _updateAvatar() async {
    final pickedFile = await AppImagePicker.pickOne(context, source: ImageSource.gallery, imageQuality: 80);

    if (pickedFile == null) return;

    setState(() => _isUploadingAvatar = true);
    final user = SupabaseService.currentUser;
    if (user == null) return;

    try {
      final file = File(pickedFile.path);
      final fileExtension = file.path.split('.').last;

      // استخراج المسار القديم للأفاتار لحذفه تلقائياً
      final String? oldPath = avatarStoragePath(_avatarUrl);

      final remotePath = '${user.id}/${DateTime.now().millisecondsSinceEpoch}.$fileExtension';

      // 1. رفع الصورة الشخصية الجديدة المضغوطة إلى التخزين أولاً دون مسح الصورة القديمة
      final newAvatarUrl = await _repo.uploadAvatar(file, remotePath);

      // 2. تحديث رابط الصورة في جدول الموظفين في قاعدة البيانات
      await _repo.updateAvatarUrl(user.id, newAvatarUrl);

      // 3. التحقق والتأكد من نجاح التحديث في قاعدة البيانات، ثم حذف الصورة القديمة بأمان من التخزين
      if (oldPath != null && oldPath.isNotEmpty && oldPath != remotePath) {
        try {
          await _repo.removeAvatarObject(oldPath);
        } catch (storageErr) {
          appLog('تحذير: تعذر حذف الصورة القديمة من التخزين بعد التحديث: $storageErr');
        }
      }

      setState(() {
        _avatarUrl = newAvatarUrl;
      });

      if (mounted) {
        AppSnack.success(context, 'تم تحديث صورتك الشخصية');
      }
    } catch (e) {
      if (mounted) {
        AppSnack.error(context, 'تعذّر رفع الصورة: $e');
      }
    } finally {
      if (mounted) setState(() => _isUploadingAvatar = false);
    }
  }

  // إضافة مستمسك: الموظف يضيف فقط، والتعديل أو الحذف من قسم الموارد البشرية
  Future<void> _addDocument() async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    final picked = await AppImagePicker.pickOne(context, source: ImageSource.gallery, imageQuality: 80);
    if (picked == null) return;
    if (!mounted) return;
    final ok = await showAppConfirm(
      context,
      title: 'إضافة المستمسك؟',
      message: 'بعد الإضافة ما تكدر تحذفه أو تغيّره بنفسك؛ التعديل من قسم الموارد البشرية.',
      confirmLabel: 'إضافة',
    );
    if (!ok) return;

    setState(() => _isUploadingDoc = true);
    try {
      final url = await _repo.uploadDocument(user.id, File(picked.path));
      final updated = [..._documentUrls, url];
      await _repo.updateDocumentUrls(user.id, updated);
      if (mounted) {
        setState(() => _documentUrls = updated);
        AppSnack.success(context, 'انضاف المستمسك');
      }
    } catch (e) {
      if (mounted) AppSnack.error(context, 'تعذّرت الإضافة: ${errorText(e)}');
    } finally {
      if (mounted) setState(() => _isUploadingDoc = false);
    }
  }

  bool get _isAdminOrManager => Roles.canManage(AuthService.currentUserRole);

  // معاينة الوثيقة ومشاركتها
  Future<void> _previewDocument(String url) async {
    await showAppSheet<void>(
      context,
      title: 'الوثيقة',
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: AppRadius.card,
            child: Container(
              constraints: const BoxConstraints(maxHeight: 360),
              color: AppColors.surface2,
              child: SignedNetworkImage(
                url,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) =>
                    const EmptyView(title: 'ملف PDF أو مستند', icon: Icons.picture_as_pdf_rounded, tone: AppTone.accent, compact: true),
              ),
            ),
          ),
          const SizedBox(height: AppSpace.lg),
          AppButton(
            label: 'مشاركة أو تنزيل',
            icon: Icons.ios_share_rounded,
            expand: true,
            onPressed: () async {
              Navigator.pop(ctx);
              await ShareHelper.shareLink(url, context);
            },
          ),
        ],
      ),
    );
  }

  // تسجيل الخروج
  Future<void> _handleLogout() async {
    final router = GoRouter.of(context);
    final ok = await showAppConfirm(
      context,
      title: 'تسجيل الخروج؟',
      message: 'تقدر ترجع تدخل بنفس حسابك من هذا الجهاز.',
      confirmLabel: 'خروج',
      destructive: true,
    );
    if (!ok) return;
    await AuthService.signOut();
    router.go(AppRoutes.login);
  }

  // طلب حذف الحساب — ممنوع إذا عليه سلفة غير مسددة
  Future<void> _handleDeleteAccountRequest() async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    setState(() => _deletionBusy = true);

    try {
      final totalRemaining = await _repo.fetchApprovedLoansRemaining(user.id);
      if (!mounted) return;

      if (totalRemaining > 0) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('لا يمكن حذف الحساب الآن'),
            content: Text('عليك سلفة غير مسددة بقيمة ${AppConstants.formatMoney(totalRemaining)}. سدّد الأقساط أو راجع الإدارة أولاً.'),
            actions: [AppButton(label: 'حسناً', onPressed: () => Navigator.pop(ctx))],
          ),
        );
        return;
      }

      final ok = await showAppConfirm(
        context,
        title: 'طلب حذف الحساب؟',
        message: 'راح يوصل طلبك للمدير العام لمراجعته والموافقة عليه.',
        confirmLabel: 'إرسال الطلب',
        destructive: true,
      );
      if (!ok) return;

      // الدالة ترسل الطلب لكل الأدمنية (الموظف لا يرى حساباتهم بسبب RLS)
      await _repo.requestAccountDeletion();
      if (mounted) AppSnack.success(context, 'وصل طلب حذف الحساب للإدارة');
    } catch (e) {
      appLog('Failed to submit deletion request: $e');
      if (mounted) AppSnack.error(context, 'تعذّر إرسال الطلب، حاول لاحقاً');
    } finally {
      if (mounted) setState(() => _deletionBusy = false);
    }
  }

  Future<void> _enableNotifications() async {
    final granted = await NotificationService.requestPermissionAndSaveToken();
    if (!mounted) return;
    setState(() => _notificationPermissionGranted = granted);
    if (!granted) await openAppSettings();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const AppPage(
        title: 'الإعدادات',
        showBack: false,
        body: Column(
          children: [
            Skeleton(height: 180, radius: AppRadius.md),
            SizedBox(height: AppSpace.lg),
            SkeletonList(count: 3),
          ],
        ),
      );
    }

    return AppPage(
      title: 'الإعدادات',
      showBack: false,
      onRefresh: () async {
        await _loadProfileAndDevice();
        await _checkNotificationPermission();
      },
      slivers: [
        SliverList.list(
          children: [
            SettingsProfileCard(
              name: _employeeName,
              avatarUrl: _avatarUrl,
              code: _employeeCode,
              email: _email,
              phone: _phone,
              uploading: _isUploadingAvatar,
              onChangeAvatar: _updateAvatar,
            ),
            const SectionHeader('الإشعارات'),
            SettingsNotificationsCard(granted: _notificationPermissionGranted, onEnable: _enableNotifications),
            const SectionHeader('وثائقي'),
            SettingsDocumentsCard(urls: _documentUrls, uploading: _isUploadingDoc, onOpen: _previewDocument, onAdd: _addDocument),
            const SectionHeader('الخدمات'),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
              child: Column(
                children: [
                  AppListTile(
                    leading: const ToneIcon(Icons.receipt_long_rounded, tone: AppTone.success),
                    title: 'كشوف الرواتب',
                    subtitle: 'تفاصيل راتبك الشهري',
                    onTap: () => context.push(AppRoutes.employeePayslips),
                  ),
                  AppListTile(
                    leading: const ToneIcon(Icons.groups_rounded, tone: AppTone.info),
                    title: 'دليل الموظفين',
                    onTap: () => context.push(AppRoutes.employeeDirectory),
                  ),
                  if (_isAdminOrManager) ...[
                    const Divider(indent: AppSpace.lg, endIndent: AppSpace.lg),
                    AppListTile(
                      leading: const ToneIcon(Icons.admin_panel_settings_rounded, tone: AppTone.accent),
                      title: 'لوحة الإدارة',
                      onTap: () => context.push(AppRoutes.adminDashboard),
                    ),
                    AppListTile(
                      leading: const ToneIcon(Icons.location_searching_rounded, tone: AppTone.accent),
                      title: 'التتبع الحي للموظفين',
                      onTap: () => context.push(AppRoutes.adminTracking),
                    ),
                    // السلف للأدمن فقط (مدير الفرع ما يعتمد سلف — نفس الموقع)
                    if (Roles.isAdmin(AuthService.currentUserRole)) ...[
                      AppListTile(
                        leading: const ToneIcon(Icons.table_chart_rounded, tone: AppTone.accent),
                        title: 'سلف الموظفين وكشوف Excel',
                        onTap: () => context.push(AppRoutes.adminLoans),
                      ),
                      AppListTile(
                        leading: const ToneIcon(Icons.auto_awesome_rounded, tone: AppTone.accent),
                        title: 'المساعد الذكي',
                        subtitle: 'اسأل عن الدوام والخصومات والسلف، وملفات Excel',
                        onTap: () => context.push(AppRoutes.adminAssistant),
                      ),
                    ],
                  ],
                ],
              ),
            ),
            const SectionHeader('الجهاز والأمان'),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('حسابك مربوط بهذا الجهاز. الدخول من هاتف ثاني يحتاج موافقة الإدارة.', style: AppText.bodySm),
                  const SizedBox(height: AppSpace.sm),
                  KeyValueRow('الجهاز', _deviceModel, icon: Icons.phone_android_rounded),
                  KeyValueRow('النظام', _osVersion, icon: Icons.memory_rounded),
                  Row(
                    children: [
                      Expanded(child: KeyValueRow('معرّف الجهاز', _deviceUUID, icon: Icons.fingerprint_rounded)),
                      IconButton(
                        tooltip: 'نسخ المعرّف',
                        icon: const Icon(Icons.copy_rounded, size: 18),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: _deviceUUID));
                          AppSnack.info(context, 'نُسخ معرّف الجهاز');
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SectionHeader('حول التطبيق'),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
              child: Column(
                children: [
                  AppListTile(
                    leading: const ToneIcon(Icons.privacy_tip_outlined, tone: AppTone.neutral),
                    title: 'سياسة الخصوصية',
                    subtitle: 'ما البيانات التي نجمعها ولماذا',
                    onTap: () => launchUrl(Uri.parse(AppConstants.privacyPolicyUrl), mode: LaunchMode.externalApplication),
                  ),
                  AppListTile(
                    leading: const ToneIcon(Icons.info_outline_rounded, tone: AppTone.neutral),
                    title: 'الإصدار',
                    trailing: Text(_appVersion, style: AppText.bodySm),
                    showChevron: false,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.xxl),
            AppButton.secondary(label: 'تسجيل الخروج', icon: Icons.logout_rounded, expand: true, onPressed: _handleLogout),
            const SizedBox(height: AppSpace.sm),
            AppButton(
              label: 'طلب حذف الحساب',
              icon: Icons.person_remove_outlined,
              variant: AppButtonVariant.dangerGhost,
              expand: true,
              loading: _deletionBusy,
              onPressed: _handleDeleteAccountRequest,
            ),
          ],
        ),
      ],
    );
  }
}
