// =========================================================================
// المساعد الذكي للأدمن — الرسائل والرد (Edge Function: supabase/functions/hr-assistant)
// =========================================================================

import '../utils/json_map.dart';

/// رسالة بالمحادثة. المرفقات (ملفات/وثائق) تبقى بالشاشة وما ترجع للسيرفر.
class AssistantMessage {
  const AssistantMessage.user(this.text) : fromUser = true, files = const [], documents = const [], isError = false;
  const AssistantMessage.assistant(this.text, {this.files = const [], this.documents = const []}) : fromUser = false, isError = false;
  const AssistantMessage.error(this.text) : fromUser = false, files = const [], documents = const [], isError = true;

  final bool fromUser;
  final String text;
  final List<AssistantFile> files;
  final List<AssistantDocuments> documents;

  /// رسالة خطأ (ما تنرسل للذكاء كجزء من المحادثة).
  final bool isError;

  /// الشكل اللي يرسله التطبيق للسيرفر.
  Map<String, String> toHistory() => {'role': fromUser ? 'user' : 'assistant', 'text': text};
}

/// ملف جاهز (Excel) مبني بالسيرفر.
class AssistantFile {
  const AssistantFile({required this.name, required this.base64});
  final String name;
  final String base64;
}

/// وثائق موظف للعرض (روابط التخزين الخاصة؛ تنفتح بروابط موقّعة).
class AssistantDocuments {
  const AssistantDocuments({required this.employee, required this.urls});
  final String employee;
  final List<String> urls;
}

/// رد المساعد: نص + مرفقات.
class AssistantReply {
  const AssistantReply({required this.text, this.files = const [], this.documents = const []});

  final String text;
  final List<AssistantFile> files;
  final List<AssistantDocuments> documents;

  factory AssistantReply.fromMap(JsonRow map) {
    final files = <AssistantFile>[];
    final docs = <AssistantDocuments>[];
    for (final a in map.list('attachments')) {
      if (a.str('kind') == 'file' && a.str('name') != null && a.str('base64') != null) {
        files.add(AssistantFile(name: a.str('name')!, base64: a.str('base64')!));
      } else if (a.str('kind') == 'documents') {
        final urls = a['urls'];
        docs.add(AssistantDocuments(
          employee: a.str('employee') ?? 'موظف',
          urls: urls is List ? [for (final u in urls) if (u is String) u] : const [],
        ));
      }
    }
    return AssistantReply(text: map.str('text') ?? '', files: files, documents: docs);
  }

  AssistantMessage toMessage() => AssistantMessage.assistant(text, files: files, documents: documents);
}
