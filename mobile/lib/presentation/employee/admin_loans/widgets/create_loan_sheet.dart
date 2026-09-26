import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';


import '../../../../core/models/models.dart';
import '../../../../core/utils/arabic_format.dart';
import '../../../../core/utils/input_formatters.dart';
import '../../../../data/repositories/loan_repository.dart';
import '../../../shared/ui/ui.dart';

/// نافذة منح سلفة مباشرة لموظف. ترجع true بعد الحفظ.
Future<bool?> showCreateLoanSheet(BuildContext context, {required List<LoanEmployeeOption> employees, required LoanRepository repo}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _CreateLoanSheet(employees: employees, repo: repo),
  );
}

class _CreateLoanSheet extends StatefulWidget {
  const _CreateLoanSheet({required this.employees, required this.repo});

  final List<LoanEmployeeOption> employees;
  final LoanRepository repo;

  @override
  State<_CreateLoanSheet> createState() => _CreateLoanSheetState();
}

class _CreateLoanSheetState extends State<_CreateLoanSheet> {
  final _amount = TextEditingController();
  final _months = TextEditingController(text: '5');
  final _notes = TextEditingController();
  String? _employeeId;
  File? _pledge;
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _months.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _error(String message) => AppSnack.error(context, message);

  Future<void> _pickPledge() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 80);
    if (picked != null && mounted) setState(() => _pledge = File(picked.path));
  }

  Future<void> _submit() async {
    final employeeId = _employeeId;
    final amount = parseThousands(_amount.text);
    final months = int.tryParse(_months.text.trim()) ?? 0;
    if (employeeId == null) return _error('اختر الموظف');
    if (amount <= 0) return _error('اكتب مبلغ السلفة');
    if (months <= 0) return _error('اكتب عدد أشهر السداد');
    // pledge_url عمود إلزامي في الجدول
    final pledge = _pledge;
    if (pledge == null) return _error('صوّر التعهد الموقّع أولاً');

    setState(() => _saving = true);
    try {
      final pledgeUrl = await widget.repo.uploadPledge(employeeId, pledge);
      final now = DateTime.now();
      final lastDay = DateTime(now.year, now.month + 2, 0).day;
      await widget.repo.createDirectLoan(
        employeeId: employeeId,
        amount: amount,
        months: months,
        firstDue: DateTime(now.year, now.month + 1, now.day > lastDay ? lastDay : now.day),
        pledgeUrl: pledgeUrl,
        notes: _notes.text.trim().isEmpty ? 'سلفة إدارية مباشرة' : _notes.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint('Error creating direct loan: $e');
      if (mounted) {
        setState(() => _saving = false);
        _error('تعذّرت إضافة السلفة: $e');
      }
    }
  }

  Future<void> _pickEmployee() async {
    final id = await showAppOptions(
      context,
      title: 'الموظف',
      current: _employeeId,
      options: [for (final e in widget.employees) (e.id, e.branchName == null ? e.fullName : '${e.fullName} · ${e.branchName}')],
    );
    if (id != null) setState(() => _employeeId = id);
  }

  @override
  Widget build(BuildContext context) {
    final employee = widget.employees.where((e) => e.id == _employeeId).firstOrNull;
    final amount = parseThousands(_amount.text);
    final months = int.tryParse(_months.text.trim()) ?? 0;
    final installment = amount > 0 && months > 0 ? (amount / months).ceilToDouble() : 0.0;
    final salary = employee?.monthlySalary ?? 0;
    final overHalf = salary > 0 && installment > salary / 2;

    return Padding(
      padding: EdgeInsets.fromLTRB(AppSpace.xl, 0, AppSpace.xl, AppSpace.xl + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('سلفة مباشرة لموظف', style: AppText.title),
            const Text('تُعتمد فوراً وتتولّد أقساطها تلقائياً.', style: AppText.caption),
            const SizedBox(height: AppSpace.lg),
            AppPickerField(
              label: 'الموظف',
              icon: Icons.person_search_rounded,
              value: employee?.fullName,
              placeholder: 'اختر الموظف',
              onTap: _saving ? null : _pickEmployee,
            ),
            if (salary > 0)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: AppSpace.sm, top: AppSpace.xs),
                child: Text('الراتب ${Fmt.iqd(salary)}', style: AppText.caption),
              ),
            const SizedBox(height: AppSpace.lg),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: AppTextField(
                    controller: _amount,
                    label: 'المبلغ (د.ع)',
                    hint: '1.000.000',
                    keyboardType: TextInputType.number,
                    inputFormatters: [DotThousandsSeparatorInputFormatter()],
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  flex: 2,
                  child: AppTextField(
                    controller: _months,
                    label: 'الأشهر',
                    hint: '5',
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.md),
            AppCard(
              tone: overHalf ? AppTone.warning : null,
              color: AppColors.surface2,
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  KeyValueRow('القسط الشهري', installment > 0 ? Fmt.iqd(installment) : '—', bold: true, valueColor: AppColors.brand),
                  if (overHalf)
                    Text('القسط أكثر من نصف الراتب — النظام سيرفض السلفة. زِد عدد الأشهر.', style: AppText.caption.copyWith(color: AppColors.warning)),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            AppTextField(controller: _notes, label: 'ملاحظات', hint: 'سبب منح السلفة (اختياري)', maxLines: 2),
            const SizedBox(height: AppSpace.lg),
            AppCard(
              tone: _pledge != null ? AppTone.success : null,
              onTap: _saving ? null : _pickPledge,
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.md),
              child: Row(
                children: [
                  Icon(_pledge != null ? Icons.task_alt_rounded : Icons.photo_camera_rounded, color: _pledge != null ? AppColors.success : AppColors.brand),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Text(
                      _pledge != null ? 'صُوّر التعهد — اضغط لإعادة التصوير' : 'تصوير التعهد الموقّع (إلزامي)',
                      style: AppText.bodySm.copyWith(color: AppColors.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.xl),
            AppButton(label: 'اعتماد السلفة', icon: Icons.check_rounded, size: AppButtonSize.large, expand: true, loading: _saving, onPressed: _submit),
          ],
        ),
      ),
    );
  }
}
