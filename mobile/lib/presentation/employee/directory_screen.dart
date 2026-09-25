// =========================================================================
// HR Pro — دليل الموظفين: بحث فوري بالعربي، فلتر الفرع، وبطاقة تواصل ووثائق
// =========================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';


import '../../core/services/supabase_service.dart';
import '../shared/ui/ui.dart';

class EmployeeDirectoryScreen extends StatefulWidget {
  const EmployeeDirectoryScreen({super.key});

  @override
  State<EmployeeDirectoryScreen> createState() => _EmployeeDirectoryScreenState();
}

class _EmployeeDirectoryScreenState extends State<EmployeeDirectoryScreen> {
  List<Map<String, dynamic>> _allEmployees = [];
  List<Map<String, dynamic>> _filteredEmployees = [];
  bool _isLoading = true;
  bool _hasError = false;
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

  /// قائمة الزملاء من دالة get_employee_directory (أعمدة غير حساسة فقط).
  /// الـ View مقيّد بـ RLS ويعيد صف الموظف نفسه فقط.
  Future<void> _loadDirectory() async {
    setState(() => _isLoading = true);

    try {
      final dynamic data =
          await SupabaseService.client.rpc<dynamic>('get_employee_directory');

      if (!mounted) return;
      final list = (data as List<dynamic>)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final branches = {'all', ...list.map((e) => (e['branch_name'] ?? '').toString()).where((b) => b.isNotEmpty)};

      setState(() {
        _allEmployees = list;
        _hasError = false;
        _branchOptions = branches.toList();
        _applyFilters();
      });
    } catch (e) {
      debugPrint('خطأ في تحميل دليل الموظفين: $e');
      if (mounted) setState(() => _hasError = true);
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

        final name = _normalizeArabic((emp['full_name'] ?? '') as String);
        final dept = _normalizeArabic((emp['department_name'] ?? '') as String);
        final branch = _normalizeArabic((emp['branch_name'] ?? '') as String);
        final code = (emp['employee_code'] ?? '').toString().toLowerCase();
        final phone = (emp['phone'] ?? '').toString();
        final email = (emp['email'] ?? '').toString().toLowerCase();

        return name.contains(normalizedQuery) ||
            dept.contains(normalizedQuery) ||
            branch.contains(normalizedQuery) ||
            code.contains(normalizedQuery) ||
            phone.contains(query) ||
            email.contains(query.toLowerCase());
      }).toList();
    });
  }

  // بطاقة الموظف: تواصل سريع، معلومات العمل، والوثائق
  void _showEmployeeProfileModal(Map<String, dynamic> emp) {
    final name = (emp['full_name'] ?? 'موظف').toString();
    final phone = (emp['phone'] ?? '').toString();
    final hasPhone = phone.trim().isNotEmpty;
    final role = switch (emp['role']) {
      'admin' => 'مدير نظام',
      'manager' => 'مدير فرع',
      _ => 'موظف',
    };
    final docUrls = [for (final u in (emp['document_urls'] as List<dynamic>? ?? const [])) u.toString()];

    showAppSheet<void>(
      context,
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AppAvatar(name: name, url: emp['avatar_url']?.toString(), size: 60),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: AppText.title),
                    const SizedBox(height: AppSpace.xs),
                    Wrap(
                      spacing: AppSpace.xs,
                      runSpacing: AppSpace.xs,
                      children: [
                        StatusBadge((emp['employee_code'] ?? '—').toString(), tone: AppTone.brand),
                        StatusBadge(role),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.lg),
          Row(
            children: [
              Expanded(
                child: AppButton.secondary(
                  label: 'اتصال',
                  icon: Icons.phone_rounded,
                  onPressed: hasPhone
                      ? () async {
                          final uri = Uri.parse('tel:$phone');
                          if (await canLaunchUrl(uri)) await launchUrl(uri);
                        }
                      : null,
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: AppButton.secondary(
                  label: 'واتساب',
                  icon: Icons.chat_rounded,
                  onPressed: hasPhone
                      ? () async {
                          final cleanPhone = phone.replaceAll(RegExp(r'\D'), '');
                          final uri = Uri.parse('https://wa.me/$cleanPhone');
                          if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
                        }
                      : null,
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              AppIconButton(
                icon: Icons.copy_rounded,
                tooltip: 'نسخ الرقم',
                onPressed: hasPhone
                    ? () {
                        Clipboard.setData(ClipboardData(text: phone));
                        AppSnack.info(context, 'نُسخ رقم الهاتف');
                      }
                    : null,
              ),
            ],
          ),
          const SizedBox(height: AppSpace.lg),
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.sm),
            child: Column(
              children: [
                KeyValueRow('الفرع', (emp['branch_name'] ?? '—').toString(), icon: Icons.store_rounded),
                KeyValueRow('القسم', (emp['department_name'] ?? '—').toString(), icon: Icons.apartment_rounded),
                KeyValueRow('الهاتف', hasPhone ? phone : 'غير مسجل', icon: Icons.phone_iphone_rounded),
                KeyValueRow('البريد', (emp['email'] ?? 'غير مسجل').toString(), icon: Icons.alternate_email_rounded),
              ],
            ),
          ),
          SectionHeader(
            'الوثائق (${docUrls.length})',
            actionLabel: docUrls.length > 1 ? 'مشاركة الكل' : null,
            onAction: () => SharePlus.instance.share(ShareParams(text: docUrls.join('\n'), subject: 'وثائق الموظف: $name')),
          ),
          if (docUrls.isEmpty)
            const Text('لا توجد وثائق مرفوعة لهذا الموظف.', style: AppText.caption)
          else
            for (var i = 0; i < docUrls.length; i++)
              AppListTile(
                dense: true,
                leading: ToneIcon(
                  docUrls[i].toLowerCase().contains('.pdf') ? Icons.picture_as_pdf_rounded : Icons.image_rounded,
                  tone: docUrls[i].toLowerCase().contains('.pdf') ? AppTone.accent : AppTone.brand,
                  size: 36,
                ),
                title: 'وثيقة ${i + 1}',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(tooltip: 'معاينة', icon: const Icon(Icons.visibility_rounded), onPressed: () => _previewImageDialog(docUrls[i], 'وثيقة ${i + 1}')),
                    IconButton(
                      tooltip: 'مشاركة',
                      icon: const Icon(Icons.ios_share_rounded),
                      onPressed: () => SharePlus.instance.share(ShareParams(uri: Uri.parse(docUrls[i]))),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  void _previewImageDialog(String url, String title) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        contentPadding: const EdgeInsets.all(AppSpace.lg),
        content: ClipRRect(
          borderRadius: AppRadius.control,
          child: Container(
            constraints: const BoxConstraints(maxHeight: 360),
            color: AppColors.surface1,
            child: Image.network(
              url,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const EmptyView(title: 'مستند PDF', icon: Icons.picture_as_pdf_rounded, tone: AppTone.accent, compact: true),
            ),
          ),
        ),
        actions: [
          AppButton.ghost(label: 'إغلاق', onPressed: () => Navigator.pop(ctx)),
          AppButton(
            label: 'مشاركة',
            icon: Icons.ios_share_rounded,
            onPressed: () async {
              Navigator.pop(ctx);
              await SharePlus.instance.share(ShareParams(uri: Uri.parse(url)));
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget list;
    if (_isLoading && _allEmployees.isEmpty) {
      list = const Padding(padding: EdgeInsets.all(AppSpace.page), child: SkeletonList(count: 6));
    } else if (_hasError && _allEmployees.isEmpty) {
      list = ErrorView(onRetry: _loadDirectory);
    } else if (_filteredEmployees.isEmpty) {
      list = EmptyView(
        title: _allEmployees.isEmpty ? 'الدليل فارغ' : 'ما لقينا نتيجة',
        message: _allEmployees.isEmpty ? null : 'جرّب اسماً أو قسماً أو رقماً ثانياً.',
        icon: Icons.person_search_rounded,
      );
    } else {
      list = ListView.builder(
        padding: const EdgeInsets.fromLTRB(AppSpace.page, AppSpace.sm, AppSpace.page, AppSpace.x4),
        itemCount: _filteredEmployees.length,
        itemBuilder: (context, index) {
          final emp = _filteredEmployees[index];
          final docs = (emp['document_urls'] as List<dynamic>? ?? const []).length;
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: ContentWidth(
              child: AppCard(
                padding: EdgeInsets.zero,
                onTap: () => _showEmployeeProfileModal(emp),
                child: AppListTile(
                  leading: AppAvatar(name: (emp['full_name'] ?? '').toString(), url: emp['avatar_url']?.toString()),
                  title: (emp['full_name'] ?? 'موظف').toString(),
                  subtitle: '${emp['department_name'] ?? 'القسم العام'} · ${emp['branch_name'] ?? 'الفرع العام'}',
                  trailing: docs > 0 ? StatusBadge('$docs وثائق', tone: AppTone.success, icon: Icons.folder_rounded) : null,
                  onTap: () => _showEmployeeProfileModal(emp),
                ),
              ),
            ),
          );
        },
      );
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text('دليل الموظفين${_allEmployees.isEmpty ? '' : ' (${_allEmployees.length})'}'),
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(_branchOptions.length > 2 ? 124 : 72),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.page, 0, AppSpace.page, AppSpace.sm),
            child: Column(
              children: [
                ContentWidth(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (_) => _applyFilters(),
                    textInputAction: TextInputAction.search,
                    style: AppText.body,
                    decoration: InputDecoration(
                      hintText: 'ابحث بالاسم، القسم، الكود أو الهاتف',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'مسح البحث',
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () {
                                _searchController.clear();
                                _applyFilters();
                              },
                            ),
                    ),
                  ),
                ),
                if (_branchOptions.length > 2) ...[
                  const SizedBox(height: AppSpace.sm),
                  AppChoiceChips<String>(
                    scrollable: true,
                    value: _selectedBranch,
                    options: [for (final b in _branchOptions) (b, b == 'all' ? 'كل الفروع' : b, null)],
                    onChanged: (b) {
                      setState(() => _selectedBranch = b);
                      _applyFilters();
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      body: RefreshIndicator.adaptive(onRefresh: _loadDirectory, child: list is ListView ? list : ListView(children: [list])),
    );
  }
}
