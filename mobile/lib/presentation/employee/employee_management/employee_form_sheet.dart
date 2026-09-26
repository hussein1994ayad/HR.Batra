import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/utils/arabic_format.dart';
import '../../../core/utils/input_formatters.dart';
import '../../shared/ui/ui.dart';
import 'employee_documents.dart';

/// نافذة إضافة موظف جديد (حساب دخول عبر create_employee_secure). ترجع true بعد الإنشاء.
Future<bool?> showEmployeeFormSheet(BuildContext context, {required List<Map<String, dynamic>> branches}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _EmployeeForm(branches: branches),
  );
}

class _EmployeeForm extends StatefulWidget {
  const _EmployeeForm({required this.branches});
  final List<Map<String, dynamic>> branches;

  @override
  State<_EmployeeForm> createState() => _EmployeeFormState();
}

class _EmployeeFormState extends State<_EmployeeForm> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _salary = TextEditingController();
  String _role = 'employee';
  String? _branchId;
  final List<File> _documents = [];
  bool _saving = false;
  bool _showPassword = true;

  @override
  void dispose() {
    for (final c in [_name, _email, _password, _phone, _code, _salary]) {
      c.dispose();
    }
    super.dispose();
  }

  /// كلمة مرور مؤقتة سهلة القراءة (يغيّرها الموظف عند أول دخول).
  void _generatePassword() {
    const chars = 'abcdefghjkmnpqrstuvwxyz23456789';
    final r = Random.secure();
    setState(() => _password.text = List.generate(10, (_) => chars[r.nextInt(chars.length)]).join());
  }

  Future<void> _pickDocuments() async {
    final picked = await ImagePicker().pickMultiImage();
    if (picked.isNotEmpty) setState(() => _documents.addAll(picked.map((x) => File(x.path))));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final newEmpId = const Uuid().v4();
      final uploadedDocs = _documents.isEmpty ? <String>[] : await uploadEmployeeDocuments(_documents, newEmpId);
      final empCode = _code.text.trim().isNotEmpty ? _code.text.trim() : 'EMP-${DateTime.now().millisecondsSinceEpoch % 10000}';

      await SupabaseService.client.rpc<dynamic>('create_employee_secure', params: {
        'p_email': _email.text.trim(),
        'p_password': _password.text,
        'p_full_name': _name.text.trim(),
        'p_phone': _phone.text.trim(),
        'p_role': _role,
        'p_branch_id': _branchId,
        'p_monthly_salary_iqd': parseThousands(_salary.text),
        'p_document_urls': uploadedDocs,
        'p_employee_code': empCode,
        'p_employee_id': newEmpId,
        'p_join_date': DateTime.now().toIso8601String().split('T')[0],
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        AppSnack.error(context, 'تعذّر إنشاء الحساب: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final branchName = widget.branches.where((b) => b['id'] == _branchId).firstOrNull?['name']?.toString();
    return Padding(
      padding: EdgeInsets.fromLTRB(AppSpace.xl, 0, AppSpace.xl, AppSpace.xl + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('موظف جديد', style: AppText.title),
              const Text('يُنشأ حساب دخول، ويُطلب من الموظف تغيير كلمة المرور أول مرة.', style: AppText.caption),
              const SizedBox(height: AppSpace.lg),
              AppTextField(
                controller: _name,
                label: 'الاسم الكامل',
                icon: Icons.person_rounded,
                textInputAction: TextInputAction.next,
                validator: (v) => v == null || v.trim().length < 3 ? 'اكتب الاسم الكامل' : null,
              ),
              const SizedBox(height: AppSpace.md),
              AppTextField(
                controller: _email,
                label: 'البريد الإلكتروني',
                hint: 'name@company.com',
                icon: Icons.alternate_email_rounded,
                keyboardType: TextInputType.emailAddress,
                textDirection: TextDirection.ltr,
                textInputAction: TextInputAction.next,
                validator: (v) {
                  final val = v?.trim() ?? '';
                  if (val.isEmpty) return 'اكتب البريد';
                  if (!RegExp(r'^[\w.\-]+@([\w\-]+\.)+[\w\-]{2,}$').hasMatch(val)) return 'صيغة البريد غير صحيحة';
                  return null;
                },
              ),
              const SizedBox(height: AppSpace.md),
              AppTextField(
                controller: _password,
                label: 'كلمة مرور مؤقتة',
                icon: Icons.lock_outline_rounded,
                obscureText: !_showPassword,
                textDirection: TextDirection.ltr,
                validator: (v) => v == null || v.length < 6 ? '6 خانات على الأقل' : null,
                suffix: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(tooltip: 'توليد كلمة مرور', icon: const Icon(Icons.auto_awesome_rounded), onPressed: _generatePassword),
                    IconButton(
                      tooltip: 'نسخ',
                      icon: const Icon(Icons.copy_rounded),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: _password.text));
                        AppSnack.info(context, 'نُسخت كلمة المرور — أرسلها للموظف');
                      },
                    ),
                    IconButton(
                      tooltip: _showPassword ? 'إخفاء' : 'إظهار',
                      icon: Icon(_showPassword ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                      onPressed: () => setState(() => _showPassword = !_showPassword),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpace.md),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: AppTextField(controller: _phone, label: 'الهاتف', hint: '07xxxxxxxxx', keyboardType: TextInputType.phone, textDirection: TextDirection.ltr),
                  ),
                  const SizedBox(width: AppSpace.md),
                  Expanded(child: AppTextField(controller: _code, label: 'الكود الوظيفي', hint: 'تلقائي', textDirection: TextDirection.ltr)),
                ],
              ),
              const SizedBox(height: AppSpace.md),
              AppChoiceChips<String>(
                label: 'الصلاحية',
                value: _role,
                options: const [('employee', 'موظف', null), ('manager', 'مدير فرع', null), ('admin', 'أدمن', null)],
                onChanged: (v) => setState(() => _role = v),
              ),
              const SizedBox(height: AppSpace.md),
              AppPickerField(
                label: 'الفرع',
                icon: Icons.store_rounded,
                value: branchName,
                placeholder: 'اختر الفرع (مطلوب للبصمة)',
                onTap: () async {
                  final id = await showAppOptions(context, title: 'الفرع', current: _branchId, options: [for (final b in widget.branches) (b['id'] as String, b['name'].toString())]);
                  if (id != null) setState(() => _branchId = id);
                },
              ),
              const SizedBox(height: AppSpace.md),
              AppTextField(
                controller: _salary,
                label: 'الراتب الشهري (د.ع)',
                hint: '750.000',
                icon: Icons.payments_outlined,
                keyboardType: TextInputType.number,
                inputFormatters: [DotThousandsSeparatorInputFormatter()],
              ),
              const SizedBox(height: AppSpace.lg),
              Text('المستمسكات (اختياري)', style: AppText.bodySm.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: AppSpace.sm),
              DocumentsGrid(
                files: _documents,
                onAdd: _pickDocuments,
                onRemoveFile: (i) => setState(() => _documents.removeAt(i)),
              ),
              const SizedBox(height: AppSpace.xl),
              AppButton(label: 'إنشاء الحساب', icon: Icons.person_add_rounded, size: AppButtonSize.large, expand: true, loading: _saving, onPressed: _save),
            ],
          ),
        ),
      ),
    );
  }
}
