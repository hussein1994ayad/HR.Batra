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

import '../../core/constants/constants.dart';
import '../../core/routes/app_router.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/device_service.dart';
import '../../core/services/file_upload_service.dart';
import '../../core/services/notification_service.dart';
import '../../core/services/share_helper.dart';
import '../../core/services/storage_links.dart';
import '../../core/services/supabase_service.dart';
import '../../core/utils/error_text.dart';
import '../shared/ui/ui.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
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
      final data = await SupabaseService.client.from('v_employee_directory').select().eq('id', user.id).maybeSingle();

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
      debugPrint('خطأ في تحميل ملف الموظف: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // تحديث الصورة الشخصية (الأفاتار) مع ضغطها تلقائياً واستبدال القديمة فورياً لتنظيف الـ Storage
  Future<void> _updateAvatar() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);

    if (pickedFile == null) return;

    setState(() => _isUploadingAvatar = true);
    final user = SupabaseService.currentUser;
    if (user == null) return;

    try {
      final file = File(pickedFile.path);
      final fileExtension = file.path.split('.').last;

      // استخراج المسار القديم للأفاتار لحذفه تلقائياً
      String? oldPath;
      if (_avatarUrl.isNotEmpty) {
        try {
          final uri = Uri.parse(_avatarUrl);
          final segments = uri.pathSegments;
          // التنسيق: /storage/v1/object/public/avatars/YOUR_OLD_PATH
          final int avatarsIndex = segments.indexOf('avatars');
          if (avatarsIndex != -1 && avatarsIndex + 1 < segments.length) {
            oldPath = segments.sublist(avatarsIndex + 1).join('/');
          }
        } catch (_) {}
      }

      final remotePath = '${user.id}/${DateTime.now().millisecondsSinceEpoch}.$fileExtension';

      // 1. رفع الصورة الشخصية الجديدة المضغوطة إلى التخزين أولاً دون مسح الصورة القديمة
      final newAvatarUrl = await FileUploadService.uploadFile(file: file, bucketName: 'avatars', remotePath: remotePath);

      // 2. تحديث رابط الصورة في جدول الموظفين في قاعدة البيانات
      await SupabaseService.client.from('employees').update({'avatar_url': newAvatarUrl}).eq('id', user.id);

      // 3. التحقق والتأكد من نجاح التحديث في قاعدة البيانات، ثم حذف الصورة القديمة بأمان من التخزين
      if (oldPath != null && oldPath.isNotEmpty && oldPath != remotePath) {
        try {
          await SupabaseService.client.storage.from('avatars').remove([oldPath]);
        } catch (storageErr) {
          debugPrint('تحذير: تعذر حذف الصورة القديمة من التخزين بعد التحديث: $storageErr');
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
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
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
      final file = File(picked.path);
      final ext = file.path.split('.').last;
      final url = await FileUploadService.uploadFile(
        file: file,
        bucketName: 'employee-documents',
        remotePath: '${user.id}/${DateTime.now().millisecondsSinceEpoch}.$ext',
      );
      final updated = [..._documentUrls, url];
      await SupabaseService.client.from('employees').update({'document_urls': updated}).eq('id', user.id);
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

  bool get _isAdminOrManager => AuthService.currentUserRole == 'admin' || AuthService.currentUserRole == 'manager';

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
      final loans = await SupabaseService.client.from('loans').select('remaining_amount').eq('employee_id', user.id).eq('status', 'approved');

      double totalRemaining = 0.0;
      for (final loan in loans) {
        totalRemaining += (loan['remaining_amount'] as num?)?.toDouble() ?? 0.0;
      }
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
      await SupabaseService.client.rpc<dynamic>('request_account_deletion');
      if (mounted) AppSnack.success(context, 'وصل طلب حذف الحساب للإدارة');
    } catch (e) {
      debugPrint('Failed to submit deletion request: $e');
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
            _buildProfileCard(),
            const SectionHeader('الإشعارات'),
            _buildNotificationsCard(),
            const SectionHeader('وثائقي'),
            _buildDocuments(),
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
                    AppListTile(
                      leading: const ToneIcon(Icons.table_chart_rounded, tone: AppTone.accent),
                      title: 'سلف الموظفين وكشوف Excel',
                      onTap: () => context.push(AppRoutes.adminLoans),
                    ),
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

  Widget _buildProfileCard() {
    return AppCard(
      padding: const EdgeInsets.all(AppSpace.xl),
      child: Column(
        children: [
          Semantics(
            button: true,
            label: 'تغيير الصورة الشخصية',
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _isUploadingAvatar ? null : _updateAvatar,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  AppAvatar(name: _employeeName, url: _avatarUrl, size: 88),
                  PositionedDirectional(
                    bottom: -2,
                    end: -2,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppColors.brand,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.surface1, width: 3),
                      ),
                      child: _isUploadingAvatar
                          ? const Padding(
                              padding: EdgeInsets.all(6),
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onBrand),
                            )
                          : const Icon(Icons.photo_camera_rounded, size: 16, color: AppColors.onBrand),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpace.md),
          Text(_employeeName, style: AppText.title, textAlign: TextAlign.center),
          const SizedBox(height: AppSpace.xs),
          StatusBadge(_employeeCode, tone: AppTone.brand, icon: Icons.badge_outlined),
          const SizedBox(height: AppSpace.lg),
          const Divider(),
          KeyValueRow('البريد', _email, icon: Icons.alternate_email_rounded),
          KeyValueRow('الهاتف', _phone, icon: Icons.phone_outlined),
        ],
      ),
    );
  }

  Widget _buildNotificationsCard() {
    final granted = _notificationPermissionGranted;
    return AppCard(
      tone: granted ? null : AppTone.warning,
      child: Row(
        children: [
          ToneIcon(granted ? Icons.notifications_active_rounded : Icons.notifications_off_rounded, tone: granted ? AppTone.success : AppTone.warning),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(granted ? 'الإشعارات مفعّلة' : 'الإشعارات متوقفة', style: AppText.subtitle),
                Text(granted ? 'توصلك القرارات وتذكيرات البصمة.' : 'فعّلها حتى توصلك القرارات والتذكيرات.', style: AppText.caption),
              ],
            ),
          ),
          if (!granted) AppButton(label: 'تفعيل', size: AppButtonSize.small, onPressed: _enableNotifications),
        ],
      ),
    );
  }

  Widget _buildDocuments() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpace.md,
            runSpacing: AppSpace.md,
            children: [
              for (final url in _documentUrls)
                Semantics(
                  button: true,
                  label: 'فتح وثيقة',
                  child: InkWell(
                    onTap: () => _previewDocument(url),
                    borderRadius: AppRadius.control,
                    child: ClipRRect(
                      borderRadius: AppRadius.control,
                      child: Container(
                        width: 72,
                        height: 72,
                        color: AppColors.surface2,
                        child: SignedNetworkImage(
                          url,
                          fit: BoxFit.cover,
                          cacheWidth: 216,
                          errorBuilder: (_, __, ___) => const Icon(Icons.picture_as_pdf_rounded, color: AppColors.accent),
                        ),
                      ),
                    ),
                  ),
                ),
              Semantics(
                button: true,
                label: 'إضافة مستمسك',
                child: InkWell(
                  onTap: _isUploadingDoc ? null : _addDocument,
                  borderRadius: AppRadius.control,
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      borderRadius: AppRadius.control,
                      border: Border.all(color: AppColors.borderStrong),
                    ),
                    child: _isUploadingDoc
                        ? const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                        : const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_rounded, color: AppColors.brand),
                              Text('إضافة', style: AppText.caption),
                            ],
                          ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          const Text('تقدر تضيف مستمسكات جديدة؛ تعديلها أو حذفها من قسم الموارد البشرية.', style: AppText.caption),
        ],
      ),
    );
  }
}
