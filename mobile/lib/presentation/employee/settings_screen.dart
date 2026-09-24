// =========================================================================
// نظام HR Pro v6.0 - شاشة الإعدادات والملف الشخصي (Profile & Settings Screen)
// =========================================================================

import 'dart:async';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/constants/constants.dart';
import '../../core/routes/app_router.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/device_service.dart';
import '../../core/services/file_upload_service.dart';
import '../../core/services/notification_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../shared/widgets/glass_container.dart';

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

  @override
  void initState() {
    super.initState();
    _loadProfileAndDevice();
    _checkNotificationPermission();
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
      final data = await SupabaseService.client
          .from('v_employee_directory')
          .select()
          .eq('id', user.id)
          .maybeSingle();

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
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );

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
      final newAvatarUrl = await FileUploadService.uploadFile(
        file: file,
        bucketName: 'avatars',
        remotePath: remotePath,
      );

      // 2. تحديث رابط الصورة في جدول الموظفين في قاعدة البيانات
      await SupabaseService.client
          .from('employees')
          .update({'avatar_url': newAvatarUrl})
          .eq('id', user.id);

      // 3. التحقق والتأكد من نجاح التحديث في قاعدة البيانات، ثم حذف الصورة القديمة بأمان من التخزين
      if (oldPath != null && oldPath.isNotEmpty && oldPath != remotePath) {
        try {
          await SupabaseService.client.storage
              .from('avatars')
              .remove([oldPath]);
        } catch (storageErr) {
          debugPrint('تحذير: تعذر حذف الصورة القديمة من التخزين بعد التحديث: $storageErr');
        }
      }

      setState(() {
        _avatarUrl = newAvatarUrl;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تحديث صورتك الشخصية بنجاح وضغطها أوتوماتيكياً! 📸', style: TextStyle(fontFamily: 'Cairo')),
            backgroundColor: AppTheme.successGreen,
          ),
        );
      }

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل رفع الصورة: $e', style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: AppTheme.dangerRed,
          ),
        );
      }
    } finally {
      setState(() => _isUploadingAvatar = false);
    }
  }

  // Upload Document
  Future<void> _uploadDocument() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (pickedFile == null) return;

    setState(() => _isUploadingDoc = true);
    final user = SupabaseService.currentUser;
    if (user == null) return;

    try {
      final file = File(pickedFile.path);
      final fileExtension = file.path.split('.').last;
      final remotePath = '${user.id}/${DateTime.now().millisecondsSinceEpoch}.$fileExtension';

      final newDocUrl = await FileUploadService.uploadFile(
        file: file,
        bucketName: 'employee-documents',
        remotePath: remotePath,
      );

      final updatedList = List<String>.from(_documentUrls)..add(newDocUrl);

      await SupabaseService.client
          .from('employees')
          .update({'document_urls': updatedList})
          .eq('id', user.id);

      setState(() {
        _documentUrls = updatedList;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم رفع الوثيقة بنجاح وضغطها أوتوماتيكياً! 📄', style: TextStyle(fontFamily: 'Cairo')),
            backgroundColor: AppTheme.successGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل رفع الوثيقة: $e', style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: AppTheme.dangerRed,
          ),
        );
      }
    } finally {
      setState(() => _isUploadingDoc = false);
    }
  }

  // معاينة وفتح وتنزيل الوثيقة
  Future<void> _previewDocument(String url) async {
    unawaited(showDialog<dynamic>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.description_rounded, color: AppTheme.neonCyan, size: 20),
                      SizedBox(width: 8),
                      Text('معاينة الوثيقة المعتمدة 📄', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13)),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white60, size: 18),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 300),
                  color: Colors.black26,
                  child: Image.network(
                    url,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Padding(
                      padding: EdgeInsets.all(30),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.picture_as_pdf_rounded, color: AppTheme.neonPink, size: 48),
                          SizedBox(height: 8),
                          Text('مستند PDF أو ملف رقمي', style: TextStyle(fontFamily: 'Cairo', color: Colors.white70, fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await SharePlus.instance.share(ShareParams(uri: Uri.parse(url)));
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryTeal,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.share_rounded, size: 16),
                      label: const Text('مشاركة / تحميل 📤', style: TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ));
  }

  // Delete Document (مخصص للآدمن والمدراء فقط)
  Future<void> _deleteDocument(String url) async {
    final bool isAdminOrManager = AuthService.currentUserRole == 'admin' || AuthService.currentUserRole == 'manager';
    if (!isAdminOrManager) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('عذراً، حذف الوثائق المعتمدة مخصص للآدمن ومسؤول الـ HR فقط 🔒', style: TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppTheme.dangerRed,
        ),
      );
      return;
    }

    final user = SupabaseService.currentUser;
    if (user == null) return;
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        title: const Text('حذف وثيقة', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: Colors.white)),
        content: const Text('هل أنت متأكد أنك تريد حذف هذه الوثيقة من السيرفر بشكل نهائي؟', style: TextStyle(fontFamily: 'Cairo', color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo', color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.dangerRed),
            onPressed: () => Navigator.pop(context, true), 
            child: const Text('حذف نهائي', style: TextStyle(fontFamily: 'Cairo'))
          ),
        ],
      )
    );
    if (confirm != true) return;

    try {
      String? pathToDelete;
      try {
        final uri = Uri.parse(url);
        final segments = uri.pathSegments;
        int index = segments.indexOf('employee-documents');
        if (index == -1) index = segments.indexOf('documents');
        if (index != -1 && index + 1 < segments.length) {
          pathToDelete = segments.sublist(index + 1).join('/');
        }
      } catch (_) {}

      if (pathToDelete != null) {
        await SupabaseService.client.storage.from('employee-documents').remove([pathToDelete]);
      }

      final updatedList = _documentUrls.where((u) => u != url).toList();
      await SupabaseService.client
          .from('employees')
          .update({'document_urls': updatedList})
          .eq('id', user.id);

      setState(() {
        _documentUrls = updatedList;
      });
      
    } catch (e) {
      debugPrint('Failed to delete document: $e');
    }
  }

  // تسجيل الخروج
  Future<void> _handleLogout() async {
    unawaited(showDialog<dynamic>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تسجيل الخروج', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
        content: const Text('هل أنت متأكد من رغبتك في تسجيل الخروج من تطبيق HR Pro؟', style: TextStyle(fontFamily: 'Cairo', fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo', color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              final router = GoRouter.of(context);
              Navigator.pop(context);
              await SupabaseService.signOut();
              router.go(AppRoutes.login);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.dangerRed),
            child: const Text('تسجيل خروج', style: TextStyle(fontFamily: 'Cairo')),
          ),
        ],
      ),
    ));
  }

  // طلب حذف الحساب
  Future<void> _handleDeleteAccountRequest() async {
    final user = SupabaseService.currentUser;
    if (user == null) return;

    // إظهار مؤشر انتظار
    unawaited(showDialog<dynamic>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: AppTheme.neonCyan),
      ),
    ));

    try {
      // 1. تحقق من القروض النشطة بذمة الموظف
      final loans = await SupabaseService.client
          .from('loans')
          .select('remaining_amount')
          .eq('employee_id', user.id)
          .eq('status', 'approved');

      // إغلاق مؤشر الانتظار
      if (mounted) Navigator.pop(context);

      double totalRemaining = 0.0;
      if (loans.isNotEmpty) {
        for (final loan in loans) {
          totalRemaining += (loan['remaining_amount'] as num?)?.toDouble() ?? 0.0;
        }
      }

      if (totalRemaining > 0) {
        // حظر الطلب لوجود سلفة غير مسددة بالكامل
        if (mounted) {
          unawaited(showDialog<dynamic>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('⚠️ عذراً، لا يمكن حذف الحساب', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
              content: Text(
                'لا يمكنك تقديم طلب حذف الحساب لوجود سلف غير مكتملة السداد بذمتك بقيمة إجمالية قدرها (${AppConstants.formatMoney(totalRemaining)}). يرجى سداد الأقساط المتبقية ومراجعة الإدارة.',
                style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('حسناً', style: TextStyle(fontFamily: 'Cairo', color: AppTheme.neonCyan)),
                ),
              ],
            ),
          ));
        }
        return;
      }

      // 2. تأكيد إرسال الطلب للآدمن
      if (mounted) {
        unawaited(showDialog<dynamic>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('طلب حذف الحساب ⚠️', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
            content: const Text(
              'هل أنت متأكد من رغبتك في تقديم طلب حذف حسابك نهائياً؟ سيتم إرسال الطلب للمسؤول (الأدمن) للمراجعة والموافقة عليه.',
              style: TextStyle(fontFamily: 'Cairo', fontSize: 13),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo', color: Colors.grey)),
              ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(context); // إغلاق الديالوج
                  
                  // إظهار مؤشر إرسال الطلب
                  unawaited(showDialog<dynamic>(
                    context: context,
                    barrierDismissible: false,
                    builder: (context) => const Center(
                      child: CircularProgressIndicator(color: AppTheme.neonCyan),
                    ),
                  ));

                  try {
                    // الدالة ترسل الطلب لكل الأدمنية (الموظف لا يرى حساباتهم بسبب RLS)
                    await SupabaseService.client.rpc<dynamic>('request_account_deletion');

                    if (context.mounted) {
                      Navigator.pop(context); // إغلاق مؤشر الانتظار
                      unawaited(showDialog<dynamic>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('تم تقديم الطلب ✅', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: Colors.green)),
                          content: const Text(
                            'تم إرسال طلب حذف حسابك بنجاح للمدير العام. سيتم مراجعة المديونيات والأقساط والموافقة على الحذف قريباً.',
                            style: TextStyle(fontFamily: 'Cairo', fontSize: 13),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('حسناً', style: TextStyle(fontFamily: 'Cairo', color: AppTheme.neonCyan)),
                            ),
                          ],
                        ),
                      ));
                    }
                  } catch (e) {
                    if (context.mounted) Navigator.pop(context); // إغلاق مؤشر الانتظار
                    debugPrint('Failed to submit deletion request: $e');
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('فشل تقديم طلب حذف الحساب، يرجى المحاولة لاحقاً', style: TextStyle(fontFamily: 'Cairo'))),
                      );
                    }
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.dangerRed),
                child: const Text('تأكيد الطلب', style: TextStyle(fontFamily: 'Cairo')),
              ),
            ],
          ),
        ));
      }

    } catch (e) {
      if (mounted) Navigator.pop(context); // إغلاق مؤشر الانتظار
      debugPrint('Failed to check loans for deletion: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('حدث خطأ أثناء فحص البيانات، يرجى المحاولة لاحقاً', style: TextStyle(fontFamily: 'Cairo'))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(child: CircularProgressIndicator(color: AppTheme.neonCyan)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'إعدادات الملف والأمان',
          style: TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // 1. قسم الصورة والملف الشخصي الخلاب
            GlassContainer(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              opacity: 0.1,
              borderColor: AppTheme.neonCyan.withValues(alpha: 0.2),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.neonCyan.withValues(alpha: 0.04),
                  blurRadius: 20,
                )
              ],
              child: Column(
                children: [
                  // الأفاتار التفاعلي مع إمكانية التغيير المباشر والضغط التلقائي
                  Stack(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: AppTheme.neonCyan, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.neonCyan.withValues(alpha: 0.3),
                              blurRadius: 16,
                              spreadRadius: 1,
                            )
                          ],
                        ),
                        child: CircleAvatar(
                          radius: 50,
                          backgroundColor: Colors.white.withValues(alpha: 0.04),
                          backgroundImage: _avatarUrl.isNotEmpty ? NetworkImage(_avatarUrl) : null,
                          child: _avatarUrl.isEmpty
                              ? const Icon(Icons.person, size: 50, color: AppTheme.neonCyan)
                              : null,
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: GestureDetector(
                          onTap: _isUploadingAvatar ? null : _updateAvatar,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                              color: AppTheme.neonCyan,
                              shape: BoxShape.circle,
                            ),
                            child: _isUploadingAvatar
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                  )
                                : const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  // بيانات الموظف
                  Text(
                    _employeeName,
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Colors.white, fontFamily: 'Cairo'),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.neonCyan.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.neonCyan.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      _employeeCode,
                      style: const TextStyle(color: AppTheme.neonCyan, fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Divider(color: Colors.white12),
                  const SizedBox(height: 8),

                  _buildProfileRow(Icons.email_outlined, 'البريد الإلكتروني للعمل', _email, isDark),
                  const SizedBox(height: 12),
                  _buildProfileRow(Icons.phone_outlined, 'رقم الهاتف المسجل', _phone, isDark),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 2. قسم أمان الحساب وقفل الأجهزة المعتمد (Device Security Info)
            GlassContainer(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              opacity: 0.1,
              borderColor: AppTheme.warningOrange.withValues(alpha: 0.2),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.warningOrange.withValues(alpha: 0.04),
                  blurRadius: 20,
                )
              ],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.verified_user_rounded, color: AppTheme.warningOrange),
                      SizedBox(width: 8),
                      Text(
                        'حماية الحساب وقفل الأجهزة 🛡️',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Colors.white,
                          fontFamily: 'Cairo',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'تطبيقاً لأعلى معايير الحماية ومكافحة التزوير، تم قفل حسابك وربطه تلقائياً بجهازك الحالي المعتمد أدناه. لا يمكن تسجيل الدخول من أي هاتف آخر إلا بموافقة الإدارة.',
                    style: TextStyle(fontSize: 11, color: Colors.white70, height: 1.5, fontFamily: 'Cairo'),
                  ),
                  const Divider(height: 24, color: Colors.white12),
                  _buildProfileRow(Icons.phone_android_rounded, 'طراز وهاتف الدخول المقفل', _deviceModel, isDark),
                  const SizedBox(height: 12),
                  _buildProfileRow(Icons.adb_rounded, 'نسخة نظام الدوران الفوري', _osVersion, isDark),
                  const SizedBox(height: 12),
                  _buildProfileRow(Icons.fingerprint_rounded, 'رمز معرف الهاتف الفريد', _deviceUUID, isDark, isCode: true),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 2.5 قسم إعدادات الإشعارات
            const SizedBox(height: 20),
            GlassContainer(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              opacity: 0.1,
              borderColor: AppTheme.neonCyan.withValues(alpha: 0.2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.notifications_active_rounded, color: AppTheme.neonCyan),
                      SizedBox(width: 8),
                      Text(
                        'إعدادات الإشعارات 🔔',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Colors.white,
                          fontFamily: 'Cairo',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // حالة الصلاحية
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _notificationPermissionGranted
                          ? AppTheme.successGreen.withValues(alpha: 0.1)
                          : AppTheme.dangerRed.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _notificationPermissionGranted
                            ? AppTheme.successGreen.withValues(alpha: 0.3)
                            : AppTheme.dangerRed.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _notificationPermissionGranted
                              ? Icons.check_circle_rounded
                              : Icons.cancel_rounded,
                          color: _notificationPermissionGranted
                              ? AppTheme.successGreen
                              : AppTheme.dangerRed,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _notificationPermissionGranted
                                ? 'صلاحية الإشعارات ممنوحة ✅'
                                : 'صلاحية الإشعارات غير ممنوحة ❌ - اضغط "تفعيل" أدناه',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 12,
                              color: _notificationPermissionGranted
                                  ? AppTheme.successGreen
                                  : AppTheme.dangerRed,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // زر طلب الصلاحية
                  if (!_notificationPermissionGranted) ...[
                    ElevatedButton.icon(
                      onPressed: () async {
                        final granted = await NotificationService.requestPermissionAndSaveToken();
                        if (mounted) {
                          setState(() => _notificationPermissionGranted = granted);
                          if (!granted) await openAppSettings();
                        }
                      },
                      icon: const Icon(Icons.notifications_active_rounded, size: 18),
                      label: const Text('تفعيل الإشعارات', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.dangerRed,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
            // 2.8 قسم وثائق وملفات الموظف
            GlassContainer(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              opacity: 0.1,
              borderColor: Colors.blueAccent.withValues(alpha: 0.2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.folder_shared_rounded, color: Colors.blueAccent),
                          SizedBox(width: 8),
                          Text(
                            'وثائقي وملفاتي 📄',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Colors.white,
                              fontFamily: 'Cairo',
                            ),
                          ),
                        ],
                      ),
                      if (_isUploadingDoc)
                        const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(color: Colors.blueAccent, strokeWidth: 2),
                        )
                      else
                        IconButton(
                          onPressed: _uploadDocument,
                          icon: const Icon(Icons.add_circle_outline, color: Colors.blueAccent),
                          tooltip: 'رفع وثيقة جديدة',
                          constraints: const BoxConstraints(),
                          padding: EdgeInsets.zero,
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_documentUrls.isEmpty)
                    const Text('لا توجد وثائق مرفوعة حالياً.', style: TextStyle(color: Colors.white54, fontSize: 12, fontFamily: 'Cairo'))
                  else
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: _documentUrls.map((url) {
                        final bool isAdminOrManager = AuthService.currentUserRole == 'admin' || AuthService.currentUserRole == 'manager';

                        return GestureDetector(
                          onTap: () => _previewDocument(url),
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                width: 68,
                                height: 68,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: AppTheme.neonCyan.withValues(alpha: 0.4)),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: Image.network(
                                    url,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const Center(
                                      child: Icon(Icons.picture_as_pdf_rounded, color: AppTheme.neonPink, size: 28),
                                    ),
                                  ),
                                ),
                              ),

                              // شارة القفل للموظف العادي، أو زر الحذف للآدمن فقط
                              Positioned(
                                top: -6,
                                right: -6,
                                child: isAdminOrManager
                                    ? GestureDetector(
                                        onTap: () => _deleteDocument(url),
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: const BoxDecoration(
                                            color: AppTheme.dangerRed,
                                            shape: BoxShape.circle,
                                            boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 4)],
                                          ),
                                          child: const Icon(Icons.close, color: Colors.white, size: 12),
                                        ),
                                      )
                                    : Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: const BoxDecoration(
                                          color: AppTheme.successGreen,
                                          shape: BoxShape.circle,
                                          boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 4)],
                                        ),
                                        child: const Icon(Icons.lock_rounded, color: Colors.white, size: 10),
                                      ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                ],
              ),
            ),
            // 2.9 بوابة الخدمات المالية (كشوف الرواتب)
            const SizedBox(height: 20),
            GlassContainer(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              opacity: 0.1,
              borderColor: AppTheme.neonCyan.withValues(alpha: 0.2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.account_balance_wallet_rounded, color: AppTheme.neonCyan),
                      SizedBox(width: 8),
                      Text(
                        'الخدمات المالية وكشف الراتب 💸',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Colors.white,
                          fontFamily: 'Cairo',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => context.push(AppRoutes.employeePayslips),
                    icon: const Icon(Icons.receipt_long_rounded, size: 18),
                    label: const Text(
                      'عرض كشوف الرواتب الشهرية',
                      style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.neonCyan.withValues(alpha: 0.2),
                      foregroundColor: AppTheme.neonCyan,
                      side: BorderSide(color: AppTheme.neonCyan.withValues(alpha: 0.4)),
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  if (AuthService.currentUserRole == 'admin' || AuthService.currentUserRole == 'manager') ...[
                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      onPressed: () => context.push(AppRoutes.adminTracking),
                      icon: const Icon(Icons.location_searching_rounded, size: 18),
                      label: const Text(
                        'خريطة التتبع الحي للموظفين 📍',
                        style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.cyberPurple.withValues(alpha: 0.2),
                        foregroundColor: AppTheme.neonCyan,
                        side: BorderSide(color: AppTheme.neonCyan.withValues(alpha: 0.4)),
                        minimumSize: const Size(double.infinity, 48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      onPressed: () => context.push(AppRoutes.adminLoans),
                      icon: const Icon(Icons.table_chart_rounded, size: 18),
                      label: const Text(
                        'متابعة سلف الموظفين وكشوف Excel 📊',
                        style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.successGreen.withValues(alpha: 0.2),
                        foregroundColor: AppTheme.successGreen,
                        side: BorderSide(color: AppTheme.successGreen.withValues(alpha: 0.4)),
                        minimumSize: const Size(double.infinity, 48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 3. أزرار التحكم


            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.neonPink.withValues(alpha: 0.3),
                    blurRadius: 16,
                    spreadRadius: 1,
                  )
                ],
              ),
              child: ElevatedButton(
                onPressed: _handleLogout,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.neonPink,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  minimumSize: const Size(double.infinity, 50),
                  elevation: 0,
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.logout_rounded),
                    SizedBox(width: 8),
                    Text(
                      'تسجيل الخروج من الحساب',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: _handleDeleteAccountRequest,
              icon: const Icon(Icons.delete_forever_rounded, color: Colors.redAccent),
              label: const Text(
                'طلب حذف الحساب',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Colors.redAccent,
                ),
              ),
              style: TextButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: Colors.redAccent, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileRow(IconData icon, String title, String val, bool isDark, {bool isCode = false}) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.white60),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 10, color: Colors.white54, fontFamily: 'Cairo')),
              const SizedBox(height: 2),
              Text(
                val,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isCode ? FontWeight.w500 : FontWeight.bold,
                  fontFamily: isCode ? 'monospace' : 'Cairo',
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
