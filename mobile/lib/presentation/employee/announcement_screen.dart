// =========================================================================
// نظام HR Pro v6.0 - شاشة إرسال التعاميم والإعلانات
// =========================================================================

import 'package:flutter/material.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
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
  List<String> _selectedEmployeeIds = [];

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
        final assignments = await SupabaseService.client
            .from('branch_assignments')
            .select('employee_id')
            .eq('branch_id', _selectedBranchId!);
        
        targetEmployeeIds = (assignments as List).map((e) => e['employee_id'] as String).toList();
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
            const SnackBar(content: Text('لا يوجد موظفين في هذا النطاق', style: TextStyle(fontFamily: 'Cairo')), backgroundColor: AppTheme.warningOrange),
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
          SnackBar(content: Text('تم إرسال التعميم بنجاح إلى ${targetEmployeeIds.length} موظف ✅', style: const TextStyle(fontFamily: 'Cairo')), backgroundColor: AppTheme.successGreen),
        );
      }
    } catch (e) {
      debugPrint('Error sending announcement: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e', style: const TextStyle(fontFamily: 'Cairo')), backgroundColor: AppTheme.dangerRed),
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
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text('إرسال تعميم 📢', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GlassContainer(
                padding: const EdgeInsets.all(20),
                borderRadius: 20,
                opacity: 0.08,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('محتوى التعميم', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white)),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _titleController,
                      style: const TextStyle(fontFamily: 'Cairo', color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        labelText: 'عنوان التعميم (مثال: هام وعاجل)',
                        labelStyle: const TextStyle(fontFamily: 'Cairo', color: Colors.white54, fontSize: 12),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.05),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppTheme.neonCyan)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _bodyController,
                      maxLines: 5,
                      style: const TextStyle(fontFamily: 'Cairo', color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        labelText: 'نص التعميم التفصيلي...',
                        labelStyle: const TextStyle(fontFamily: 'Cairo', color: Colors.white54, fontSize: 12),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.05),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppTheme.neonCyan)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              GlassContainer(
                padding: const EdgeInsets.all(20),
                borderRadius: 20,
                opacity: 0.08,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('الاستهداف', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white)),
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
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedBranchId,
                            hint: const Text('اختر الفرع...', style: TextStyle(fontFamily: 'Cairo', color: Colors.white54, fontSize: 12)),
                            isExpanded: true,
                            dropdownColor: const Color(0xFF1A1F3A),
                            style: const TextStyle(fontFamily: 'Cairo', color: Colors.white, fontSize: 14),
                            items: _branches.map((b) {
                              return DropdownMenuItem<String>(
                                value: b['id'],
                                child: Text(b['name']),
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
                          icon: const Icon(Icons.person_search_rounded, color: AppTheme.neonCyan),
                          label: Text(_selectedEmployeeIds.isEmpty ? 'اختر الموظفين' : 'تم تحديد ${_selectedEmployeeIds.length} موظف', style: const TextStyle(fontFamily: 'Cairo', color: Colors.white)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white.withOpacity(0.05),
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
                    backgroundColor: AppTheme.neonCyan,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: _isLoading
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
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
          color: isSelected ? AppTheme.neonCyan.withOpacity(0.2) : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isSelected ? AppTheme.neonCyan : Colors.white10),
        ),
        child: Column(
          children: [
            Icon(icon, color: isSelected ? AppTheme.neonCyan : Colors.white54, size: 28),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? AppTheme.neonCyan : Colors.white54,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showEmployeeSelectionDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1A1F3A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text('اختيار الموظفين', style: TextStyle(fontFamily: 'Cairo', color: Colors.white)),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _employees.length,
                  itemBuilder: (context, index) {
                    final emp = _employees[index];
                    final isSelected = _selectedEmployeeIds.contains(emp['id']);
                    return CheckboxListTile(
                      title: Text(emp['full_name'], style: const TextStyle(fontFamily: 'Cairo', color: Colors.white, fontSize: 14)),
                      value: isSelected,
                      activeColor: AppTheme.neonCyan,
                      checkColor: Colors.black,
                      onChanged: (val) {
                        setDialogState(() {
                          if (val == true) {
                            _selectedEmployeeIds.add(emp['id']);
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
                  child: const Text('تم', style: TextStyle(fontFamily: 'Cairo', color: AppTheme.neonCyan)),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
