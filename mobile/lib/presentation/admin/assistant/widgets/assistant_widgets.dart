// قطع شاشة المساعد: فقاعة الرسالة، بطاقة الملف (فتح/مشاركة)، بطاقة الوثائق، والترحيب بالأسئلة الجاهزة.

import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../../core/models/models.dart';
import '../../../../core/services/excel_export_service.dart';
import '../../../../core/utils/app_log.dart';
import '../../../shared/ui/ui.dart';
import '../../employee_management/employee_documents.dart';
import '../assistant_logic.dart';

/// تنفيذ قرار على حركة رواتب (الافتراضي: AdminActionsRepository.decidePayrollEvent).
typedef AssistantDecide = Future<void> Function(String eventId, {required bool deduct, required String reason});

class AssistantBubble extends StatelessWidget {
  const AssistantBubble({super.key, required this.message, required this.decide});
  final AssistantMessage message;
  final AssistantDecide decide;

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
              if (message.voice)
                const Padding(
                  padding: EdgeInsets.only(bottom: AppSpace.xs),
                  child: Row(children: [
                    Icon(Icons.mic_rounded, size: 14, color: AppColors.textSecondary),
                    SizedBox(width: AppSpace.xs),
                    Text('سؤال بالصوت · هذا اللي انفهم', style: AppText.caption),
                  ]),
                ),
              SelectableText(user ? message.text : assistantDisplayText(message.text),
                  style: AppText.body.copyWith(color: AppColors.textPrimary, height: 1.6)),
              for (final f in message.files) ...[const SizedBox(height: AppSpace.sm), AssistantFileCard(file: f)],
              for (final d in message.documents) ...[const SizedBox(height: AppSpace.sm), AssistantDocumentsCard(docs: d)],
              for (final d in message.decisions) ...[const SizedBox(height: AppSpace.sm), AssistantDecisionCard(decision: d, decide: decide)],
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

/// بطاقة اقتراح قرار: ما ينفذ شي إلا لما الأدمن يضغط «تأكيد» (أو يختار العكس). بعد التنفيذ تنقفل.
class AssistantDecisionCard extends StatefulWidget {
  const AssistantDecisionCard({super.key, required this.decision, required this.decide});
  final AssistantDecision decision;
  final AssistantDecide decide;

  @override
  State<AssistantDecisionCard> createState() => _AssistantDecisionCardState();
}

class _AssistantDecisionCardState extends State<AssistantDecisionCard> {
  bool _busy = false;
  bool? _doneDeduct;

  Future<void> _apply(bool deduct) async {
    setState(() => _busy = true);
    try {
      final d = widget.decision;
      final reason = deduct == d.suggestDeduct && d.reason.trim().isNotEmpty ? d.reason : (deduct ? 'بدون عذر' : 'عذر مقبول من الإدارة');
      await widget.decide(d.eventId, deduct: deduct, reason: reason);
      if (mounted) setState(() => _doneDeduct = deduct);
    } catch (e) {
      appLog('assistant decision: $e');
      if (mounted) AppSnack.error(context, 'ما تنفذ القرار: ${e.toString().replaceFirst('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.decision;
    final label = kPayrollEventLabels[d.type] ?? d.type;
    final detail = [
      if (d.minutes > 0) '${d.minutes.round()} دقيقة',
      if (d.amount > 0) Fmt.iqd(d.amount),
    ].join(' · ');
    final suggestion = d.suggestDeduct ? 'خصم' : 'إعفاء';
    return AppCard(
      padding: const EdgeInsets.all(AppSpace.md),
      color: AppColors.surface2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            ToneIcon(Icons.gavel_rounded, tone: d.suggestDeduct ? AppTone.danger : AppTone.success),
            const SizedBox(width: AppSpace.md),
            Expanded(child: Text('${d.employee} · $label · ${d.date}', style: AppText.bodySm.copyWith(color: AppColors.textPrimary))),
          ]),
          if (detail.isNotEmpty) Padding(padding: const EdgeInsets.only(top: AppSpace.xs), child: Text(detail, style: AppText.caption)),
          const SizedBox(height: AppSpace.xs),
          Text('الاقتراح: $suggestion — ${d.reason}', style: AppText.bodySm),
          const SizedBox(height: AppSpace.sm),
          if (_doneDeduct != null)
            Text(_doneDeduct! ? '✓ تم الخصم' : '✓ تم الإعفاء',
                style: AppText.bodySm.copyWith(color: _doneDeduct! ? AppTone.danger.color : AppTone.success.color, fontWeight: FontWeight.w700))
          else
            Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: [
              AppButton(
                label: 'تأكيد $suggestion',
                size: AppButtonSize.small,
                variant: d.suggestDeduct ? AppButtonVariant.danger : AppButtonVariant.primary,
                loading: _busy,
                onPressed: () => _apply(d.suggestDeduct),
              ),
              AppButton.secondary(
                label: d.suggestDeduct ? 'إعفاء بدلاً منه' : 'خصم بدلاً منه',
                size: AppButtonSize.small,
                onPressed: _busy ? null : () => _apply(!d.suggestDeduct),
              ),
            ]),
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
