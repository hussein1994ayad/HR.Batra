import 'package:supabase_flutter/supabase_flutter.dart';

/// تعديل أو حذف ما وصل لأي سطر = صلاحية السيرفر منعته بصمت (الشي للأدمن بس)، أو السجل ما موجود.
/// يطلع خطأ واضح بدل «تم الحفظ» وهو ما تغيّر شي (تدقيق 14/10/2026، BUG-006 / CODE-009).
/// الاستعمال: `ensureChanged(await _db.from('x').update(...).eq('id', id).select('id'));`
void ensureChanged(List<dynamic> rows) {
  if (rows.isEmpty) {
    throw const PostgrestException(
      message: 'ما تغيّر شي: هذي العملية لمسؤول النظام (الأدمن) فقط، أو السجل ما موجود.',
      code: '42501',
    );
  }
}
