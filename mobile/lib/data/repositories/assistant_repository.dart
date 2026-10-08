// =========================================================================
// المساعد الذكي للأدمن: طلب واحد للـ Edge Function `hr-assistant` (الذكاء والأدوات والإكسل كلها بالسيرفر،
// فالتطبيق يبقى خفيف). السيرفر يتحقق إن المستخدم أدمن.
// =========================================================================

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/models/assistant_models.dart';
import '../../core/services/supabase_service.dart';
import '../../core/utils/json_map.dart';

class AssistantRepository {
  AssistantRepository({SupabaseClient? client}) : _db = client ?? SupabaseService.client;
  final SupabaseClient _db;

  /// آخر 10 رسائل نصية تكفي للسياق (نفس حد السيرفر).
  static const maxHistory = 10;

  /// يرسل المحادثة ويرجع الرد. يرمي [AssistantException] برسالة عربية مفهومة.
  Future<AssistantReply> ask(List<AssistantMessage> conversation) async {
    try {
      final res = await _db.functions.invoke('hr-assistant', body: {'messages': historyFor(conversation)});
      final data = rowOf(res.data);
      if (data == null) throw const AssistantException('رد غير متوقع من المساعد.');
      return AssistantReply.fromMap(data);
    } on FunctionException catch (e) {
      throw AssistantException(_serverMessage(e.details) ?? 'تعذّر الوصول للمساعد. تأكد من الإنترنت وجرّب مرة ثانية.');
    }
  }

  /// اللي ينرسل للسيرفر: آخر [maxHistory] رسائل نصية، بدون رسائل الخطأ.
  static List<Map<String, String>> historyFor(List<AssistantMessage> conversation) {
    final history = conversation.where((m) => !m.isError && m.text.trim().isNotEmpty).toList();
    final recent = history.length > maxHistory ? history.sublist(history.length - maxHistory) : history;
    return [for (final m in recent) m.toHistory()];
  }

  static String? _serverMessage(Object? details) => rowOf(details)?.str('error');
}

class AssistantException implements Exception {
  const AssistantException(this.message);
  final String message;
  @override
  String toString() => message;
}
