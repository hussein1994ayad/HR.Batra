// =========================================================================
// HR Pro — سلة المحذوفات: الملفات المحذوفة مؤقتاً مع الاستعادة أو الحذف النهائي
// =========================================================================

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/models/models.dart';
import '../../../core/utils/app_log.dart';
import '../../../data/repositories/storage_repository.dart';
import '../../shared/ui/ui.dart';
import 'storage_logic.dart';

class TrashScreen extends StatefulWidget {
  const TrashScreen({super.key});

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  final StorageRepository _repo = StorageRepository();
  bool _isLoading = true;
  bool _hasError = false;
  List<DeletedFileModel> _deletedFiles = [];

  @override
  void initState() {
    super.initState();
    _loadTrashFiles();
  }

  // تحميل قائمة الملفات المحذوفة مؤقتاً
  Future<void> _loadTrashFiles() async {
    setState(() => _isLoading = true);
    try {
      final data = await _repo.fetchTrash();

      if (!mounted) return;
      setState(() {
        _deletedFiles = data;
        _hasError = false;
      });
    } catch (e) {
      appLog('خطأ في جلب بيانات سلة المحذوفات: $e');
      if (mounted) setState(() => _hasError = true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _getFileTypeName(String fileType) {
    switch (fileType) {
      case 'avatar':
        return 'الصورة الشخصية';
      case 'document':
        return 'مستند رسمي';
      case 'pledge':
        return 'تعهد السلفة';
      case 'logo':
        return 'شعار الشركة';
      default:
        return 'ملف آخر';
    }
  }

  // استعادة ملف محذوف (وسمه كمسترجع)
  Future<void> _restoreFile(DeletedFileModel fileRow) async {
    final String fileId = fileRow.id;

    setState(() => _isLoading = true);
    try {
      await _repo.restore(fileId);

      if (mounted) AppSnack.success(context, 'استُعيد الملف');
      unawaited(_loadTrashFiles());
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        AppSnack.error(context, 'تعذّرت الاستعادة: $e');
      }
    }
  }

  // حذف ملف نهائياً من التخزين ومن السجل
  Future<void> _permanentDeleteFile(DeletedFileModel fileRow) async {
    final String fileId = fileRow.id;
    final String filePath = fileRow.filePath!;
    final String fileType = fileRow.fileType!;
    final String bucket = bucketForFileType(fileType);

    setState(() => _isLoading = true);
    try {
      await _repo.deletePermanently(bucket: bucket, filePath: filePath, fileId: fileId);

      if (mounted) AppSnack.success(context, 'حُذف الملف نهائياً');
      unawaited(_loadTrashFiles());
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        AppSnack.error(context, 'تعذّر الحذف: $e');
      }
    }
  }

  static String _formatBytes(Object? bytes) {
    if (bytes is! num) return 'غير محدد';
    final b = bytes.toInt();
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _confirmDelete(DeletedFileModel file) async {
    final ok = await showAppConfirm(
      context,
      title: 'حذف نهائي؟',
      message: 'راح ينحذف الملف من السيرفر وما يمكن استرجاعه أبداً.',
      confirmLabel: 'حذف نهائي',
      destructive: true,
    );
    if (ok) await _permanentDeleteFile(file);
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> content;
    if (_isLoading && _deletedFiles.isEmpty) {
      content = const [SkeletonList(count: 4, itemHeight: 120)];
    } else if (_hasError && _deletedFiles.isEmpty) {
      content = [ErrorView(onRetry: _loadTrashFiles)];
    } else if (_deletedFiles.isEmpty) {
      content = const [EmptyView(title: 'السلة فارغة', message: 'الملفات المحذوفة تبقى هنا 30 يوماً قبل حذفها تلقائياً.', icon: Icons.delete_outline_rounded, tone: AppTone.success)];
    } else {
      content = [
        AppCard(
          tone: AppTone.info,
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.md),
          child: Row(
            children: [
              const Icon(Icons.info_outline_rounded, color: AppColors.info, size: 20),
              const SizedBox(width: AppSpace.sm),
              Expanded(child: Text('${_deletedFiles.length} ملف — تُحذف تلقائياً بعد انتهاء المدة.', style: AppText.bodySm.copyWith(color: AppColors.textPrimary))),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.md),
        for (var i = 0; i < _deletedFiles.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.md),
            child: FadeSlideIn(index: i, child: _fileCard(_deletedFiles[i])),
          ),
      ];
    }
    return AppPage(
      title: 'سلة المحذوفات',
      onRefresh: _loadTrashFiles,
      slivers: [SliverList.list(children: content)],
    );
  }

  Widget _fileCard(DeletedFileModel file) {
    final type = file.fileType ?? '';
    final filename = file.fileName;
    final deletedBy = file.deletedByName;
    final deletedAt = file.deletedAt;
    final expiry = file.scheduledDeletion;
    final daysLeft = expiry?.difference(DateTime.now()).inDays;
    final icon = switch (type) {
      'avatar' => Icons.person_rounded,
      'pledge' => Icons.draw_rounded,
      'logo' => Icons.business_rounded,
      _ => Icons.description_rounded,
    };
    final busy = _isLoading;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ToneIcon(icon, tone: AppTone.neutral),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_getFileTypeName(type), style: AppText.subtitle),
                    Text(filename, style: AppText.caption, maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr),
                  ],
                ),
              ),
              if (daysLeft != null)
                StatusBadge(daysLeft <= 0 ? 'اليوم' : 'باقي ${Fmt.days(daysLeft)}', tone: daysLeft <= 5 ? AppTone.danger : AppTone.warning),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          KeyValueRow('حذفه', deletedBy),
          KeyValueRow('وقت الحذف', deletedAt == null ? '—' : Fmt.relative(deletedAt)),
          KeyValueRow('الحجم', _formatBytes(file.fileSizeBytes)),
          const SizedBox(height: AppSpace.sm),
          Row(
            children: [
              Expanded(child: AppButton.secondary(label: 'استعادة', icon: Icons.settings_backup_restore_rounded, size: AppButtonSize.small, onPressed: busy ? null : () => _restoreFile(file))),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: AppButton(
                  label: 'حذف نهائي',
                  icon: Icons.delete_forever_rounded,
                  variant: AppButtonVariant.dangerGhost,
                  size: AppButtonSize.small,
                  onPressed: busy ? null : () => _confirmDelete(file),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
