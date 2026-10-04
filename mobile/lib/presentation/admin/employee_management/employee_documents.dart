import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/services/image_compression_service.dart';
import '../../../core/services/share_helper.dart';
import '../../../core/services/storage_links.dart';
import '../../../core/services/supabase_service.dart';
import '../../shared/ui/ui.dart';

/// يضغط الصور ويرفعها إلى bucket 'employee-documents' ويرجع روابطها.
Future<List<String>> uploadEmployeeDocuments(List<File> files, String employeeId) async {
  final uploadedUrls = <String>[];
  for (final file in files) {
    try {
      // ضغط الصورة، أو الملف كما هو إذا لم يكن صورة (مثل PDF)
      final processedFile = await ImageCompressionService.compressImage(file);
      final fileName = '$employeeId/${DateTime.now().millisecondsSinceEpoch}_${file.path.split(Platform.pathSeparator).last}';
      await SupabaseService.client.storage.from('employee-documents').upload(fileName, processedFile);
      uploadedUrls.add(SupabaseService.client.storage.from('employee-documents').getPublicUrl(fileName));
    } catch (e) {
      debugPrint('Error compressing/uploading file: $e');
    }
  }
  return uploadedUrls;
}

/// ينزّل الملف مؤقتاً ويفتحه بالتطبيق المناسب.
Future<void> downloadAndOpenDocument(BuildContext context, String url) async {
  try {
    final response = await http.get(Uri.parse(await StorageLinks.resolve(url)));
    if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');
    final dir = await getTemporaryDirectory();
    final ext = url.split('?').first.split('.').last;
    final file = File('${dir.path}/batra_${DateTime.now().millisecondsSinceEpoch}.$ext');
    await file.writeAsBytes(response.bodyBytes);
    await OpenFilex.open(file.path);
  } catch (e) {
    if (context.mounted) AppSnack.error(context, 'تعذّر فتح الملف');
  }
}

/// معاينة وثيقة: صورة قابلة للتكبير أو بطاقة PDF، مع فتح ومشاركة.
Future<void> previewEmployeeDocument(BuildContext context, String url, String title) {
  final isPdf = url.toLowerCase().contains('.pdf');
  return showAppSheet<void>(
    context,
    title: title,
    builder: (ctx) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: AppRadius.card,
          child: Container(
            constraints: const BoxConstraints(maxHeight: 380),
            color: AppColors.surface2,
            child: isPdf
                ? const EmptyView(title: 'مستند PDF', icon: Icons.picture_as_pdf_rounded, tone: AppTone.accent, compact: true)
                : InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 4,
                    child: SignedNetworkImage(
                      url,
                      fit: BoxFit.contain,
                      loadingBuilder: (_, child, p) => p == null ? child : const Skeleton(height: 240, radius: 0),
                      errorBuilder: (_, __, ___) => const EmptyView(title: 'تعذّر تحميل الصورة', icon: Icons.broken_image_rounded, tone: AppTone.danger, compact: true),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: AppSpace.lg),
        AppButton(label: 'فتح أو تنزيل', icon: Icons.open_in_new_rounded, expand: true, onPressed: () => downloadAndOpenDocument(ctx, url)),
        const SizedBox(height: AppSpace.sm),
        AppButton.secondary(
          label: 'مشاركة',
          icon: Icons.ios_share_rounded,
          expand: true,
          onPressed: () => ShareHelper.shareLink(url, ctx),
        ),
      ],
    ),
  );
}

/// شبكة مصغّرات: وثائق موجودة (روابط) + ملفات جديدة + زر إضافة.
class DocumentsGrid extends StatelessWidget {
  const DocumentsGrid({super.key, this.urls = const [], this.files = const [], required this.onAdd, this.onRemoveUrl, required this.onRemoveFile});

  final List<String> urls;
  final List<File> files;
  final VoidCallback onAdd;
  final void Function(int index)? onRemoveUrl;
  final void Function(int index) onRemoveFile;

  static const double _size = 72;

  Widget _thumb(Widget image, VoidCallback? onRemove) {
    return SizedBox(
      width: _size,
      height: _size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: ClipRRect(borderRadius: AppRadius.control, child: image)),
          if (onRemove != null)
            PositionedDirectional(
              top: -8,
              end: -8,
              child: Semantics(
                button: true,
                label: 'إزالة',
                child: InkWell(
                  onTap: onRemove,
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(color: AppColors.danger, shape: BoxShape.circle, border: Border.all(color: AppColors.surface1, width: 2)),
                    child: const Icon(Icons.close_rounded, size: 14, color: AppColors.onStatus),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpace.md,
      runSpacing: AppSpace.md,
      children: [
        for (var i = 0; i < urls.length; i++)
          _thumb(
            SignedNetworkImage(urls[i], fit: BoxFit.cover, cacheWidth: 216, errorBuilder: (_, __, ___) => const ColoredBox(color: AppColors.surface2, child: Icon(Icons.description_rounded, color: AppColors.accent))),
            onRemoveUrl == null ? null : () => onRemoveUrl!(i),
          ),
        for (var i = 0; i < files.length; i++) _thumb(Image.file(files[i], fit: BoxFit.cover, cacheWidth: 216), () => onRemoveFile(i)),
        Semantics(
          button: true,
          label: 'إضافة صور',
          child: InkWell(
            onTap: onAdd,
            borderRadius: AppRadius.control,
            child: Container(
              width: _size,
              height: _size,
              decoration: BoxDecoration(borderRadius: AppRadius.control, border: Border.all(color: AppColors.borderStrong)),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [Icon(Icons.add_a_photo_rounded, color: AppColors.brand), Text('إضافة', style: AppText.caption)],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// نافذة تعديل مستمسكات موظف: حذف القديمة ورفع الجديدة (تُضغط تلقائياً).
Future<bool?> showEditDocumentsSheet(BuildContext context, Map<String, dynamic> emp) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _DocumentsEditor(emp: emp),
  );
}

class _DocumentsEditor extends StatefulWidget {
  const _DocumentsEditor({required this.emp});
  final Map<String, dynamic> emp;

  @override
  State<_DocumentsEditor> createState() => _DocumentsEditorState();
}

class _DocumentsEditorState extends State<_DocumentsEditor> {
  late final List<String> _original = [for (final u in (widget.emp['document_urls'] as List<dynamic>? ?? const [])) u.toString()];
  late final List<String> _existing = List.of(_original);
  final List<File> _new = [];
  bool _saving = false;

  Future<void> _pick() async {
    final picked = await ImagePicker().pickMultiImage();
    if (picked.isNotEmpty) setState(() => _new.addAll(picked.map((x) => File(x.path))));
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      // حذف الوثائق المزالة من التخزين
      for (final url in _original.where((u) => !_existing.contains(u))) {
        try {
          final match = RegExp(r'/employee-documents/(.+)').firstMatch(url);
          if (match != null) {
            await SupabaseService.client.storage.from('employee-documents').remove([match.group(1)!]);
          }
        } catch (e) {
          debugPrint('تعذر حذف المستند القديم من التخزين: $e');
        }
      }
      final newUrls = _new.isEmpty ? <String>[] : await uploadEmployeeDocuments(_new, widget.emp['id'] as String);
      await SupabaseService.client.from('employees').update({'document_urls': [..._existing, ...newUrls]}).eq('id', widget.emp['id'] as Object);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        AppSnack.error(context, 'تعذّر الحفظ: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final removed = _original.length - _existing.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.xl, 0, AppSpace.xl, AppSpace.xl),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('مستمسكات ${widget.emp['full_name'] ?? ''}', style: AppText.title),
            const Text('أزل الصور القديمة أو أضف جديدة — تُضغط الصور تلقائياً.', style: AppText.caption),
            const SizedBox(height: AppSpace.lg),
            DocumentsGrid(
              urls: _existing,
              files: _new,
              onAdd: _pick,
              onRemoveUrl: (i) => setState(() => _existing.removeAt(i)),
              onRemoveFile: (i) => setState(() => _new.removeAt(i)),
            ),
            if (removed > 0) ...[
              const SizedBox(height: AppSpace.md),
              Text('راح تنحذف $removed ${removed == 1 ? 'وثيقة' : 'وثائق'} نهائياً عند الحفظ.', style: AppText.caption.copyWith(color: AppColors.warning)),
            ],
            const SizedBox(height: AppSpace.xl),
            AppButton(label: 'حفظ', icon: Icons.check_rounded, size: AppButtonSize.large, expand: true, loading: _saving, onPressed: _save),
          ],
        ),
      ),
    );
  }
}
