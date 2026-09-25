// =========================================================================
// نظام HR Pro v6.0 - شاشة سلة المحذوفات للملفات (Trash / Recycle Bin Screen)
// =========================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/design/design.dart';
import '../../core/services/supabase_service.dart';
import '../shared/widgets/glass_background.dart';
import '../shared/widgets/glass_container.dart';

class TrashScreen extends StatefulWidget {
  const TrashScreen({super.key});

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _deletedFiles = [];

  @override
  void initState() {
    super.initState();
    _loadTrashFiles();
  }

  // تحميل قائمة الملفات المحذوفة مؤقتاً
  Future<void> _loadTrashFiles() async {
    setState(() => _isLoading = true);
    try {
      final List<dynamic> data = await SupabaseService.client
          .from('deleted_files')
          .select('*, employees(full_name)')
          .isFilter('restored_at', null)
          .order('deleted_at', ascending: false);

      setState(() {
        _deletedFiles = List<Map<String, dynamic>>.from(data);
      });
    } catch (e) {
      debugPrint('خطأ في جلب بيانات سلة المحذوفات: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // تحديد اسم الباكت بناءً على نوع الملف
  String _getBucketName(String fileType) {
    switch (fileType) {
      case 'avatar':
        return 'avatars';
      case 'document':
        return 'employee-documents';
      case 'pledge':
        return 'loan-pledges';
      case 'logo':
        return 'company-logos';
      default:
        return 'employee-documents';
    }
  }

  // ترجمة نوع الملف للغة العربية
  String _getFileTypeName(String fileType) {
    switch (fileType) {
      case 'avatar':
        return 'الصورة الشخصية';
      case 'document':
        return 'مستند رسمي';
      case 'pledge':
        return 'تعهد السلفة';
      case 'logo':
        return 'شعار الشركة';
      default:
        return 'ملف آخر';
    }
  }

  // استعادة ملف محذوف
  Future<void> _restoreFile(Map<String, dynamic> fileRow) async {
    final String fileId = fileRow['id'] as String;

    setState(() => _isLoading = true);
    try {
      // تحديث حقل تاريخ الاستعادة في قاعدة البيانات لوسمه كمسترجع
      await SupabaseService.client
          .from('deleted_files')
          .update({
            'restored_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', fileId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم استعادة الملف بنجاح ✅', style: TextStyle(fontFamily: 'Cairo')),
            backgroundColor: AppColors.success,
          ),
        );
      }
      unawaited(_loadTrashFiles());
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل استعادة الملف: $e', style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  // إتلاف وحذف ملف نهائياً
  Future<void> _permanentDeleteFile(Map<String, dynamic> fileRow) async {
    final String fileId = fileRow['id'] as String;
    final String filePath = fileRow['file_path'] as String;
    final String fileType = fileRow['file_type'] as String;
    final String bucket = _getBucketName(fileType);

    setState(() => _isLoading = true);
    try {
      // 1. حذف الملف نهائياً من Supabase Storage
      await SupabaseService.client.storage.from(bucket).remove([filePath]);

      // 2. حذف السجل تماماً من جدول سلة المحذوفات
      await SupabaseService.client
          .from('deleted_files')
          .delete()
          .eq('id', fileId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إتلاف الملف وحذفه نهائياً 🗑️', style: TextStyle(fontFamily: 'Cairo')),
            backgroundColor: AppColors.onStatus,
          ),
        );
      }
      unawaited(_loadTrashFiles());
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل في إتلاف الملف: $e', style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  // تنسيق الحجم بالـ KB/MB
  String _formatBytes(dynamic bytes) {
    if (bytes == null) return 'غير محدد';
    final int b = bytes as int;
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Widget _buildDetailColumn(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: AppColors.textPrimary.withValues(alpha: 0.4),
            fontFamily: 'Cairo',
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            fontFamily: 'Cairo',
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  void _showDeleteConfirmationDialog(BuildContext context, Map<String, dynamic> file) {
    showDialog<dynamic>(
      context: context,
      barrierColor: AppColors.onStatus.withValues(alpha: 0.6),
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: GlassContainer(
          padding: const EdgeInsets.all(24),
            borderColor: AppColors.danger.withValues(alpha: 0.4),
            boxShadow: [
              BoxShadow(
                color: AppColors.danger.withValues(alpha: 0.12),
                blurRadius: 24,
              )
            ],
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.danger.withValues(alpha: 0.35),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.danger.withValues(alpha: 0.2),
                        blurRadius: 10,
                      )
                    ],
                  ),
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    color: AppColors.danger,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'إتلاف وحذف نهائي؟ ⚠️',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'هل أنت متأكد من رغبتك في حذف هذا الملف بشكل نهائي وتام من الخوادم؟ لا يمكن التراجع عن هذا الإجراء.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 13,
                    color: AppColors.textPrimary.withValues(alpha: 0.8),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          side: BorderSide(color: AppColors.textPrimary.withValues(alpha: 0.2)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text(
                          'إلغاء',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.danger.withValues(alpha: 0.25),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            )
                          ],
                        ),
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                            _permanentDeleteFile(file);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.danger,
                            elevation: 0,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text(
                            'إتلاف نهائي',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text(
            'سلة المحذوفات للملفات 🗑️',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
              shadows: [
                Shadow(
                  color: AppColors.brand,
                  blurRadius: 10,
                ),
              ],
            ),
          ),
          centerTitle: true,
        ),
        body: _isLoading
            ? const Center(
                child: CircularProgressIndicator(
                  color: AppColors.brand,
                ),
              )
            : _deletedFiles.isEmpty
                ? Center(
                    child: GlassContainer(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                      margin: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.delete_outline_rounded,
                            size: 64,
                            color: AppColors.textPrimary.withValues(alpha: 0.4),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'سلة المحذوفات فارغة حالياً',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 16,
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'يتم الاحتفاظ بالملفات المحذوفة هنا لمدة 30 يوماً فقط لتسهيل استعادتها قبل إتلافها بالكامل.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 12,
                              color: AppColors.textPrimary.withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: _deletedFiles.length,
                    itemBuilder: (context, index) {
                      final file = _deletedFiles[index];
                      final String filename = file['file_path'].split('/').last as String;
                      final String deletedByName = (file['employees']?['full_name'] ?? 'غير معروف') as String;
                      final DateTime deletedAt = DateTime.parse(file['deleted_at'] as String).toLocal();
                      final DateTime expiryDate = DateTime.parse(file['scheduled_deletion_date'] as String).toLocal();
                      final daysLeft = expiryDate.difference(DateTime.now()).inDays;
                      final warningColor = daysLeft <= 5 ? AppColors.danger : AppColors.warning;

                      return GlassContainer(
                        margin: const EdgeInsets.only(bottom: 16),
                        borderRadius: 20,
                        borderColor: warningColor.withValues(alpha: 0.4),
                        boxShadow: [
                          BoxShadow(
                            color: warningColor.withValues(alpha: 0.06),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          )
                        ],
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: AppColors.brand.withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: AppColors.brand.withValues(alpha: 0.35),
                                      width: 1.5,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.brand.withValues(alpha: 0.2),
                                        blurRadius: 8,
                                      )
                                    ],
                                  ),
                                  child: const Icon(Icons.insert_drive_file_outlined, color: AppColors.brand, size: 22),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        filename,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          fontFamily: 'Cairo',
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'النوع: ${_getFileTypeName(file['file_type'] as String)}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: AppColors.textPrimary.withValues(alpha: 0.5),
                                          fontFamily: 'Cairo',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: warningColor.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: warningColor.withValues(alpha: 0.4),
                                    ),
                                  ),
                                  child: Text(
                                    'متبقي $daysLeft يوم',
                                    style: TextStyle(
                                      color: warningColor,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'Cairo',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Container(
                              height: 1,
                              color: AppColors.textPrimary.withValues(alpha: 0.08),
                            ),
                            const SizedBox(height: 12),
                            
                            // تفاصيل الحجم وتاريخ الحذف
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                _buildDetailColumn('تاريخ الحذف', DateFormat('yyyy/MM/dd h:mm a').format(deletedAt)),
                                _buildDetailColumn('حجم الملف', _formatBytes(file['file_size_bytes'])),
                                _buildDetailColumn('بواسطة', deletedByName),
                              ],
                            ),
                            const SizedBox(height: 16),
                            
                            // أزرار العمليات
                            Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppColors.success.withValues(alpha: 0.2),
                                          blurRadius: 8,
                                          offset: const Offset(0, 3),
                                        )
                                      ],
                                    ),
                                    child: ElevatedButton.icon(
                                      onPressed: () => _restoreFile(file),
                                      icon: const Icon(Icons.settings_backup_restore_rounded, size: 16, color: AppColors.textPrimary),
                                      label: const Text(
                                        'استعادة الملف',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontFamily: 'Cairo',
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.success,
                                        elevation: 0,
                                        shadowColor: Colors.transparent,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => _showDeleteConfirmationDialog(context, file),
                                    icon: const Icon(Icons.delete_forever_rounded, size: 16, color: AppColors.danger),
                                    label: const Text(
                                      'إتلاف نهائي',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontFamily: 'Cairo',
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.danger,
                                      ),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      side: const BorderSide(color: AppColors.danger, width: 1.2),
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      backgroundColor: AppColors.danger.withValues(alpha: 0.04),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
