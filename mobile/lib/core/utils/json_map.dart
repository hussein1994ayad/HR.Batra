// =========================================================================
// قراءة آمنة لصفوف Supabase
// =========================================================================
// صفوف PostgREST تصل كـ Map<String, dynamic>. الوصول المتسلسل مثل
// row['employees']?['full_name'] استدعاء على dynamic (avoid_dynamic_calls)
// ويرمي عند اختلاف النوع. هذه الدوال تتحقق من النوع وترجع null بدلاً من ذلك.
//
//   final name = row.obj('employees')?.str('full_name') ?? 'موظف';
// =========================================================================

typedef JsonRow = Map<String, dynamic>;

/// يحوّل نتيجة select (List<dynamic>) إلى قائمة صفوف، ويتجاهل أي عنصر ليس Map.
List<JsonRow> rowsOf(Object? value) {
  if (value is! List) return const [];
  return [
    for (final item in value)
      if (item is Map) Map<String, dynamic>.from(item),
  ];
}

/// صف واحد من maybeSingle/single، أو null.
JsonRow? rowOf(Object? value) => value is Map ? Map<String, dynamic>.from(value) : null;

extension JsonMap on JsonRow {
  String? str(String key) {
    final v = this[key];
    if (v == null) return null;
    return v is String ? v : v.toString();
  }

  double? dbl(String key) {
    final v = this[key];
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  int? integer(String key) {
    final v = this[key];
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  bool? boolean(String key) {
    final v = this[key];
    return v is bool ? v : null;
  }

  /// تاريخ/وقت ISO بالتوقيت المحلي للجهاز.
  DateTime? date(String key) {
    final v = str(key);
    return v == null ? null : DateTime.tryParse(v)?.toLocal();
  }

  /// كائن مضمّن من join (قد يصل ككائن أو كمصفوفة من عنصر واحد).
  JsonRow? obj(String key) {
    final v = this[key];
    if (v is Map) return Map<String, dynamic>.from(v);
    if (v is List && v.isNotEmpty && v.first is Map) {
      return Map<String, dynamic>.from(v.first as Map);
    }
    return null;
  }

  List<JsonRow> list(String key) => rowsOf(this[key]);

  List<int> ints(String key) {
    final v = this[key];
    if (v is! List) return const [];
    return [
      for (final e in v)
        if (e is num) e.toInt() else if (e is String && int.tryParse(e) != null) int.parse(e),
    ];
  }
}
