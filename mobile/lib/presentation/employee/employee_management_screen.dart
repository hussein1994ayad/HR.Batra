// =========================================================================
// نظام HR Pro v6.0 - شاشة إدارة الموظفين
// =========================================================================

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
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
    setState(() => _isLoading = true);
    try {
      final data = await SupabaseService.client
          .from('employees')
          .select('*, employee_devices(id, model)')
          .order('full_name');
          
      setState(() {
        _employees = List<Map<String, dynamic>>.from(data);
      });
    } catch (e) {
      debugPrint('Error loading employees: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleEmployeeStatus(String id, bool currentStatus) async {
    try {
      setState(() => _isLoading = true);
      await SupabaseService.client
          .from('employees')
          .update({'is_active': !currentStatus})
          .eq('id', id);
      
      _loadEmployees();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(!currentStatus ? 'تم تفعيل حساب الموظف ✅' : 'تم تعطيل حساب الموظف ❌', style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: !currentStatus ? AppTheme.successGreen : AppTheme.warningOrange,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error toggling status: $e');
    } finally {
      setState(() => _isLoading = false);
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
          
      _loadEmployees();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم فك ربط جهاز الموظف بنجاح ✅', style: TextStyle(fontFamily: 'Cairo')),
            backgroundColor: AppTheme.successGreen,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error unbinding device: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<List<String>> _uploadDocuments(List<File> files, String employeeId) async {
    List<String> uploadedUrls = [];
    final tempDir = await getTemporaryDirectory();
    
    for (var file in files) {
      try {
        final ext = file.path.split('.').last;
        final targetPath = '${tempDir.path}/${DateTime.now().millisecondsSinceEpoch}_compressed.$ext';
        
        final compressedFile = await FlutterImageCompress.compressAndGetFile(
          file.absolute.path,
          targetPath,
          quality: 70,
          minWidth: 1024,
          minHeight: 1024,
        );
        
        if (compressedFile != null) {
          final fileName = '$employeeId/${DateTime.now().millisecondsSinceEpoch}_${file.path.split('/').last}';
          await SupabaseService.client.storage
              .from('employee-documents')
              .upload(fileName, File(compressedFile.path));
              
          final url = SupabaseService.client.storage
              .from('employee-documents')
              .getPublicUrl(fileName);
              
          uploadedUrls.add(url);
        }
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
    List<File> _selectedDocuments = [];
    final ImagePicker _picker = ImagePicker();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.9,
              decoration: BoxDecoration(
                color: const Color(0xFF1A1F3A),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border.all(color: AppTheme.neonCyan.withOpacity(0.2)),
              ),
              child: isSaving 
                  ? const Center(child: CircularProgressIndicator(color: AppTheme.neonCyan))
                  : Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
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
                            color: AppTheme.neonCyan.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.person_add_rounded, color: AppTheme.neonCyan, size: 22),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'إضافة موظف جديد',
                          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                  const Divider(color: Colors.white10, height: 1),
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
                        const Text('الصلاحية', style: TextStyle(fontFamily: 'Cairo', color: Colors.white70, fontSize: 12)),
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
                        const Text('المستمسكات الثبوتية (اختياري)', style: TextStyle(fontFamily: 'Cairo', color: Colors.white70, fontSize: 12)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ..._selectedDocuments.asMap().entries.map((entry) {
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
                                      onTap: () => setModalState(() => _selectedDocuments.removeAt(idx)),
                                      child: const CircleAvatar(radius: 10, backgroundColor: Colors.red, child: Icon(Icons.close, size: 12, color: Colors.white)),
                                    ),
                                  )
                                ],
                              );
                            }),
                            GestureDetector(
                              onTap: () async {
                                final pickedFiles = await _picker.pickMultiImage();
                                if (pickedFiles.isNotEmpty) {
                                  setModalState(() {
                                    _selectedDocuments.addAll(pickedFiles.map((x) => File(x.path)));
                                  });
                                }
                              },
                              child: Container(
                                width: 60,
                                height: 60,
                                decoration: BoxDecoration(
                                  border: Border.all(color: AppTheme.neonCyan.withOpacity(0.5), style: BorderStyle.solid),
                                  borderRadius: BorderRadius.circular(12),
                                  color: AppTheme.neonCyan.withOpacity(0.1),
                                ),
                                child: const Icon(Icons.add_a_photo_rounded, color: AppTheme.neonCyan),
                              ),
                            )
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text('سيتم ضغط الصور تلقائياً', style: TextStyle(fontFamily: 'Cairo', color: Colors.white38, fontSize: 10)),
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
                            // استدعاء Edge Function لإنشاء الموظف
                            final res = await SupabaseService.client.functions.invoke(
                              'admin-create-user',
                              body: {
                                'email': emailController.text.trim(),
                                'password': passwordController.text,
                                'full_name': nameController.text.trim(),
                                'employee_code': codeController.text.trim(),
                                'role': role,
                              },
                            );

                            if (res.status == 200) {
                              if (_selectedDocuments.isNotEmpty) {
                                try {
                                  final empData = await SupabaseService.client.from('employees').select('id').eq('email', emailController.text.trim()).single();
                                  final urls = await _uploadDocuments(_selectedDocuments, empData['id']);
                                  await SupabaseService.client.from('employees').update({'document_urls': urls}).eq('id', empData['id']);
                                } catch (e) {
                                  debugPrint('Failed to upload documents: $e');
                                }
                              }

                              if (mounted) {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('تم إنشاء الموظف بنجاح ✅', style: TextStyle(fontFamily: 'Cairo')), backgroundColor: AppTheme.successGreen),
                                );
                                _loadEmployees();
                              }
                            } else {
                              throw Exception('فشل إنشاء المستخدم: ${res.data}');
                            }
                          } catch (e) {
                            setModalState(() => isSaving = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('خطأ: $e', style: const TextStyle(fontFamily: 'Cairo')), backgroundColor: AppTheme.dangerRed),
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.neonCyan,
                          foregroundColor: Colors.black,
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
    List<File> _selectedDocuments = [];
    List<String> _existingDocuments = List<String>.from(emp['document_urls'] ?? []);
    final ImagePicker _picker = ImagePicker();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.9,
              decoration: BoxDecoration(
                color: const Color(0xFF1A1F3A),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border.all(color: AppTheme.neonCyan.withOpacity(0.2)),
              ),
              child: isSaving 
                  ? const Center(child: CircularProgressIndicator(color: AppTheme.neonCyan))
                  : Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
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
                            color: AppTheme.neonCyan.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.edit_document, color: AppTheme.neonCyan, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'تعديل ملف ومستمسكات ${emp['full_name']}',
                          style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const Divider(color: Colors.white10, height: 1),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        const Text('تعديل المستمسكات الثبوتية', style: TextStyle(fontFamily: 'Cairo', color: Colors.white70, fontSize: 12)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ..._existingDocuments.asMap().entries.map((entry) {
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
                                      onTap: () => setModalState(() => _existingDocuments.removeAt(idx)),
                                      child: const CircleAvatar(radius: 10, backgroundColor: Colors.red, child: Icon(Icons.close, size: 12, color: Colors.white)),
                                    ),
                                  )
                                ],
                              );
                            }),
                            ..._selectedDocuments.asMap().entries.map((entry) {
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
                                      onTap: () => setModalState(() => _selectedDocuments.removeAt(idx)),
                                      child: const CircleAvatar(radius: 10, backgroundColor: Colors.red, child: Icon(Icons.close, size: 12, color: Colors.white)),
                                    ),
                                  )
                                ],
                              );
                            }),
                            GestureDetector(
                              onTap: () async {
                                final pickedFiles = await _picker.pickMultiImage();
                                if (pickedFiles.isNotEmpty) {
                                  setModalState(() {
                                    _selectedDocuments.addAll(pickedFiles.map((x) => File(x.path)));
                                  });
                                }
                              },
                              child: Container(
                                width: 60,
                                height: 60,
                                decoration: BoxDecoration(
                                  border: Border.all(color: AppTheme.neonCyan.withOpacity(0.5), style: BorderStyle.solid),
                                  borderRadius: BorderRadius.circular(12),
                                  color: AppTheme.neonCyan.withOpacity(0.1),
                                ),
                                child: const Icon(Icons.add_a_photo_rounded, color: AppTheme.neonCyan),
                              ),
                            )
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text('ملاحظة: يمكنك إزالة أي صورة قديمة أو رفع صور جديدة سيتم استبدالها.', style: TextStyle(fontFamily: 'Cairo', color: Colors.white38, fontSize: 10)),
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
                            final originalDocs = List<String>.from(emp['document_urls'] ?? []);
                            final deletedDocs = originalDocs.where((url) => !_existingDocuments.contains(url)).toList();
                            for (var url in deletedDocs) {
                              try {
                                final match = RegExp(r'/employee-documents/(.+)').firstMatch(url);
                                if (match != null) {
                                  await SupabaseService.client.storage.from('employee-documents').remove([match.group(1)!]);
                                }
                              } catch(e) {}
                            }

                            // Upload new
                            List<String> newUrls = [];
                            if (_selectedDocuments.isNotEmpty) {
                              newUrls = await _uploadDocuments(_selectedDocuments, emp['id']);
                            }
                            final finalUrls = [..._existingDocuments, ...newUrls];

                            await SupabaseService.client.from('employees').update({'document_urls': finalUrls}).eq('id', emp['id']);

                            if (mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('تم تحديث المستمسكات بنجاح ✅', style: TextStyle(fontFamily: 'Cairo')), backgroundColor: AppTheme.successGreen),
                              );
                              _loadEmployees();
                            }
                          } catch (e) {
                            setModalState(() => isSaving = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('خطأ: $e', style: const TextStyle(fontFamily: 'Cairo')), backgroundColor: AppTheme.dangerRed),
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.neonCyan,
                          foregroundColor: Colors.black,
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

  Widget _buildRoleChoice(String label, String value, String groupValue, Function(String) onChanged) {
    final isSelected = value == groupValue;
    return GestureDetector(
      onTap: () => onChanged(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.neonCyan.withOpacity(0.2) : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? AppTheme.neonCyan : Colors.white10),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? AppTheme.neonCyan : Colors.white54,
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
      style: const TextStyle(fontFamily: 'Cairo', color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontFamily: 'Cairo', color: Colors.white54, fontSize: 12),
        prefixIcon: Icon(icon, color: AppTheme.neonCyan, size: 20),
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppTheme.neonCyan)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _employees.where((e) => (e['full_name'] ?? '').toLowerCase().contains(_searchQuery.toLowerCase())).toList();

    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text('إدارة الموظفين 👥', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
          actions: [
            IconButton(
              icon: const Icon(Icons.person_add_rounded, color: AppTheme.neonCyan),
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
                style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
                decoration: InputDecoration(
                  hintText: 'ابحث عن موظف...',
                  hintStyle: const TextStyle(color: Colors.white38, fontFamily: 'Cairo'),
                  prefixIcon: const Icon(Icons.search, color: Colors.white54),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.05),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                ),
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppTheme.neonCyan))
                  : filtered.isEmpty
                      ? const Center(child: Text('لا يوجد موظفين', style: TextStyle(color: Colors.white54, fontFamily: 'Cairo')))
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final emp = filtered[index];
                            final isActive = emp['is_active'] ?? true;
                            final devices = emp['employee_devices'] as List<dynamic>? ?? [];
                            final hasDevice = devices.isNotEmpty;

                            return GlassContainer(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(16),
                              borderRadius: 16,
                              opacity: 0.08,
                              borderColor: isActive ? AppTheme.neonCyan.withOpacity(0.2) : AppTheme.dangerRed.withOpacity(0.3),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      CircleAvatar(
                                        backgroundColor: AppTheme.neonCyan.withOpacity(0.2),
                                        child: Text(emp['full_name']?.substring(0, 1) ?? '?', style: const TextStyle(color: AppTheme.neonCyan, fontWeight: FontWeight.bold)),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(emp['full_name'] ?? 'بدون اسم', style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 14)),
                                            Text(emp['email'] ?? '', style: const TextStyle(color: Colors.white54, fontSize: 10)),
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                _buildBadge(emp['role'] == 'admin' ? 'مدير' : 'موظف', AppTheme.cyberPurple),
                                                const SizedBox(width: 4),
                                                _buildBadge(isActive ? 'نشط' : 'معطل', isActive ? AppTheme.successGreen : AppTheme.dangerRed),
                                                if (hasDevice) ...[
                                                  const SizedBox(width: 4),
                                                  _buildBadge('جهاز مربوط', AppTheme.warningOrange),
                                                ]
                                              ],
                                            )
                                          ],
                                        ),
                                      ),
                                      PopupMenuButton<String>(
                                        icon: const Icon(Icons.more_vert, color: Colors.white70),
                                        color: const Color(0xFF1A1F3A),
                                        onSelected: (value) {
                                          if (value == 'edit') _showEditEmployeeModal(emp);
                                          if (value == 'toggle') _toggleEmployeeStatus(emp['id'], isActive);
                                          if (value == 'unbind') _unbindDevice(emp['id']);
                                        },
                                        itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                                          const PopupMenuItem<String>(
                                            value: 'edit',
                                            child: Text('تعديل الملف والمستمسكات', style: TextStyle(color: AppTheme.neonCyan, fontFamily: 'Cairo')),
                                          ),
                                          PopupMenuItem<String>(
                                            value: 'toggle',
                                            child: Text(isActive ? 'تعطيل الحساب' : 'تفعيل الحساب', style: TextStyle(color: isActive ? AppTheme.dangerRed : AppTheme.successGreen, fontFamily: 'Cairo')),
                                          ),
                                          if (hasDevice)
                                            const PopupMenuItem<String>(
                                              value: 'unbind',
                                              child: Text('فك ربط الجهاز (السماح بتسجيل جديد)', style: TextStyle(color: AppTheme.warningOrange, fontFamily: 'Cairo')),
                                            ),
                                        ],
                                      )
                                    ],
                                  ),
                                ],
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
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 8, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
    );
  }
}
