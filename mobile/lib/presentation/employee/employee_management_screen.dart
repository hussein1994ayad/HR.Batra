// =========================================================================
// نظام HR Pro v6.0 - شاشة إدارة الموظفين
// =========================================================================

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../core/services/image_compression_service.dart';
import '../../core/services/supabase_service.dart';
import '../shared/ui/ui.dart';
import '../shared/widgets/glass_background.dart';
import '../shared/widgets/glass_container.dart';

class EmployeeManagementScreen extends StatefulWidget {
  const EmployeeManagementScreen({super.key});

  @override
  State<EmployeeManagementScreen> createState() => _EmployeeManagementScreenState();
}

class _EmployeeManagementScreenState extends State<EmployeeManagementScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _employees = [];
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadEmployees();
  }

  Future<void> _loadEmployees() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    final user = SupabaseService.currentUser;
    if (user == null) {
      if (mounted) Navigator.pop(context);
      return;
    }

    try {
      final employeeRes = await SupabaseService.client
          .from('employees')
          .select('role')
          .eq('id', user.id)
          .maybeSingle();

      if (employeeRes == null || (employeeRes['role'] != 'admin' && employeeRes['role'] != 'manager')) {
        if (mounted) Navigator.pop(context);
        return;
      }

      final data = await SupabaseService.client
          .from('employees')
          .select('*, employee_devices(id, model)')
          .order('full_name');
          
      if (mounted) {
        setState(() {
          _employees = List<Map<String, dynamic>>.from(data);
        });
      }
    } catch (e) {
      debugPrint('Error loading employees: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleEmployeeStatus(String id, bool currentStatus) async {
    try {
      setState(() => _isLoading = true);
      await SupabaseService.client
          .from('employees')
          .update({'is_active': !currentStatus})
          .eq('id', id);
      
      unawaited(_loadEmployees());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(!currentStatus ? 'تم تفعيل حساب الموظف' : 'تم تعطيل حساب الموظف', style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: !currentStatus ? AppColors.success : AppColors.warning,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error toggling status: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _unbindDevice(String employeeId) async {
    try {
      setState(() => _isLoading = true);
      
      // 1. مسح تسجيلات الجهاز القديمة
      await SupabaseService.client
          .from('employee_devices')
          .delete()
          .eq('employee_id', employeeId);

      // 2. تحديث قفل الموظف ليكون نشطاً للجهاز القادم
      await SupabaseService.client
          .from('employees')
          .update({'device_id_lock': 'force_lock_active'})
          .eq('id', employeeId);
          
      unawaited(_loadEmployees());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم فك ربط جهاز الموظف بنجاح', style: TextStyle(fontFamily: 'Cairo')),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error unbinding device: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<List<String>> _uploadDocuments(List<File> files, String employeeId) async {
    List<String> uploadedUrls = [];
    
    for (final file in files) {
      try {
        // ضغط الصورة تلقائياً وإرجاعها، أو إرجاع الملف كما هو إذا كان مستنداً غير صوري (مثل PDF)
        final processedFile = await ImageCompressionService.compressImage(file);
        
        final fileName = '$employeeId/${DateTime.now().millisecondsSinceEpoch}_${file.path.split('/').last}';
        await SupabaseService.client.storage
            .from('employee-documents')
            .upload(fileName, processedFile);
            
        final url = SupabaseService.client.storage
            .from('employee-documents')
            .getPublicUrl(fileName);
            
        uploadedUrls.add(url);
      } catch (e) {
        debugPrint('Error compressing/uploading file: $e');
      }
    }
    return uploadedUrls;
  }

  void _showAddEmployeeModal() {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    final codeController = TextEditingController();
    String role = 'employee';
    bool isSaving = false;
    List<File> selectedDocuments = [];
    final ImagePicker picker = ImagePicker();

    showModalBottomSheet<dynamic>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.9,
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border.all(color: AppColors.brand.withValues(alpha: 0.2)),
              ),
              child: isSaving 
                  ? const Padding(padding: EdgeInsets.all(AppSpace.page), child: SkeletonList())
                  : Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.borderStrong,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.brand.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.person_add_rounded, color: AppColors.brand, size: 22),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'إضافة موظف جديد',
                          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textPrimary),
                        ),
                      ],
                    ),
                  ),
                  const Divider(color: AppColors.border, height: 1),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        _buildTextField(nameController, 'الاسم الكامل', Icons.person_rounded),
                        const SizedBox(height: 16),
                        _buildTextField(emailController, 'البريد الإلكتروني', Icons.email_rounded, isEmail: true),
                        const SizedBox(height: 16),
                        _buildTextField(passwordController, 'كلمة المرور', Icons.lock_rounded, isPassword: true),
                        const SizedBox(height: 16),
                        _buildTextField(codeController, 'كود الموظف (الرقم الوظيفي)', Icons.badge_rounded),
                        const SizedBox(height: 16),
                        const Text('الصلاحية', style: TextStyle(fontFamily: 'Cairo', color: AppColors.textSecondary, fontSize: 12)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _buildRoleChoice('موظف', 'employee', role, (val) => setModalState(() => role = val)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildRoleChoice('مدير/أدمن', 'admin', role, (val) => setModalState(() => role = val)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Text('المستمسكات الثبوتية (اختياري)', style: TextStyle(fontFamily: 'Cairo', color: AppColors.textSecondary, fontSize: 12)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ...selectedDocuments.asMap().entries.map((entry) {
                              int idx = entry.key;
                              File file = entry.value;
                              return Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.file(file, width: 60, height: 60, fit: BoxFit.cover),
                                  ),
                                  Positioned(
                                    top: -4,
                                    right: -4,
                                    child: GestureDetector(
                                      onTap: () => setModalState(() => selectedDocuments.removeAt(idx)),
                                      child: const CircleAvatar(radius: 10, backgroundColor: AppColors.danger, child: Icon(Icons.close, size: 12, color: AppColors.textPrimary)),
                                    ),
                                  )
                                ],
                              );
                            }),
                            GestureDetector(
                              onTap: () async {
                                final pickedFiles = await picker.pickMultiImage();
                                if (pickedFiles.isNotEmpty) {
                                  setModalState(() {
                                    selectedDocuments.addAll(pickedFiles.map((x) => File(x.path)));
                                  });
                                }
                              },
                              child: Container(
                                width: 60,
                                height: 60,
                                decoration: BoxDecoration(
                                  border: Border.all(color: AppColors.brand.withValues(alpha: 0.5)),
                                  borderRadius: BorderRadius.circular(12),
                                  color: AppColors.brand.withValues(alpha: 0.1),
                                ),
                                child: const Icon(Icons.add_a_photo_rounded, color: AppColors.brand),
                              ),
                            )
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text('سيتم ضغط الصور تلقائياً', style: TextStyle(fontFamily: 'Cairo', color: AppColors.textDisabled, fontSize: 10)),
                      ],
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
                    child: SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () async {
                          if (nameController.text.isEmpty || emailController.text.isEmpty || passwordController.text.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('الرجاء إكمال جميع الحقول الأساسية', style: TextStyle(fontFamily: 'Cairo'))),
                            );
                            return;
                          }

                          setModalState(() => isSaving = true);
                          try {
                            final newEmpId = const Uuid().v4();
                            List<String> uploadedDocs = [];
                            if (selectedDocuments.isNotEmpty) {
                              uploadedDocs = await _uploadDocuments(selectedDocuments, newEmpId);
                            }

                            final empCode = codeController.text.trim().isNotEmpty
                                ? codeController.text.trim()
                                : 'EMP-${DateTime.now().millisecondsSinceEpoch % 10000}';

                            await SupabaseService.client.rpc<dynamic>('create_employee_secure', params: {
                              'p_email': emailController.text.trim(),
                              'p_password': passwordController.text,
                              'p_full_name': nameController.text.trim(),
                              'p_phone': '',
                              'p_role': role,
                              'p_branch_id': null,
                              'p_monthly_salary_iqd': 0,
                              'p_document_urls': uploadedDocs,
                              'p_employee_code': empCode,
                              'p_employee_id': newEmpId,
                              'p_join_date': DateTime.now().toIso8601String().split('T')[0],
                            });

                            if (context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('تم إنشاء الموظف بنجاح', style: TextStyle(fontFamily: 'Cairo')), backgroundColor: AppColors.success),
                              );
                              unawaited(_loadEmployees());
                            }
                          } catch (e) {
                            setModalState(() => isSaving = false);
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('خطأ: $e', style: const TextStyle(fontFamily: 'Cairo')), backgroundColor: AppColors.danger),
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.brand,
                          foregroundColor: AppColors.onStatus,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: const Text('إنشاء الحساب', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 15)),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showEditEmployeeModal(Map<String, dynamic> emp) {
    bool isSaving = false;
    List<File> selectedDocuments = [];
    List<String> existingDocuments = List<String>.from((emp['document_urls'] ?? <dynamic>[]) as Iterable<dynamic>);
    final ImagePicker picker = ImagePicker();

    showModalBottomSheet<dynamic>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.9,
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border.all(color: AppColors.brand.withValues(alpha: 0.2)),
              ),
              child: isSaving 
                  ? const Padding(padding: EdgeInsets.all(AppSpace.page), child: SkeletonList())
                  : Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.borderStrong,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.brand.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.edit_document, color: AppColors.brand, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'تعديل ملف ومستمسكات ${emp['full_name']}',
                          style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textPrimary),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const Divider(color: AppColors.border, height: 1),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        const Text('تعديل المستمسكات الثبوتية', style: TextStyle(fontFamily: 'Cairo', color: AppColors.textSecondary, fontSize: 12)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ...existingDocuments.asMap().entries.map((entry) {
                              int idx = entry.key;
                              String url = entry.value;
                              return Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.network(url, width: 60, height: 60, fit: BoxFit.cover),
                                  ),
                                  Positioned(
                                    top: -4,
                                    right: -4,
                                    child: GestureDetector(
                                      onTap: () => setModalState(() => existingDocuments.removeAt(idx)),
                                      child: const CircleAvatar(radius: 10, backgroundColor: AppColors.danger, child: Icon(Icons.close, size: 12, color: AppColors.textPrimary)),
                                    ),
                                  )
                                ],
                              );
                            }),
                            ...selectedDocuments.asMap().entries.map((entry) {
                              int idx = entry.key;
                              File file = entry.value;
                              return Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.file(file, width: 60, height: 60, fit: BoxFit.cover),
                                  ),
                                  Positioned(
                                    top: -4,
                                    right: -4,
                                    child: GestureDetector(
                                      onTap: () => setModalState(() => selectedDocuments.removeAt(idx)),
                                      child: const CircleAvatar(radius: 10, backgroundColor: AppColors.danger, child: Icon(Icons.close, size: 12, color: AppColors.textPrimary)),
                                    ),
                                  )
                                ],
                              );
                            }),
                            GestureDetector(
                              onTap: () async {
                                final pickedFiles = await picker.pickMultiImage();
                                if (pickedFiles.isNotEmpty) {
                                  setModalState(() {
                                    selectedDocuments.addAll(pickedFiles.map((x) => File(x.path)));
                                  });
                                }
                              },
                              child: Container(
                                width: 60,
                                height: 60,
                                decoration: BoxDecoration(
                                  border: Border.all(color: AppColors.brand.withValues(alpha: 0.5)),
                                  borderRadius: BorderRadius.circular(12),
                                  color: AppColors.brand.withValues(alpha: 0.1),
                                ),
                                child: const Icon(Icons.add_a_photo_rounded, color: AppColors.brand),
                              ),
                            )
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text('ملاحظة: يمكنك إزالة أي صورة قديمة أو رفع صور جديدة سيتم استبدالها.', style: TextStyle(fontFamily: 'Cairo', color: AppColors.textDisabled, fontSize: 10)),
                      ],
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
                    child: SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () async {
                          setModalState(() => isSaving = true);
                          try {
                            // Find deleted
                            final originalDocs = List<String>.from((emp['document_urls'] ?? <dynamic>[]) as Iterable<dynamic>);
                            final deletedDocs = originalDocs.where((url) => !existingDocuments.contains(url)).toList();
                            for (final url in deletedDocs) {
                              try {
                                final match = RegExp(r'/employee-documents/(.+)').firstMatch(url);
                                if (match != null) {
                                  await SupabaseService.client.storage.from('employee-documents').remove([match.group(1)!]);
                                }
                              } catch (e) {
                                debugPrint('تعذر حذف المستند القديم من التخزين: $e');
                              }
                            }

                            // Upload new
                            List<String> newUrls = [];
                            if (selectedDocuments.isNotEmpty) {
                              newUrls = await _uploadDocuments(selectedDocuments, emp['id'] as String);
                            }
                            final finalUrls = [...existingDocuments, ...newUrls];

                            await SupabaseService.client.from('employees').update({'document_urls': finalUrls}).eq('id', emp['id'] as Object);

                            if (context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('تم تحديث المستمسكات بنجاح', style: TextStyle(fontFamily: 'Cairo')), backgroundColor: AppColors.success),
                              );
                              unawaited(_loadEmployees());
                            }
                          } catch (e) {
                            setModalState(() => isSaving = false);
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('خطأ: $e', style: const TextStyle(fontFamily: 'Cairo')), backgroundColor: AppColors.danger),
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.brand,
                          foregroundColor: AppColors.onStatus,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: const Text('تحديث وحفظ', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 15)),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildRoleChoice(String label, String value, String groupValue, void Function(String) onChanged) {
    final isSelected = value == groupValue;
    return GestureDetector(
      onTap: () => onChanged(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.brand.withValues(alpha: 0.2) : AppColors.textPrimary.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? AppColors.brand : AppColors.border),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? AppColors.brand : AppColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon, {bool isPassword = false, bool isEmail = false}) {
    return TextField(
      controller: controller,
      obscureText: isPassword,
      keyboardType: isEmail ? TextInputType.emailAddress : TextInputType.text,
      style: const TextStyle(fontFamily: 'Cairo', color: AppColors.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontFamily: 'Cairo', color: AppColors.textMuted, fontSize: 12),
        prefixIcon: Icon(icon, color: AppColors.brand, size: 20),
        filled: true,
        fillColor: AppColors.textPrimary.withValues(alpha: 0.05),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.brand)),
      ),
    );
  }

  String _normalizeArabic(String text) {
    return text
        .replaceAll(RegExp(r'[أإآٱ]'), 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي')
        .replaceAll('ئ', 'ي')
        .replaceAll('ؤ', 'و')
        .replaceAll(RegExp(r'[\u064B-\u065F]'), '')
        .trim()
        .toLowerCase();
  }

  void _previewImageDialog(String url, String title) {
    final isPdf = url.toLowerCase().contains('.pdf');

    showDialog<dynamic>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface1,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.brand.withValues(alpha: 0.3)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(isPdf ? Icons.picture_as_pdf_rounded : Icons.image_rounded, color: isPdf ? AppColors.accent : AppColors.brand, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textPrimary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: AppColors.textMuted, size: 20),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              const Divider(color: AppColors.border, height: 1),
              ClipRRect(
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
                child: isPdf
                    ? Container(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          children: [
                            const Icon(Icons.picture_as_pdf_rounded, size: 64, color: AppColors.accent),
                            const SizedBox(height: 12),
                            const Text('مستند رقمي بصيغة PDF', style: TextStyle(fontFamily: 'Cairo', color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: () => _downloadAndOpenFile(url, 'document.pdf'),
                              icon: const Icon(Icons.open_in_new_rounded, size: 16),
                              label: const Text('فتح وتحميل المستند', style: TextStyle(fontFamily: 'Cairo')),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.accent,
                                foregroundColor: AppColors.textPrimary,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ],
                        ),
                      )
                    : InteractiveViewer(
                        minScale: 0.5,
                        maxScale: 4.0,
                        child: Image.network(
                          url,
                          fit: BoxFit.contain,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Container(
                              height: 250,
                              alignment: Alignment.center,
                              child: const CircularProgressIndicator(color: AppColors.brand),
                            );
                          },
                          errorBuilder: (context, error, stackTrace) => Container(
                            height: 150,
                            alignment: Alignment.center,
                            child: const Text('تعذر تحميل الصورة', style: TextStyle(fontFamily: 'Cairo', color: AppColors.textMuted)),
                          ),
                        ),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: () => _downloadAndOpenFile(url, isPdf ? 'document.pdf' : 'document.jpg'),
                      icon: const Icon(Icons.download_rounded, size: 16, color: AppColors.brand),
                      label: const Text('تحميل وفتح', style: TextStyle(fontFamily: 'Cairo', fontSize: 11, color: AppColors.brand)),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: () async {
                        await SharePlus.instance.share(ShareParams(uri: Uri.parse(url)));
                      },
                      icon: const Icon(Icons.share_rounded, size: 16, color: AppColors.textSecondary),
                      label: const Text('مشاركة', style: TextStyle(fontFamily: 'Cairo', fontSize: 11, color: AppColors.textSecondary)),
                    ),
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _downloadAndOpenFile(String url, String fallbackName) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final dir = await getTemporaryDirectory();
        final ext = url.split('?').first.split('.').last;
        final fileName = 'batra_${DateTime.now().millisecondsSinceEpoch}.$ext';
        final file = File('${dir.path}/$fileName');
        await file.writeAsBytes(response.bodyBytes);
        await OpenFilex.open(file.path);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل فتح الملف: $e', style: const TextStyle(fontFamily: 'Cairo')), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  void _showEmployeeProfileModal(Map<String, dynamic> emp) {
    final name = emp['full_name'] ?? 'بدون اسم';
    final email = emp['email'] ?? 'لا يوجد بريد';
    final phone = emp['phone_number'] ?? emp['phone'] ?? 'غير مسجل';
    final code = emp['employee_code'] ?? 'غير محدد';
    final role = emp['role'] == 'admin' ? 'مدير عام' : (emp['role'] == 'manager' ? 'مدير' : 'موظف');
    final department = emp['department'] ?? 'غير محدد';
    final branch = emp['branch'] ?? emp['branches']?['name'] ?? 'غير محدد';
    final isActive = emp['is_active'] ?? true;
    final salary = emp['monthly_salary_iqd'] ?? emp['salary'] ?? 0;
    final docUrls = List<dynamic>.from((emp['document_urls'] ?? <dynamic>[]) as Iterable<dynamic>);
    final devices = emp['employee_devices'] as List<dynamic>? ?? [];
    final hasDevice = devices.isNotEmpty;

    showModalBottomSheet<dynamic>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.88,
        decoration: const BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                decoration: BoxDecoration(color: AppColors.borderStrong, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                children: [
                  // Profile Header
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: AppColors.brand.withValues(alpha: 0.2),
                        child: Text(
                          ((name.isNotEmpty as bool) ? name.substring(0, 1) : '?') as String,
                          style: const TextStyle(color: AppColors.brand, fontSize: 22, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name as String, style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textPrimary)),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                _buildBadge(role, AppColors.accent),
                                const SizedBox(width: 6),
                                _buildBadge((isActive as bool) ? 'نشط' : 'معطل', isActive ? AppColors.success : AppColors.danger),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(color: AppColors.brand.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                                  child: Text('كود: $code', style: const TextStyle(fontFamily: 'Cairo', fontSize: 9, color: AppColors.brand, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: AppColors.textMuted),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Quick Contact Buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: phone != 'غير مسجل'
                              ? () async {
                                  final uri = Uri.parse('tel:$phone');
                                  if (await canLaunchUrl(uri)) await launchUrl(uri);
                                }
                              : null,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.success,
                            side: const BorderSide(color: AppColors.success),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                          icon: const Icon(Icons.phone_rounded, size: 16),
                          label: const Text('اتصال', style: TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: phone != 'غير مسجل'
                              ? () async {
                                  final cleanPhone = phone.replaceAll(RegExp(r'\D'), '');
                                  final uri = Uri.parse('https://wa.me/$cleanPhone');
                                  if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
                                }
                              : null,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.brand,
                            side: const BorderSide(color: AppColors.brand),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                          icon: const Icon(Icons.chat_bubble_rounded, size: 16),
                          label: const Text('واتساب', style: TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: phone as String));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('تم نسخ رقم الهاتف', style: TextStyle(fontFamily: 'Cairo')),
                              backgroundColor: AppColors.brandStrong,
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                        icon: const Icon(Icons.copy_rounded, color: AppColors.textSecondary, size: 18),
                        tooltip: 'نسخ الرقم',
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Employee Details Grid
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.textPrimary.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.textPrimary.withValues(alpha: 0.08)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('المعلومات الوظيفية والشخصية', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.brand)),
                        const SizedBox(height: 12),
                        _buildProfileInfoRow(Icons.email_outlined, 'البريد الإلكتروني', email as String),
                        _buildProfileInfoRow(Icons.phone_android_rounded, 'رقم الهاتف', phone as String),
                        _buildProfileInfoRow(Icons.account_tree_outlined, 'القسم / الإدارة', department as String),
                        _buildProfileInfoRow(Icons.location_on_outlined, 'الفرع المعتمد', branch as String),
                        _buildProfileInfoRow(Icons.monetization_on_outlined, 'الراتب الشهري', '$salary د.ع'),
                        _buildProfileInfoRow(Icons.smartphone_rounded, 'حالة قفل الجهاز', hasDevice ? 'مربوط بجهاز (${devices.first['model'] ?? 'هاتف'})' : 'غير مقيد بجهاز حالياً'),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Documents Explorer
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.folder_shared_rounded, color: AppColors.brand, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'المستمسكات والوثائق (${docUrls.length})',
                            style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textPrimary),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          if (docUrls.length > 1)
                            TextButton.icon(
                              onPressed: () async {
                                final text = docUrls.map((u) => u.toString()).join('\n');
                                await SharePlus.instance.share(ShareParams(text: text, subject: 'وثائق الموظف: $name'));
                              },
                              icon: const Icon(Icons.share_rounded, color: AppColors.brand, size: 14),
                              label: const Text('مشاركة الكل', style: TextStyle(fontFamily: 'Cairo', fontSize: 10, color: AppColors.brand)),
                            ),
                          TextButton.icon(
                            onPressed: () {
                              Navigator.pop(ctx);
                              _showEditEmployeeModal(emp);
                            },
                            icon: const Icon(Icons.edit_document, color: AppColors.accent, size: 14),
                            label: const Text('تعديل/إضافة', style: TextStyle(fontFamily: 'Cairo', fontSize: 10, color: AppColors.accent)),
                          ),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  if (docUrls.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.textPrimary.withValues(alpha: 0.02),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.textPrimary.withValues(alpha: 0.06)),
                      ),
                      child: const Center(
                        child: Text('لا توجد وثائق أو مستمسكات مرفوعة لهذا الموظف.', style: TextStyle(fontFamily: 'Cairo', color: AppColors.textDisabled, fontSize: 11)),
                      ),
                    )
                  else
                    ...docUrls.asMap().entries.map((entry) {
                      final idx = entry.key + 1;
                      final url = entry.value.toString();
                      final isPdf = url.toLowerCase().contains('.pdf');

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.textPrimary.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.brand.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: (isPdf ? AppColors.accent : AppColors.brand).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                isPdf ? Icons.picture_as_pdf_rounded : Icons.image_rounded,
                                color: isPdf ? AppColors.accent : AppColors.brand,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('وثيقة رسمية رقم #$idx', style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textPrimary)),
                                  Text(isPdf ? 'مستند PDF رقمي' : 'صورة / مستمسك معتمد', style: const TextStyle(fontFamily: 'Cairo', fontSize: 10, color: AppColors.textMuted)),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.visibility_rounded, color: AppColors.brand, size: 18),
                              tooltip: 'معاينة',
                              onPressed: () => _previewImageDialog(url, 'وثيقة الموظف $name #$idx'),
                            ),
                            IconButton(
                              icon: const Icon(Icons.download_rounded, color: AppColors.success, size: 18),
                              tooltip: 'تحميل وفتح',
                              onPressed: () => _downloadAndOpenFile(url, isPdf ? 'doc_$idx.pdf' : 'doc_$idx.jpg'),
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.textMuted),
          const SizedBox(width: 8),
          SizedBox(
            width: 110,
            child: Text(label, style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, color: AppColors.textMuted)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final normQuery = _normalizeArabic(_searchQuery);
    final filtered = _employees.where((e) {
      if (normQuery.isEmpty) return true;
      final name = _normalizeArabic(e['full_name']?.toString() ?? '');
      final email = (e['email']?.toString() ?? '').toLowerCase();
      final code = (e['employee_code']?.toString() ?? '').toLowerCase();
      final phone = (e['phone_number']?.toString() ?? e['phone']?.toString() ?? '').toLowerCase();
      final dept = _normalizeArabic(e['department']?.toString() ?? '');
      final branch = _normalizeArabic(e['branch']?.toString() ?? e['branches']?['name']?.toString() ?? '');
      return name.contains(normQuery) ||
          email.contains(normQuery) ||
          code.contains(normQuery) ||
          phone.contains(normQuery) ||
          dept.contains(normQuery) ||
          branch.contains(normQuery);
    }).toList();

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
          title: const Text('إدارة الموظفين', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textPrimary)),
          actions: [
            IconButton(
              icon: const Icon(Icons.person_add_rounded, color: AppColors.brand),
              onPressed: _showAddEmployeeModal,
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                onChanged: (val) => setState(() => _searchQuery = val),
                style: const TextStyle(color: AppColors.textPrimary, fontFamily: 'Cairo'),
                decoration: InputDecoration(
                  hintText: 'ابحث بالاسم، الكود، الهاتف، القسم، الفرع...',
                  hintStyle: const TextStyle(color: AppColors.textDisabled, fontFamily: 'Cairo', fontSize: 12),
                  prefixIcon: const Icon(Icons.search, color: AppColors.textMuted),
                  filled: true,
                  fillColor: AppColors.textPrimary.withValues(alpha: 0.05),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(),
                ),
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Padding(padding: EdgeInsets.all(AppSpace.page), child: SkeletonList())
                  : filtered.isEmpty
                      ? const Center(child: Text('لا يوجد موظفون مطابقون لبحثك', style: TextStyle(color: AppColors.textMuted, fontFamily: 'Cairo')))
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final emp = filtered[index];
                            final isActive = emp['is_active'] ?? true;
                            final devices = emp['employee_devices'] as List<dynamic>? ?? [];
                            final hasDevice = devices.isNotEmpty;

                            return InkWell(
                              onTap: () => _showEmployeeProfileModal(emp),
                              borderRadius: BorderRadius.circular(16),
                              child: GlassContainer(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(16),
                                borderColor: (isActive as bool) ? AppColors.brand.withValues(alpha: 0.2) : AppColors.danger.withValues(alpha: 0.3),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        CircleAvatar(
                                          backgroundColor: AppColors.brand.withValues(alpha: 0.2),
                                          child: Text((emp['full_name']?.isNotEmpty == true ? emp['full_name']!.substring(0, 1) : '?') as String, style: const TextStyle(color: AppColors.brand, fontWeight: FontWeight.bold)),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text((emp['full_name'] ?? 'بدون اسم') as String, style: const TextStyle(color: AppColors.textPrimary, fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 14)),
                                              Text((emp['email'] ?? '') as String, style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
                                              const SizedBox(height: 4),
                                              Row(
                                                children: [
                                                  _buildBadge(emp['role'] == 'admin' ? 'مدير عام' : (emp['role'] == 'manager' ? 'مدير' : 'موظف'), AppColors.accent),
                                                  const SizedBox(width: 4),
                                                  _buildBadge(isActive ? 'نشط' : 'معطل', isActive ? AppColors.success : AppColors.danger),
                                                  if (hasDevice) ...[
                                                    const SizedBox(width: 4),
                                                    _buildBadge('جهاز مربوط', AppColors.warning),
                                                  ]
                                                ],
                                              )
                                            ],
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.folder_shared_rounded, color: AppColors.brand, size: 20),
                                          tooltip: 'عرض الملف والوثائق',
                                          onPressed: () => _showEmployeeProfileModal(emp),
                                        ),
                                        PopupMenuButton<String>(
                                          icon: const Icon(Icons.more_vert, color: AppColors.textSecondary),
                                          color: AppColors.surface2,
                                          onSelected: (value) {
                                            if (value == 'profile') _showEmployeeProfileModal(emp);
                                            if (value == 'edit') _showEditEmployeeModal(emp);
                                            if (value == 'toggle') _toggleEmployeeStatus(emp['id'] as String, isActive);
                                            if (value == 'unbind') _unbindDevice(emp['id'] as String);
                                          },
                                          itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                                            const PopupMenuItem<String>(
                                              value: 'profile',
                                              child: Text('عرض الملف والوثائق', style: TextStyle(color: AppColors.brand, fontFamily: 'Cairo')),
                                            ),
                                            const PopupMenuItem<String>(
                                              value: 'edit',
                                              child: Text('تعديل المستمسكات', style: TextStyle(color: AppColors.textPrimary, fontFamily: 'Cairo')),
                                            ),
                                            PopupMenuItem<String>(
                                              value: 'toggle',
                                              child: Text(isActive ? 'تعطيل الحساب' : 'تفعيل الحساب', style: TextStyle(color: isActive ? AppColors.danger : AppColors.success, fontFamily: 'Cairo')),
                                            ),
                                            if (hasDevice)
                                              const PopupMenuItem<String>(
                                                value: 'unbind',
                                                child: Text('فك ربط الجهاز (السماح بتسجيل جديد)', style: TextStyle(color: AppColors.warning, fontFamily: 'Cairo')),
                                              ),
                                          ],
                                        )
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 8, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
    );
  }
}
