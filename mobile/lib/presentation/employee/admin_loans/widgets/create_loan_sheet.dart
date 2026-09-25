import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/design/design.dart';
import '../../../../core/models/models.dart';
import '../../../../core/utils/arabic_format.dart';
import '../../../../core/utils/input_formatters.dart';
import '../../../../data/repositories/loan_repository.dart';

/// نافذة منح سلفة مباشرة لموظف. ترجع true بعد الحفظ.
Future<bool?> showCreateLoanSheet(BuildContext context, {required List<LoanEmployeeOption> employees, required LoanRepository repo}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
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

  void _error(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message, style: const TextStyle(fontFamily: 'Cairo')), backgroundColor: AppColors.danger),
    );
  }

  Future<void> _pickPledge() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 80);
    if (picked != null && mounted) setState(() => _pledge = File(picked.path));
  }

  Future<void> _submit() async {
    final employeeId = _employeeId;
    final amount = parseThousands(_amount.text);
    final months = int.tryParse(_months.text.trim()) ?? 0;
    if (employeeId == null) return _error('يرجى اختيار الموظف المستفيد أولاً!');
    if (amount <= 0) return _error('يرجى إدخال مبلغ سلفة صحيح أكبر من الصفر!');
    if (months <= 0) return _error('يرجى إدخال عدد أشهر سداد صحيح (شهر واحد على الأقل)!');
    // pledge_url عمود إلزامي في الجدول
    final pledge = _pledge;
    if (pledge == null) return _error('يرجى تصوير التعهد الخطي الموقّع أولاً!');

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
        _error('فشل إضافة السلفة: $e');
      }
    }
  }

  InputDecoration _decoration(String hint, {String? suffix}) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontFamily: 'Cairo', color: AppColors.textDisabled, fontSize: 12),
        suffixText: suffix,
        suffixStyle: const TextStyle(fontFamily: 'Cairo', color: AppColors.brand, fontWeight: FontWeight.bold),
        filled: true,
        fillColor: AppColors.textPrimary.withValues(alpha: 0.06),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.border)),
      );

  static const _label = TextStyle(fontFamily: 'Cairo', fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.bold);
  static const _input = TextStyle(fontFamily: 'Cairo', color: AppColors.textPrimary, fontWeight: FontWeight.bold);

  @override
  Widget build(BuildContext context) {
    final hasPledge = _pledge != null;
    return Container(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 24, top: 24, left: 20, right: 20),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        border: Border.all(color: AppColors.brand.withValues(alpha: 0.4), width: 1.5),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.add_circle_rounded, color: AppColors.brand, size: 24),
                    SizedBox(width: 10),
                    Text('إضافة سلفة جديدة لموظف ➕',
                        style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textPrimary)),
                  ],
                ),
                IconButton(icon: const Icon(Icons.close_rounded, color: AppColors.textMuted), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 16),
            const Text('اختر الموظف المستفيد:', style: _label),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: AppColors.textPrimary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  dropdownColor: AppColors.surface2,
                  value: _employeeId,
                  hint: const Text('اضغط لاختيار موظف...', style: TextStyle(fontFamily: 'Cairo', color: AppColors.textDisabled, fontSize: 12)),
                  items: [
                    for (final emp in widget.employees)
                      DropdownMenuItem(
                        value: emp.id,
                        child: Text('${emp.fullName} (${emp.branchName ?? ''})',
                            style: const TextStyle(fontFamily: 'Cairo', color: AppColors.textPrimary, fontSize: 13)),
                      ),
                  ],
                  onChanged: (v) => setState(() => _employeeId = v),
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text('مبلغ السلفة الإجمالي (دينار عراقي):', style: _label),
            const SizedBox(height: 6),
            TextField(
              controller: _amount,
              keyboardType: TextInputType.number,
              inputFormatters: [DotThousandsSeparatorInputFormatter()],
              style: _input,
              decoration: _decoration('مثال: 1.000.000', suffix: 'د.ع'),
            ),
            const SizedBox(height: 14),
            const Text('مدة السداد (عدد الأشهر):', style: _label),
            const SizedBox(height: 6),
            TextField(
              controller: _months,
              keyboardType: TextInputType.number,
              style: _input,
              decoration: _decoration('مثال: 5', suffix: 'أشهر'),
            ),
            const SizedBox(height: 14),
            const Text('ملاحظات وسبب منح السلفة:', style: _label),
            const SizedBox(height: 6),
            TextField(
              controller: _notes,
              maxLines: 2,
              style: const TextStyle(fontFamily: 'Cairo', color: AppColors.textPrimary, fontSize: 12),
              decoration: _decoration('اكتب تفاصيل أو سبب منح السلفة...'),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _saving ? null : _pickPledge,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: hasPledge ? AppColors.success : AppColors.brand.withValues(alpha: 0.5)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                icon: Icon(hasPledge ? Icons.check_circle_rounded : Icons.camera_alt_rounded,
                    color: hasPledge ? AppColors.success : AppColors.brand, size: 18),
                label: Text(
                  hasPledge ? 'تم التقاط صورة التعهد ✅' : 'تصوير التعهد الخطي (إلزامي) 📷',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: hasPledge ? AppColors.success : AppColors.textPrimary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _saving ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: AppColors.textPrimary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: _saving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: AppColors.textPrimary, strokeWidth: 2))
                    : const Text('حفظ واعتماد السلفة مباشرة 💸',
                        style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 14)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
