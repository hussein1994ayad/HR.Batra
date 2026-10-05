// =========================================================================
// ملف بسلة المحذوفات — الجدول: public.deleted_files (مع اسم من حذفه من employees)
// =========================================================================

import '../utils/json_map.dart';

class DeletedFileModel {
  final String id;
  final String? filePath;

  /// 'avatar' | 'document' | 'pledge' | 'logo'
  final String? fileType;

  /// اسم من حذف الملف، أو 'غير معروف'.
  final String deletedByName;
  final DateTime? deletedAt;

  /// موعد الحذف النهائي التلقائي (بالتوقيت المحلي).
  final DateTime? scheduledDeletion;

  /// null = الحجم غير مسجل.
  final num? fileSizeBytes;

  const DeletedFileModel({
    required this.id,
    this.filePath,
    this.fileType,
    this.deletedByName = 'غير معروف',
    this.deletedAt,
    this.scheduledDeletion,
    this.fileSizeBytes,
  });

  factory DeletedFileModel.fromMap(JsonRow map) {
    final employees = map['employees'];
    final size = map['file_size_bytes'];
    return DeletedFileModel(
      id: map.str('id') ?? '',
      filePath: map.str('file_path'),
      fileType: map.str('file_type'),
      deletedByName: employees is Map ? (employees['full_name'] ?? 'غير معروف').toString() : 'غير معروف',
      deletedAt: DateTime.tryParse(map['deleted_at']?.toString() ?? ''),
      scheduledDeletion: DateTime.tryParse(map['scheduled_deletion_date']?.toString() ?? '')?.toLocal(),
      fileSizeBytes: size is num ? size : null,
    );
  }

  /// اسم الملف بدون المسار.
  String get fileName => (filePath ?? '').split('/').last;
}
