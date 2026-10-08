// =========================================================================
// المساعد الذكي للأدمن: طلب واحد للـ Edge Function `hr-assistant` (الذكاء والأدوات والإكسل كلها بالسيرفر،
// فالتطبيق يبقى خفيف). السيرفر يتحقق إن المستخدم أدمن.
// =========================================================================

import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/models/assistant_models.dart';
import '../../core/services/supabase_service.dart';
import '../../core/utils/json_map.dart';

class AssistantRepository {
  AssistantRepository({SupabaseClient? client}) : _db = client ?? SupabaseService.client;
  final SupabaseClient _db;

  /// آخر 10 رسائل نصية تكفي للسياق (نفس حد السيرفر).
  static const maxHistory = 10;

  /// يرسل المحادثة ويرجع الرد. مع [audio]: السيرفر يكتب التسجيل نص (يرجع بـ transcript) ويجاوب عليه.
  /// يرمي [AssistantException] برسالة عربية مفهومة.
  Future<AssistantReply> ask(List<AssistantMessage> conversation, {AssistantAudio? audio}) async {
    try {
      final res = await _db.functions.invoke('hr-assistant', body: {
        'messages': historyFor(conversation),
        if (audio != null) 'audio': {'mime': audio.mime, 'base64': base64Encode(audio.bytes)},
      });
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

  // ---------------- المحادثات المحفوظة (نص فقط، تنحذف بعد 90 يوم) ----------------

  /// يحفظ رسائل جديدة؛ بدون [conversationId] تنفتح محادثة جديدة. يرجع رقم المحادثة.
  Future<String> saveMessages(String? conversationId, List<AssistantMessage> messages) async {
    final saved = [for (final m in messages) if (!m.isError && m.text.trim().isNotEmpty) m.toSaved()];
    if (saved.isEmpty && conversationId != null) return conversationId;
    final id = await _db.rpc<Object?>('assistant_save_messages', params: {'p_conversation_id': conversationId, 'p_messages': saved});
    return id as String;
  }

  Future<List<AssistantConversation>> conversations() async {
    final rows = await _db.from('assistant_conversations').select('id, title, updated_at').order('updated_at', ascending: false).limit(50);
    return [for (final r in rowsOf(rows)) ?AssistantConversation.fromMap(r)];
  }

  Future<List<AssistantMessage>> messagesOf(String conversationId) async {
    final rows = await _db.from('assistant_messages').select('role, text, voice').eq('conversation_id', conversationId).order('id');
    return [for (final r in rowsOf(rows)) AssistantMessage.fromSaved(r)];
  }

  Future<void> deleteConversation(String conversationId) => _db.from('assistant_conversations').delete().eq('id', conversationId);

  // ---------------- الملخص الصباحي (إشعار 10:00) ----------------

  Future<bool> morningSummaryEnabled() async => rowOf(await _db.rpc('assistant_settings'))?['morning_summary'] != false;

  Future<void> setMorningSummary(bool enabled) => _db.rpc('assistant_set_morning_summary', params: {'p_enabled': enabled});

  static String? _serverMessage(Object? details) => rowOf(details)?.str('error');
}

class AssistantException implements Exception {
  const AssistantException(this.message);
  final String message;
  @override
  String toString() => message;
}
