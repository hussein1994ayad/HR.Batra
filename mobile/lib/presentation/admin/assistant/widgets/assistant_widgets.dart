// قطع شاشة المساعد: فقاعة الرسالة، بطاقة الملف (فتح/مشاركة)، بطاقة الوثائق، والترحيب بالأسئلة الجاهزة.

import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../../core/models/assistant_models.dart';
import '../../../../core/services/excel_export_service.dart';
import '../../../../core/utils/app_log.dart';
import '../../../shared/ui/ui.dart';
import '../../employee_management/employee_documents.dart';
import '../assistant_logic.dart';

class AssistantBubble extends StatelessWidget {
  const AssistantBubble({super.key, required this.message});
  final AssistantMessage message;

  @override
  Widget build(BuildContext context) {
    final user = message.fromUser;
    final color = user
        ? AppColors.brandContainer
        : message.isError
            ? AppTone.danger.color.withValues(alpha: 0.12)
            : AppColors.surface1;
    return Align(
      alignment: user ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.86),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: AppSpace.xs),
          padding: const EdgeInsets.all(AppSpace.md),
          decoration: BoxDecoration(
            color: color,
            borderRadius: AppRadius.card,
            border: Border.all(color: user ? AppColors.brand.withValues(alpha: 0.3) : AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SelectableText(user ? message.text : assistantDisplayText(message.text),
                  style: AppText.body.copyWith(color: AppColors.textPrimary, height: 1.6)),
              for (final f in message.files) ...[const SizedBox(height: AppSpace.sm), AssistantFileCard(file: f)],
              for (final d in message.documents) ...[const SizedBox(height: AppSpace.sm), AssistantDocumentsCard(docs: d)],
            ],
          ),
        ),
      ),
    );
  }
}

/// ملف Excel جاهز: يُحفظ أول مرة ثم يُفتح أو يُشارك.
class AssistantFileCard extends StatefulWidget {
  const AssistantFileCard({super.key, required this.file});
  final AssistantFile file;

  @override
  State<AssistantFileCard> createState() => _AssistantFileCardState();
}

class _AssistantFileCardState extends State<AssistantFileCard> {
  String? _path;
  bool _busy = false;

  Future<String?> _ensureSaved() async {
    if (_path != null) return _path;
    try {
      _path = await ExcelExportService.saveExcelBytes(base64Decode(widget.file.base64), widget.file.name);
    } catch (e) {
      appLog('assistant file save: $e');
      if (mounted) AppSnack.error(context, 'تعذّر حفظ الملف.');
    }
    return _path;
  }

  Future<void> _run(Future<void> Function(String path) action) async {
    setState(() => _busy = true);
    final path = await _ensureSaved();
    if (path != null) await action(path);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpace.md),
      color: AppColors.surface2,
      child: Row(
        children: [
          const ToneIcon(Icons.table_chart_rounded, tone: AppTone.success),
          const SizedBox(width: AppSpace.md),
          Expanded(child: Text(widget.file.name, style: AppText.bodySm.copyWith(color: AppColors.textPrimary), maxLines: 2)),
          IconButton(
            tooltip: 'فتح',
            icon: const Icon(Icons.open_in_new_rounded),
            onPressed: _busy ? null : () => _run(ExcelExportService.openExcelFile),
          ),
          IconButton(
            tooltip: 'مشاركة',
            icon: const Icon(Icons.ios_share_rounded),
            onPressed: _busy ? null : () => _run((p) => ExcelExportService.shareExcelFile(p, text: widget.file.name)),
          ),
        ],
      ),
    );
  }
}

/// وثائق موظف: كل وثيقة تنفتح بمعاينة (روابط موقّعة عبر StorageLinks).
class AssistantDocumentsCard extends StatelessWidget {
  const AssistantDocumentsCard({super.key, required this.docs});
  final AssistantDocuments docs;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
      color: AppColors.surface2,
      child: Column(
        children: [
          for (var i = 0; i < docs.urls.length; i++)
            AppListTile(
              dense: true,
              leading: ToneIcon(
                docs.urls[i].toLowerCase().contains('.pdf') ? Icons.picture_as_pdf_rounded : Icons.image_rounded,
                size: 36,
              ),
              title: 'وثيقة ${i + 1} — ${docs.employee}',
              onTap: () => previewEmployeeDocument(context, docs.urls[i], 'وثيقة ${i + 1} — ${docs.employee}'),
            ),
        ],
      ),
    );
  }
}

/// أول الشاشة: تعريف قصير + أسئلة جاهزة.
class AssistantWelcome extends StatelessWidget {
  const AssistantWelcome({super.key, required this.onPick});
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpace.lg),
        const Center(child: ToneIcon(Icons.auto_awesome_rounded, tone: AppTone.accent, size: 56)),
        const SizedBox(height: AppSpace.md),
        const Text('مساعد الموارد البشرية', textAlign: TextAlign.center, style: AppText.title),
        const SizedBox(height: AppSpace.xs),
        const Text('اسألني عن دوام أي موظف، الخصومات، السلف، الإجازات أو الوثائق، وأسويلك ملفات Excel.',
            textAlign: TextAlign.center, style: AppText.bodySm),
        const SizedBox(height: AppSpace.lg),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          alignment: WrapAlignment.center,
          children: [for (final s in kAssistantSuggestions) ActionChip(label: Text(s), onPressed: () => onPick(s))],
        ),
      ],
    );
  }
}
