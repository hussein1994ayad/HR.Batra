// =========================================================================
// نظام HR Pro v6.0 - دليل الموظفين الذكي والملف الشخصي والوثائق
// =========================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/services/auth_service.dart';
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

  // فلاتر سريعة
  String _selectedBranch = 'all';
  List<String> _branchOptions = ['all'];

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

  /// دالة تسوية الحروف العربية للبحث الفوري الدقيق
  String _normalizeArabic(String text) {
    return text
        .replaceAll(RegExp(r'[أإآٱ]'), 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي')
        .replaceAll('ئ', 'ي')
        .replaceAll('ؤ', 'و')
        .replaceAll(RegExp(r'[\u064B-\u065F]'), '') // إزالة الحركات
        .trim()
        .toLowerCase();
  }

  /// جلب البيانات من الـ view المخصص والمحمي بقاعدة البيانات
  Future<void> _loadDirectory() async {
    setState(() => _isLoading = true);

    try {
      final data = await SupabaseService.client
          .from('v_employee_directory')
          .select()
          .order('full_name');

      if (!mounted) return;
      final list = List<Map<String, dynamic>>.from(data);
      final branches = {'all', ...list.map((e) => (e['branch_name'] ?? '').toString()).where((b) => b.isNotEmpty)};

      setState(() {
        _allEmployees = list;
        _branchOptions = branches.toList();
        _applyFilters();
      });
    } catch (e) {
      debugPrint('خطأ في تحميل دليل الموظفين: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// تطبيق البحث والتصفية الفورية بمجرد كتابة أي حرف
  void _applyFilters() {
    final query = _searchController.text.trim();
    final normalizedQuery = _normalizeArabic(query);

    setState(() {
      _filteredEmployees = _allEmployees.where((emp) {
        // تصفية الفرع
        if (_selectedBranch != 'all' && (emp['branch_name'] ?? '') != _selectedBranch) {
          return false;
        }

        // إذا كان البحث فارغاً، يظهر جميع الموظفين في الفرع
        if (normalizedQuery.isEmpty) return true;

        final name = _normalizeArabic(emp['full_name'] ?? '');
        final dept = _normalizeArabic(emp['department_name'] ?? '');
        final branch = _normalizeArabic(emp['branch_name'] ?? '');
        final code = (emp['employee_code'] ?? '').toLowerCase();
        final phone = (emp['phone'] ?? '').toString();
        final email = (emp['email'] ?? '').toLowerCase();

        return name.contains(normalizedQuery) ||
            dept.contains(normalizedQuery) ||
            branch.contains(normalizedQuery) ||
            code.contains(normalizedQuery) ||
            phone.contains(query) ||
            email.contains(query.toLowerCase());
      }).toList();
    });
  }

  /// فتح الملف الشخصي الشامل للموظف مع استعراض وتنزيل كافة وثائقه
  void _showEmployeeProfileModal(Map<String, dynamic> emp) {
    final name = emp['full_name'] ?? 'موظف';
    final avatarUrl = emp['avatar_url'] ?? '';
    final dept = emp['department_name'] ?? 'القسم العام';
    final branch = emp['branch_name'] ?? 'الفرع العام';
    final phone = emp['phone'] ?? 'غير مسجل';
    final email = emp['email'] ?? 'غير مسجل';
    final code = emp['employee_code'] ?? 'EMP-000';
    final role = emp['role'] == 'admin' ? 'مدير نظام 👑' : emp['role'] == 'manager' ? 'مدير فرع 👔' : 'موظف 👤';
    final List<dynamic> docUrls = emp['document_urls'] as List<dynamic>? ?? [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.92,
        expand: false,
        builder: (_, scrollController) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: ListView(
            controller: scrollController,
            children: [
              // مقبض السحب
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                ),
              ),

              // ترويسة بطاقة الموظف
              Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.neonCyan, width: 2),
                      boxShadow: [BoxShadow(color: AppTheme.neonCyan.withValues(alpha: 0.3), blurRadius: 10)],
                    ),
                    child: CircleAvatar(
                      radius: 30,
                      backgroundColor: Colors.white.withValues(alpha: 0.08),
                      backgroundImage: avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                      child: avatarUrl.isEmpty ? const Icon(Icons.person, color: AppTheme.neonCyan, size: 30) : null,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white)),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.neonCyan.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(code, style: const TextStyle(fontFamily: 'Cairo', fontSize: 10, color: AppTheme.neonCyan, fontWeight: FontWeight.bold)),
                            ),
                            const SizedBox(width: 6),
                            Text(role, style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, color: Colors.white70)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white60),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // أزرار التواصل السريع (اتصال، واتساب، نسخ)
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
                        foregroundColor: AppTheme.successGreen,
                        side: const BorderSide(color: AppTheme.successGreen),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      icon: const Icon(Icons.phone_rounded, size: 16),
                      label: const Text('اتصال 📞', style: TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold)),
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
                        foregroundColor: AppTheme.neonCyan,
                        side: const BorderSide(color: AppTheme.neonCyan),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      icon: const Icon(Icons.chat_bubble_rounded, size: 16),
                      label: const Text('واتساب 💬', style: TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: phone));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('تم نسخ رقم الهاتف 📋', style: TextStyle(fontFamily: 'Cairo')),
                          backgroundColor: AppTheme.primaryTeal,
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    icon: const Icon(Icons.copy_rounded, color: Colors.white70, size: 18),
                    tooltip: 'نسخ الرقم',
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // بطاقة المعلومات الوظيفية
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  children: [
                    _buildInfoRow(Icons.domain_rounded, 'الفرع', branch, AppTheme.neonCyan),
                    const Divider(color: Colors.white10, height: 16),
                    _buildInfoRow(Icons.apartment_rounded, 'القسم', dept, AppTheme.cyberPurple),
                    const Divider(color: Colors.white10, height: 16),
                    _buildInfoRow(Icons.phone_iphone_rounded, 'الهاتف', phone, AppTheme.successGreen),
                    const Divider(color: Colors.white10, height: 16),
                    _buildInfoRow(Icons.email_rounded, 'البريد', email, Colors.amber),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // قسم وثائق ومستندات الموظف
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.folder_shared_rounded, color: AppTheme.neonCyan, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'وثائق ومستندات الموظف (${docUrls.length}) 📁',
                        style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                      ),
                    ],
                  ),
                  if (docUrls.length > 1)
                    TextButton.icon(
                      onPressed: () async {
                        final text = docUrls.map((u) => u.toString()).join('\n');
                        await Share.share(text, subject: 'وثائق الموظف: $name');
                      },
                      icon: const Icon(Icons.share_rounded, color: AppTheme.neonCyan, size: 14),
                      label: const Text('مشاركة الكل', style: TextStyle(fontFamily: 'Cairo', fontSize: 10, color: AppTheme.neonCyan)),
                    ),
                ],
              ),

              const SizedBox(height: 10),

              if (docUrls.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.02),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                  ),
                  child: const Center(
                    child: Text('لا توجد وثائق أو مستمسكات مرفوعة لهذا الموظف حتى الآن.', style: TextStyle(fontFamily: 'Cairo', color: Colors.white38, fontSize: 11)),
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
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.neonCyan.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: (isPdf ? AppTheme.neonPink : AppTheme.neonCyan).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            isPdf ? Icons.picture_as_pdf_rounded : Icons.image_rounded,
                            color: isPdf ? AppTheme.neonPink : AppTheme.neonCyan,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('وثيقة رسمية رقم #$idx', style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white)),
                              Text(isPdf ? 'مستند PDF رقمي' : 'صورة / مستمسك معتمد', style: const TextStyle(fontFamily: 'Cairo', fontSize: 10, color: Colors.white54)),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.visibility_rounded, color: AppTheme.neonCyan, size: 18),
                          tooltip: 'معاينة',
                          onPressed: () {
                            _previewImageDialog(url, 'وثيقة الموظف #$idx');
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.download_rounded, color: AppTheme.successGreen, size: 18),
                          tooltip: 'تنزيل ومشاركة',
                          onPressed: () async {
                            await Share.shareUri(Uri.parse(url));
                          },
                        ),
                      ],
                    ),
                  );
                }),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  void _previewImageDialog(String url, String title) {
    showDialog(
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
                  Text(title, style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13)),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white60, size: 18),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 340),
                  color: Colors.black38,
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
                          Text('مستند PDF رقمي', style: TextStyle(fontFamily: 'Cairo', color: Colors.white70, fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              ElevatedButton.icon(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await Share.shareUri(Uri.parse(url));
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryTeal,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.share_rounded, size: 16),
                label: const Text('تنزيل / مشاركة الوثيقة 📤', style: TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 8),
        Text('$label: ', style: const TextStyle(fontFamily: 'Cairo', color: Colors.white60, fontSize: 11)),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontFamily: 'Cairo', color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
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
          centerTitle: true,
          iconTheme: const IconThemeData(color: Colors.white),
          title: const Text(
            'دليل الموظفين المعتمد 👥',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Colors.white,
            ),
          ),
        ),
        body: Column(
          children: [
            // شريط البحث الذكي الفوري
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
              child: TextField(
                controller: _searchController,
                onChanged: (val) => _applyFilters(),
                style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'Cairo'),
                decoration: InputDecoration(
                  hintText: 'ابحث بالاسم، القسم، الفرع، كود الموظف، أو الهاتف...',
                  hintStyle: const TextStyle(color: Colors.white54, fontSize: 11, fontFamily: 'Cairo'),
                  prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.neonCyan, size: 20),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, color: Colors.white70, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            _applyFilters();
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.05),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppTheme.neonCyan),
                  ),
                ),
              ),
            ),

            // فلاتر الفروع السريعة
            if (_branchOptions.length > 2)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: _branchOptions.map((br) {
                    final isSelected = _selectedBranch == br;
                    final label = br == 'all' ? 'جميع الفروع (${_allEmployees.length})' : br;

                    return GestureDetector(
                      onTap: () {
                        setState(() => _selectedBranch = br);
                        _applyFilters();
                      },
                      child: Container(
                        margin: const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isSelected ? AppTheme.neonCyan.withValues(alpha: 0.25) : Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: isSelected ? AppTheme.neonCyan : Colors.white12),
                        ),
                        child: Text(
                          label,
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 10.5,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? Colors.white : Colors.white60,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
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
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final emp = _filteredEmployees[index];
                              final avatarUrl = emp['avatar_url'] ?? '';
                              final name = emp['full_name'] ?? 'موظف';
                              final dept = emp['department_name'] ?? 'القسم العام';
                              final branch = emp['branch_name'] ?? 'الفرع العام';
                              final phone = emp['phone'] ?? 'غير متوفر';
                              final code = emp['employee_code'] ?? 'EMP-000';
                              final List<dynamic> docs = emp['document_urls'] as List<dynamic>? ?? [];

                              return InkWell(
                                onTap: () => _showEmployeeProfileModal(emp),
                                borderRadius: BorderRadius.circular(16),
                                child: GlassContainer(
                                  padding: const EdgeInsets.all(12),
                                  borderRadius: 16,
                                  opacity: 0.08,
                                  borderColor: AppTheme.neonCyan.withValues(alpha: 0.18),
                                  child: Row(
                                    children: [
                                      // الصورة الشخصية
                                      Container(
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(color: AppTheme.neonCyan, width: 1.5),
                                        ),
                                        child: CircleAvatar(
                                          radius: 24,
                                          backgroundColor: Colors.white.withValues(alpha: 0.04),
                                          backgroundImage: avatarUrl.isNotEmpty
                                              ? ResizeImage.resizeIfNeeded(100, 100, NetworkImage(avatarUrl))
                                              : null,
                                          child: avatarUrl.isEmpty
                                              ? const Icon(Icons.person, color: AppTheme.neonCyan, size: 22)
                                              : null,
                                        ),
                                      ),
                                      const SizedBox(width: 12),

                                      // تفاصيل الموظف
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    name,
                                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white, fontFamily: 'Cairo'),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                                  decoration: BoxDecoration(
                                                    color: AppTheme.neonCyan.withValues(alpha: 0.15),
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: Text(
                                                    code,
                                                    style: const TextStyle(fontSize: 8.5, color: AppTheme.neonCyan, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              '$dept • $branch',
                                              style: const TextStyle(fontSize: 10.5, color: Colors.white70, fontFamily: 'Cairo'),
                                            ),
                                            const SizedBox(height: 2),
                                            Row(
                                              children: [
                                                Text(
                                                  phone,
                                                  style: const TextStyle(fontSize: 9.5, color: Colors.white54, fontFamily: 'Cairo'),
                                                ),
                                                if (docs.isNotEmpty) ...[
                                                  const SizedBox(width: 8),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                                    decoration: BoxDecoration(
                                                      color: AppTheme.successGreen.withValues(alpha: 0.15),
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                    child: Text(
                                                      '${docs.length} وثائق 📁',
                                                      style: const TextStyle(fontSize: 8, color: AppTheme.successGreen, fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),

                                      const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white38, size: 14),
                                    ],
                                  ),
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

