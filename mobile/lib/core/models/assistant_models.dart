// =========================================================================
// المساعد الذكي للأدمن — الرسائل والرد (Edge Function: supabase/functions/hr-assistant)
// =========================================================================

import '../utils/json_map.dart';

/// رسالة بالمحادثة. المرفقات (ملفات/وثائق) تبقى بالشاشة وما ترجع للسيرفر.
class AssistantMessage {
  const AssistantMessage.user(this.text, {this.voice = false})
      : fromUser = true, files = const [], documents = const [], decisions = const [], isError = false;
  const AssistantMessage.assistant(this.text, {this.files = const [], this.documents = const [], this.decisions = const []})
      : fromUser = false, isError = false, voice = false;
  const AssistantMessage.error(this.text) : fromUser = false, files = const [], documents = const [], decisions = const [], isError = true, voice = false;

  final bool fromUser;
  final String text;
  final List<AssistantFile> files;
  final List<AssistantDocuments> documents;

  /// اقتراحات قرارات (ما تنفذ إلا بتأكيد الأدمن).
  final List<AssistantDecision> decisions;

  /// رسالة خطأ (ما تنرسل للذكاء كجزء من المحادثة).
  final bool isError;

  /// سؤال بالصوت (النص هو اللي فهمه المساعد من التسجيل).
  final bool voice;

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

/// اقتراح قرار على حركة معلّقة. البيانات من القاعدة؛ الاقتراح والسبب من الذكاء. التنفيذ بزر «تأكيد».
class AssistantDecision {
  const AssistantDecision({
    required this.eventId,
    required this.employee,
    required this.date,
    required this.type,
    required this.minutes,
    required this.amount,
    required this.suggestDeduct,
    required this.reason,
  });

  final String eventId;
  final String employee;
  final String date;

  /// absence | late | early_leave | missing_punch
  final String type;
  final double minutes;
  final double amount;
  final bool suggestDeduct;
  final String reason;

  static AssistantDecision? fromMap(JsonRow m) {
    final id = m.str('event_id');
    if (id == null) return null;
    return AssistantDecision(
      eventId: id,
      employee: m.str('employee') ?? 'موظف',
      date: m.str('date') ?? '',
      type: m.str('type') ?? '',
      minutes: m.dbl('minutes') ?? 0,
      amount: m.dbl('amount') ?? 0,
      suggestDeduct: m.str('suggest') == 'deduct',
      reason: m.str('reason') ?? '',
    );
  }
}

/// تسجيل صوتي (WAV) للسؤال بالصوت. ما ينحفظ بأي مكان.
class AssistantAudio {
  const AssistantAudio({required this.bytes, this.mime = 'audio/wav'});
  final List<int> bytes;
  final String mime;
}

/// رد المساعد: نص + مرفقات.
class AssistantReply {
  const AssistantReply({required this.text, this.transcript, this.files = const [], this.documents = const [], this.decisions = const []});

  final String text;

  /// لسؤال بالصوت: شنو انفهم من التسجيل (يظهر كرسالة الأدمن).
  final String? transcript;
  final List<AssistantFile> files;
  final List<AssistantDocuments> documents;
  final List<AssistantDecision> decisions;

  factory AssistantReply.fromMap(JsonRow map) {
    final files = <AssistantFile>[];
    final docs = <AssistantDocuments>[];
    final decisions = <AssistantDecision>[];
    for (final a in map.list('attachments')) {
      if (a.str('kind') == 'file' && a.str('name') != null && a.str('base64') != null) {
        files.add(AssistantFile(name: a.str('name')!, base64: a.str('base64')!));
      } else if (a.str('kind') == 'decision') {
        final d = AssistantDecision.fromMap(a);
        if (d != null) decisions.add(d);
      } else if (a.str('kind') == 'documents') {
        final urls = a['urls'];
        docs.add(AssistantDocuments(
          employee: a.str('employee') ?? 'موظف',
          urls: urls is List ? [for (final u in urls) if (u is String) u] : const [],
        ));
      }
    }
    return AssistantReply(text: map.str('text') ?? '', transcript: map.str('transcript'), files: files, documents: docs, decisions: decisions);
  }

  AssistantMessage toMessage() => AssistantMessage.assistant(text, files: files, documents: documents, decisions: decisions);
}
