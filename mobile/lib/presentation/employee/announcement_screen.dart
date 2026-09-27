// =========================================================================
// HR Pro — إرسال تعميم للموظفين
// =========================================================================
// عنوان ونص، ثم الاستهداف (الجميع / فرع / أشخاص)، معاينة حيّة كما سيراها
// الموظف، وتأكيد بعدد المستلمين قبل الإرسال. يُرسل كإشعارات (notifications).
// =========================================================================

import 'package:flutter/material.dart';

import '../../core/services/supabase_service.dart';
import '../../core/utils/error_text.dart';
import '../shared/ui/ui.dart';

class AnnouncementScreen extends StatefulWidget {
  const AnnouncementScreen({super.key});

  @override
  State<AnnouncementScreen> createState() => _AnnouncementScreenState();
}

class _AnnouncementScreenState extends State<AnnouncementScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _loadingData = true;
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
    _titleController.addListener(_refresh);
    _bodyController.addListener(_refresh);
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final futures = await Future.wait([
        SupabaseService.client.from('branches').select('id, name').order('name'),
        SupabaseService.client.from('employees').select('id, full_name').eq('is_active', true).order('full_name'),
      ]);
      if (!mounted) return;
      setState(() {
        _branches = List<Map<String, dynamic>>.from(futures[0]);
        _employees = List<Map<String, dynamic>>.from(futures[1]);
      });
    } catch (e) {
      debugPrint('Error loading data: $e');
    } finally {
      if (mounted) setState(() => _loadingData = false);
    }
  }

  String get _targetLabel => switch (_selectedTarget) {
        'branch' => 'موظفو ${_branches.where((b) => b['id'] == _selectedBranchId).firstOrNull?['name'] ?? 'الفرع'}',
        'employees' => '${_selectedEmployeeIds.length} موظف',
        _ => 'كل الموظفين (${_employees.length})',
      };

  Future<void> _sendAnnouncement() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedTarget == 'branch' && _selectedBranchId == null) {
      AppSnack.error(context, 'اختر الفرع');
      return;
    }
    if (_selectedTarget == 'employees' && _selectedEmployeeIds.isEmpty) {
      AppSnack.error(context, 'اختر موظفاً واحداً على الأقل');
      return;
    }

    final ok = await showAppConfirm(context, title: 'إرسال التعميم؟', message: 'راح يوصل إشعار إلى $_targetLabel.', confirmLabel: 'إرسال');
    if (!ok || !mounted) return;

    setState(() => _isLoading = true);

    try {
      List<String> targetEmployeeIds = [];

      if (_selectedTarget == 'all') {
        targetEmployeeIds = _employees.map((e) => e['id'] as String).toList();
      } else if (_selectedTarget == 'branch') {
        final branchEmps = await SupabaseService.client.from('employees').select('id').eq('branch_id', _selectedBranchId!).eq('is_active', true);
        targetEmployeeIds = branchEmps.map((e) => e['id'] as String).toList();
      } else {
        targetEmployeeIds = List.of(_selectedEmployeeIds);
      }

      if (targetEmployeeIds.isEmpty) {
        if (mounted) AppSnack.show(context, 'لا يوجد موظفون في هذا النطاق', tone: AppTone.warning);
        return;
      }

      final notifications = targetEmployeeIds
          .map((id) => {
                'employee_id': id,
                'title': '📢 ${_titleController.text.trim()}',
                'body': _bodyController.text.trim(),
                'type': 'system',
                'is_read': false,
              })
          .toList();

      await SupabaseService.client.from('notifications').insert(notifications);

      if (mounted) {
        _titleController.clear();
        _bodyController.clear();
        AppSnack.success(context, 'وصل التعميم إلى ${targetEmployeeIds.length} موظف');
      }
    } catch (e) {
      debugPrint('Error sending announcement: $e');
      if (mounted) AppSnack.error(context, 'تعذّر الإرسال: ${errorText(e)}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickEmployees() async {
    await showAppSheet<void>(
      context,
      title: 'اختر الموظفين',
      builder: (ctx) => _EmployeePicker(employees: _employees, selected: _selectedEmployeeIds, onChanged: _refresh),
    );
  }

  Future<void> _pickBranch() async {
    final id = await showAppSheet<String>(
      context,
      title: 'اختر الفرع',
      builder: (ctx) => Column(
        children: [
          for (final b in _branches)
            AppListTile(
              dense: true,
              leading: const ToneIcon(Icons.store_rounded, tone: AppTone.accent, size: 36),
              title: b['name'].toString(),
              trailing: b['id'] == _selectedBranchId ? const Icon(Icons.check_rounded, color: AppColors.brand) : null,
              onTap: () => Navigator.pop(ctx, b['id'] as String),
            ),
        ],
      ),
    );
    if (id != null) setState(() => _selectedBranchId = id);
  }

  @override
  Widget build(BuildContext context) {
    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();
    return AppPage(
      title: 'تعميم جديد',
      maxWidth: AppBreakpoints.maxForm,
      body: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextField(
              controller: _titleController,
              label: 'العنوان',
              hint: 'مثلاً: عطلة رسمية يوم الخميس',
              maxLength: 80,
              textInputAction: TextInputAction.next,
              validator: (v) => v == null || v.trim().isEmpty ? 'اكتب عنوان التعميم' : null,
            ),
            const SizedBox(height: AppSpace.lg),
            AppTextField(
              controller: _bodyController,
              label: 'النص',
              hint: 'تفاصيل التعميم...',
              maxLines: 6,
              minLines: 3,
              validator: (v) => v == null || v.trim().isEmpty ? 'اكتب نص التعميم' : null,
            ),
            const SizedBox(height: AppSpace.lg),
            AppChoiceChips<String>(
              label: 'إلى من؟',
              value: _selectedTarget,
              options: const [
                ('all', 'الجميع', Icons.groups_rounded),
                ('branch', 'فرع', Icons.store_rounded),
                ('employees', 'أشخاص', Icons.person_add_alt_1_rounded),
              ],
              onChanged: (v) => setState(() => _selectedTarget = v),
            ),
            if (_selectedTarget == 'branch') ...[
              const SizedBox(height: AppSpace.md),
              AppPickerField(
                label: 'الفرع',
                icon: Icons.store_rounded,
                value: _branches.where((b) => b['id'] == _selectedBranchId).firstOrNull?['name']?.toString(),
                placeholder: 'اختر الفرع',
                onTap: _loadingData ? null : _pickBranch,
              ),
            ],
            if (_selectedTarget == 'employees') ...[
              const SizedBox(height: AppSpace.md),
              AppPickerField(
                label: 'الموظفون',
                icon: Icons.person_search_rounded,
                value: _selectedEmployeeIds.isEmpty ? null : 'تم اختيار ${_selectedEmployeeIds.length} موظف',
                placeholder: 'اختر الموظفين',
                onTap: _loadingData ? null : _pickEmployees,
              ),
            ],
            const SectionHeader('معاينة'),
            AppCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const ToneIcon(Icons.campaign_rounded, tone: AppTone.info),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title.isEmpty ? 'عنوان التعميم' : title, style: AppText.subtitle.copyWith(color: title.isEmpty ? AppColors.textMuted : null)),
                        const SizedBox(height: AppSpace.xs),
                        Text(body.isEmpty ? 'هنا يظهر النص كما سيراه الموظف.' : body, style: AppText.bodySm),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.sm),
            Text('يصل إلى: $_targetLabel', style: AppText.caption),
            const SizedBox(height: AppSpace.xxl),
            AppButton(label: 'إرسال التعميم', icon: Icons.send_rounded, size: AppButtonSize.large, expand: true, loading: _isLoading, onPressed: _sendAnnouncement),
          ],
        ),
      ),
    );
  }
}

/// قائمة اختيار متعدد للموظفين مع بحث وتحديد الكل.
class _EmployeePicker extends StatefulWidget {
  const _EmployeePicker({required this.employees, required this.selected, required this.onChanged});
  final List<Map<String, dynamic>> employees;
  final List<String> selected;
  final VoidCallback onChanged;

  @override
  State<_EmployeePicker> createState() => _EmployeePickerState();
}

class _EmployeePickerState extends State<_EmployeePicker> {
  String _q = '';

  void _toggle(String id, bool on) {
    setState(() => on ? widget.selected.add(id) : widget.selected.remove(id));
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.employees.where((e) => _q.isEmpty || e['full_name'].toString().contains(_q)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          decoration: const InputDecoration(hintText: 'بحث بالاسم', prefixIcon: Icon(Icons.search_rounded)),
          onChanged: (v) => setState(() => _q = v.trim()),
        ),
        Row(
          children: [
            Expanded(child: Text('${widget.selected.length} مختار', style: AppText.caption)),
            TextButton(
              onPressed: () {
                setState(() {
                  widget.selected
                    ..clear()
                    ..addAll(items.map((e) => e['id'] as String));
                });
                widget.onChanged();
              },
              child: const Text('تحديد الكل'),
            ),
            TextButton(
              onPressed: () {
                setState(widget.selected.clear);
                widget.onChanged();
              },
              child: const Text('مسح'),
            ),
          ],
        ),
        for (final e in items)
          CheckboxListTile.adaptive(
            value: widget.selected.contains(e['id']),
            title: Text(e['full_name'].toString(), style: AppText.body),
            secondary: AppAvatar(name: e['full_name'].toString(), size: 36),
            contentPadding: EdgeInsets.zero,
            onChanged: (v) => _toggle(e['id'] as String, v ?? false),
          ),
        const SizedBox(height: AppSpace.md),
        AppButton(label: 'تم', expand: true, onPressed: () => Navigator.pop(context)),
      ],
    );
  }
}
