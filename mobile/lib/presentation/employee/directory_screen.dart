// =========================================================================
// نظام HR Pro v6.0 - دليل الموظفين الآمن والمصرح به (Employee Directory Screen)
// =========================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../shared/widgets/glass_container.dart';
import '../shared/widgets/glass_background.dart';

class EmployeeDirectoryScreen extends StatefulWidget {
  const EmployeeDirectoryScreen({super.key});

  @override
  State<EmployeeDirectoryScreen> createState() => _EmployeeDirectoryScreenState();
}

class _EmployeeDirectoryScreenState extends State<EmployeeDirectoryScreen> {
  List<Map<String, dynamic>> _allEmployees = [];
  List<Map<String, dynamic>> _filteredEmployees = [];
  bool _isLoading = true;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadDirectory();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // جلب البيانات من الـ view المخصص والمحمي والمحسّن بقاعدة البيانات
  Future<void> _loadDirectory() async {
    setState(() => _isLoading = true);

    try {
      final data = await SupabaseService.client
          .from('v_employee_directory')
          .select()
          .order('full_name');

      setState(() {
        _allEmployees = List<Map<String, dynamic>>.from(data);
        _filteredEmployees = _allEmployees;
      });
    } catch (e) {
      debugPrint('خطأ في تحميل دليل الموظفين: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // تصفية نتائج البحث الفوري
  void _filterSearch(String query) {
    if (query.trim().isEmpty) {
      setState(() {
        _filteredEmployees = _allEmployees;
      });
      return;
    }

    final lowerQuery = query.toLowerCase();
    setState(() {
      _filteredEmployees = _allEmployees.where((emp) {
        final name = (emp['full_name'] ?? '').toLowerCase();
        final dept = (emp['department_name'] ?? '').toLowerCase();
        final code = (emp['employee_code'] ?? '').toLowerCase();
        return name.contains(lowerQuery) || dept.contains(lowerQuery) || code.contains(lowerQuery);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          iconTheme: const IconThemeData(color: Colors.white),
          title: const Text(
            'دليل الموظفين المعتمد',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        body: Column(
          children: [
            // شريط البحث المتميز بقلم HSL المضيء
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                controller: _searchController,
                onChanged: _filterSearch,
                style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'Cairo'),
                decoration: InputDecoration(
                  hintText: 'ابحث بالاسم، القسم، أو كود الموظف...',
                  hintStyle: const TextStyle(color: Colors.white54, fontSize: 13, fontFamily: 'Cairo'),
                  prefixIcon: const Icon(Icons.search, color: AppTheme.neonCyan),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, color: Colors.white70),
                          onPressed: () {
                            _searchController.clear();
                            _filterSearch('');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.04),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: AppTheme.neonCyan),
                  ),
                ),
              ),
            ),

            // قائمة دليل الموظفين
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppTheme.neonCyan))
                  : _filteredEmployees.isEmpty
                      ? const Center(
                          child: Text(
                            'لم يتم العثور على أي موظف مطابق للبحث 🔍',
                            style: TextStyle(fontSize: 12, color: Colors.white70, fontFamily: 'Cairo'),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadDirectory,
                          color: AppTheme.neonCyan,
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            itemCount: _filteredEmployees.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final emp = _filteredEmployees[index];
                              final avatarUrl = emp['avatar_url'] ?? '';
                              final name = emp['full_name'] ?? 'موظف';
                              final dept = emp['department_name'] ?? 'القسم العام';
                              final branch = emp['branch_name'] ?? 'الفرع العام';
                              final phone = emp['phone'] ?? 'غير متوفر';
                              final code = emp['employee_code'] ?? 'EMP-000';

                              return GlassContainer(
                                padding: const EdgeInsets.all(14),
                                borderRadius: 20,
                                opacity: 0.1,
                                borderColor: AppTheme.neonCyan.withOpacity(0.2),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppTheme.neonCyan.withOpacity(0.04),
                                    blurRadius: 16,
                                  )
                                ],
                                child: Row(
                                  children: [
                                    // الصورة الشخصية
                                    Container(
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(color: AppTheme.neonCyan, width: 1.5),
                                      ),
                                      child: CircleAvatar(
                                        radius: 26,
                                        backgroundColor: Colors.white.withOpacity(0.04),
                                        backgroundImage: avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                                        child: avatarUrl.isEmpty
                                            ? const Icon(Icons.person, color: AppTheme.neonCyan)
                                            : null,
                                      ),
                                    ),
                                    const SizedBox(width: 14),

                                    // تفاصيل الموظف
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Text(
                                                name,
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white, fontFamily: 'Cairo'),
                                              ),
                                              const SizedBox(width: 8),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: AppTheme.neonCyan.withOpacity(0.15),
                                                  borderRadius: BorderRadius.circular(6),
                                                  border: Border.all(color: AppTheme.neonCyan.withOpacity(0.3), width: 1),
                                                ),
                                                child: Text(
                                                  code,
                                                  style: const TextStyle(fontSize: 8, color: AppTheme.neonCyan, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '$dept - $branch',
                                            style: const TextStyle(fontSize: 11, color: Colors.white70, fontFamily: 'Cairo'),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'الهاتف: $phone',
                                            style: const TextStyle(fontSize: 10, color: Colors.white54, fontFamily: 'Cairo'),
                                          ),
                                        ],
                                      ),
                                    ),
                                    
                                    // زر نسخ الهاتف أو المساعدة
                                    IconButton(
                                      icon: const Icon(Icons.copy_rounded, color: AppTheme.neonCyan, size: 20),
                                      onPressed: () {
                                        // نسخ رقم الهاتف للحافظة
                                        Clipboard.setData(ClipboardData(text: phone));
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            content: Text('تم نسخ رقم الهاتف للحافظة بنجاح! 📋', style: TextStyle(fontFamily: 'Cairo')),
                                            backgroundColor: AppTheme.successGreen,
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
