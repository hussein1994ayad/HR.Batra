// طابور JSON محلي (ملف بمجلد التطبيق) لما ينحفظ بدون إنترنت ويُرفع لاحقاً:
// نقاط التتبع، أحداث دخول/خروج الفروع، وأحداث السياج الجغرافي — كلها نفس الطريقة.

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class OfflineJsonQueue {
  OfflineJsonQueue(this.fileName, {Future<Directory> Function()? directory})
      : _directory = directory ?? getApplicationDocumentsDirectory;

  /// اسم الملف ثابت حتى ما تضيع العناصر المخزّنة من نسخ سابقة.
  final String fileName;
  final Future<Directory> Function() _directory;

  Future<File> get _file async => File('${(await _directory()).path}/$fileName');

  /// كل العناصر المخزّنة (فارغة إذا ما موجود ملف أو فارغ).
  Future<List<dynamic>> readAll() async {
    final file = await _file;
    if (!file.existsSync()) return [];
    final content = await file.readAsString();
    if (content.isEmpty) return [];
    return jsonDecode(content) as List<dynamic>;
  }

  /// يضيف عنصراً ويرجع عدد العناصر المخزّنة بعده.
  Future<int> append(Map<String, dynamic> item) async {
    final list = await readAll();
    list.add(item);
    await (await _file).writeAsString(jsonEncode(list));
    return list.length;
  }

  /// يستبدل المخزّن بما بقي بعد المزامنة (فارغ = حذف الملف).
  Future<void> replace(List<Map<String, dynamic>> remaining) async {
    final file = await _file;
    if (remaining.isEmpty) {
      if (file.existsSync()) await file.delete();
    } else {
      await file.writeAsString(jsonEncode(remaining));
    }
  }
}
