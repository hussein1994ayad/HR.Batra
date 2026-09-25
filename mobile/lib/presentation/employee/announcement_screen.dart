// =========================================================================
// نظام HR Pro v6.0 - شاشة إرسال التعاميم والإعلانات
// =========================================================================

import 'package:flutter/material.dart';
import '../../core/design/design.dart';
import '../../core/services/supabase_service.dart';
import '../shared/widgets/glass_background.dart';
import '../shared/widgets/glass_container.dart';

class AnnouncementScreen extends StatefulWidget {
  const AnnouncementScreen({super.key});

  @override
  State<AnnouncementScreen> createState() => _AnnouncementScreenState();
}

class _AnnouncementScreenState extends State<AnnouncementScreen> {
  bool _isLoading = false;
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  
  String _selectedTarget = 'all'; // 'all', 'branch', 'employees'
  String? _selectedBranchId;
  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _employees = [];
  final List<String> _selectedEmployeeIds = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final futures = await Future.wait([
        SupabaseService.client.from('branches').select('id, name').order('name'),
        SupabaseService.client.from('employees').select('id, full_name').eq('is_active', true).order('full_name'),
      ]);
      setState(() {
        _branches = List<Map<String, dynamic>>.from(futures[0]);
        _employees = List<Map<String, dynamic>>.from(futures[1]);
      });
    } catch (e) {
      debugPrint('Error loading data: $e');
    }
  }

  Future<void> _sendAnnouncement() async {
    if (_titleController.text.isEmpty || _bodyController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرجاء كتابة عنوان ونص التعميم', style: TextStyle(fontFamily: 'Cairo'))),
      );
      return;
    }

    if (_selectedTarget == 'branch' && _selectedBranchId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرجاء اختيار الفرع', style: TextStyle(fontFamily: 'Cairo'))),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      List<String> targetEmployeeIds = [];

      if (_selectedTarget == 'all') {
        targetEmployeeIds = _employees.map((e) => e['id'] as String).toList();
      } else if (_selectedTarget == 'branch') {
        // Get employees in this branch
        final branchEmps = await SupabaseService.client
            .from('employees')
            .select('id')
            .eq('branch_id', _selectedBranchId!)
            .eq('is_active', true);
        
        targetEmployeeIds = (branchEmps as List).map((e) => e['id'] as String).toList();
      } else if (_selectedTarget == 'employees') {
        if (_selectedEmployeeIds.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('الرجاء اختيار موظف واحد على الأقل', style: TextStyle(fontFamily: 'Cairo'))),
          );
          return;
        }
        targetEmployeeIds = _selectedEmployeeIds;
      }

      if (targetEmployeeIds.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('لا يوجد موظفين في هذا النطاق', style: TextStyle(fontFamily: 'Cairo')), backgroundColor: AppColors.warning),
          );
        }
        setState(() => _isLoading = false);
        return;
      }

      // Prepare bulk insert
      final notifications = targetEmployeeIds.map((id) => {
        'employee_id': id,
        'title': '📢 ${_titleController.text}',
        'body': _bodyController.text,
        'type': 'system',
        'is_read': false,
      }).toList();

      await SupabaseService.client.from('notifications').insert(notifications);

      if (mounted) {
        _titleController.clear();
        _bodyController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم إرسال التعميم بنجاح إلى ${targetEmployeeIds.length} موظف', style: const TextStyle(fontFamily: 'Cairo')), backgroundColor: AppColors.success),
        );
      }
    } catch (e) {
      debugPrint('Error sending announcement: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e', style: const TextStyle(fontFamily: 'Cairo')), backgroundColor: AppColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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
          title: const Text('إرسال تعميم', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textPrimary)),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GlassContainer(
                padding: const EdgeInsets.all(20),
                borderRadius: 20,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('محتوى التعميم', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textPrimary)),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _titleController,
                      style: const TextStyle(fontFamily: 'Cairo', color: AppColors.textPrimary, fontSize: 14),
                      decoration: InputDecoration(
                        labelText: 'عنوان التعميم (مثال: هام وعاجل)',
                        labelStyle: const TextStyle(fontFamily: 'Cairo', color: AppColors.textMuted, fontSize: 12),
                        filled: true,
                        fillColor: AppColors.textPrimary.withValues(alpha: 0.05),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.brand)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _bodyController,
                      maxLines: 5,
                      style: const TextStyle(fontFamily: 'Cairo', color: AppColors.textPrimary, fontSize: 14),
                      decoration: InputDecoration(
                        labelText: 'نص التعميم التفصيلي...',
                        labelStyle: const TextStyle(fontFamily: 'Cairo', color: AppColors.textMuted, fontSize: 12),
                        filled: true,
                        fillColor: AppColors.textPrimary.withValues(alpha: 0.05),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.brand)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              GlassContainer(
                padding: const EdgeInsets.all(20),
                borderRadius: 20,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('الاستهداف', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textPrimary)),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _buildTargetChoice('الجميع', 'all', Icons.people_alt_rounded),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildTargetChoice('فرع', 'branch', Icons.business_rounded),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildTargetChoice('أشخاص', 'employees', Icons.person_add_alt_1_rounded),
                        ),
                      ],
                    ),
                    if (_selectedTarget == 'branch') ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: AppColors.textPrimary.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedBranchId,
                            hint: const Text('اختر الفرع...', style: TextStyle(fontFamily: 'Cairo', color: AppColors.textMuted, fontSize: 12)),
                            isExpanded: true,
                            dropdownColor: AppColors.surface2,
                            style: const TextStyle(fontFamily: 'Cairo', color: AppColors.textPrimary, fontSize: 14),
                            items: _branches.map((b) {
                              return DropdownMenuItem<String>(
                                value: b['id'] as String?,
                                child: Text(b['name'] as String),
                              );
                            }).toList(),
                            onChanged: (val) => setState(() => _selectedBranchId = val),
                          ),
                        ),
                      ),
                    ],
                    if (_selectedTarget == 'employees') ...[
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _showEmployeeSelectionDialog,
                          icon: const Icon(Icons.person_search_rounded, color: AppColors.brand),
                          label: Text(_selectedEmployeeIds.isEmpty ? 'اختر الموظفين' : 'تم تحديد ${_selectedEmployeeIds.length} موظف', style: const TextStyle(fontFamily: 'Cairo', color: AppColors.textPrimary)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.textPrimary.withValues(alpha: 0.05),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _sendAnnouncement,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brand,
                    foregroundColor: AppColors.onStatus,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: _isLoading
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: AppColors.onStatus, strokeWidth: 2))
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.send_rounded),
                            SizedBox(width: 8),
                            Text('إرسال التعميم الآن', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16)),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTargetChoice(String label, String value, IconData icon) {
    final isSelected = _selectedTarget == value;
    return GestureDetector(
      onTap: () => setState(() => _selectedTarget = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.brand.withValues(alpha: 0.2) : AppColors.textPrimary.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isSelected ? AppColors.brand : AppColors.border),
        ),
        child: Column(
          children: [
            Icon(icon, color: isSelected ? AppColors.brand : AppColors.textMuted, size: 28),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? AppColors.brand : AppColors.textMuted,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showEmployeeSelectionDialog() {
    showDialog<dynamic>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.surface2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text('اختيار الموظفين', style: TextStyle(fontFamily: 'Cairo', color: AppColors.textPrimary)),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _employees.length,
                  itemBuilder: (context, index) {
                    final emp = _employees[index];
                    final isSelected = _selectedEmployeeIds.contains(emp['id']);
                    return CheckboxListTile(
                      title: Text(emp['full_name'] as String, style: const TextStyle(fontFamily: 'Cairo', color: AppColors.textPrimary, fontSize: 14)),
                      value: isSelected,
                      activeColor: AppColors.brand,
                      checkColor: AppColors.onStatus,
                      onChanged: (val) {
                        setDialogState(() {
                          if (val == true) {
                            _selectedEmployeeIds.add(emp['id'] as String);
                          } else {
                            _selectedEmployeeIds.remove(emp['id']);
                          }
                        });
                        setState(() {});
                      },
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('تم', style: TextStyle(fontFamily: 'Cairo', color: AppColors.brand)),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
