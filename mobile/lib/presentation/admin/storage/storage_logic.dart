// منطق شاشتي التخزين وسلة المحذوفات بدون واجهة.

/// الـ bucket حسب نوع الملف المحذوف.
String bucketForFileType(String fileType) {
  switch (fileType) {
    case 'avatar':
      return 'avatars';
    case 'document':
      return 'employee-documents';
    case 'pledge':
      return 'loan-pledges';
    case 'logo':
      return 'company-logos';
    default:
      return 'employee-documents';
  }
}

/// مجموع أحجام ملفات السلة (الصفوف بلا حجم تُهمل).
double sumTrashBytes(List<Map<String, dynamic>> rows) {
  double totalTrash = 0;
  for (final row in rows) {
    if (row['file_size_bytes'] != null) {
      totalTrash += (row['file_size_bytes'] as num).toDouble();
    }
  }
  return totalTrash;
}

/// توزيع نتيجة get_storage_stats على: الصور الشخصية، الوثائق، التعهدات، وغيرها.
({double avatars, double documents, double pledges, double others}) storageBucketTotals(Object? statsData) {
  double avatars = 0;
  double documents = 0;
  double pledges = 0;
  double others = 0;

  if (statsData != null && statsData is List) {
    for (final raw in statsData) {
      final stat = Map<String, dynamic>.from(raw as Map);
      final bucket = stat['bucket_name']?.toString();
      final size = (stat['total_size'] as num?)?.toDouble() ?? 0.0;
      if (bucket == 'avatars') {
        avatars += size;
      } else if (bucket == 'employee-documents' || bucket == 'documents') {
        documents += size;
      } else if (bucket == 'loan-pledges') {
        pledges += size;
      } else {
        others += size;
      }
    }
  }
  return (avatars: avatars, documents: documents, pledges: pledges, others: others);
}
