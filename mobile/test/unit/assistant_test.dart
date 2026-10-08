// المساعد الذكي: قراءة الرد، تنظيف النص، والشاشة (أدمن فقط، رسالة ← رد + ملف + وثائق، والخطأ).

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hr_pro/core/models/models.dart';
import 'package:hr_pro/core/services/auth_service.dart';
import 'package:hr_pro/core/theme/app_theme.dart';
import 'package:hr_pro/data/repositories/assistant_repository.dart';
import 'package:hr_pro/presentation/admin/assistant/assistant_logic.dart';
import 'package:hr_pro/presentation/admin/assistant/assistant_screen.dart';
import 'package:hr_pro/presentation/admin/assistant/assistant_voice.dart';

class _FakeRepo implements AssistantRepository {
  _FakeRepo(this.answer);
  final Future<AssistantReply> Function(List<AssistantMessage>) answer;
  final sent = <List<Map<String, String>>>[];
  final audios = <AssistantAudio?>[];

  @override
  Future<AssistantReply> ask(List<AssistantMessage> conversation, {AssistantAudio? audio}) {
    sent.add([for (final m in conversation) m.toHistory()]);
    audios.add(audio);
    return answer(conversation);
  }

  // المحادثات المحفوظة والإعدادات (بالذاكرة)
  final saves = <(String?, List<Map<String, Object>>)>[];
  final stored = <String, List<AssistantMessage>>{};
  bool summary = true;

  @override
  Future<String> saveMessages(String? conversationId, List<AssistantMessage> messages) async {
    saves.add((conversationId, [for (final m in messages) m.toSaved()]));
    final id = conversationId ?? 'c${stored.length + 1}';
    (stored[id] ??= []).addAll(messages);
    return id;
  }

  @override
  Future<List<AssistantConversation>> conversations() async =>
      [for (final e in stored.entries) AssistantConversation(id: e.key, title: e.value.first.text, updatedAt: DateTime(2026, 10, 8))];

  @override
  Future<List<AssistantMessage>> messagesOf(String conversationId) async => stored[conversationId] ?? const [];

  @override
  Future<void> deleteConversation(String conversationId) async => stored.remove(conversationId);

  @override
  Future<bool> morningSummaryEnabled() async => summary;

  @override
  Future<void> setMorningSummary(bool enabled) async => summary = enabled;
}

Widget _host(AssistantRepository repo, {AssistantRecorder? recorder}) =>
    MaterialApp(theme: AppTheme.darkTheme, home: AssistantScreen(repository: repo, recorder: recorder));

class _FakeRecorder implements AssistantRecorder {
  _FakeRecorder({this.allowed = true});
  final bool allowed;
  int started = 0, cancelled = 0;

  @override
  Future<bool> requestPermission() async => allowed;
  @override
  Future<void> start() async => started++;
  @override
  Future<Uint8List?> stop() async => Uint8List.fromList([82, 73, 70, 70]);
  @override
  Future<void> cancel() async => cancelled++;
  @override
  void dispose() {}
}

void main() {
  test('reply: text, Excel file and documents', () {
    final r = AssistantReply.fromMap({
      'text': 'تفضل',
      'attachments': [
        {'kind': 'file', 'name': 'سجل_دوام.xlsx', 'mime': 'x', 'base64': 'UEs='},
        {'kind': 'documents', 'employee': 'علي', 'urls': ['u1', 'u2', 3]},
        {'kind': 'unknown'},
      ],
    });
    expect(r.text, 'تفضل');
    expect(r.files.single.name, 'سجل_دوام.xlsx');
    expect(r.documents.single.urls, ['u1', 'u2']);
  });

  test('history sent to the server: last 10 text messages, errors dropped', () {
    final conv = [
      for (var i = 0; i < 12; i++) i.isEven ? AssistantMessage.user('س$i') : AssistantMessage.assistant('ج$i'),
      const AssistantMessage.error('خطأ'),
      const AssistantMessage.user('  '),
    ];
    final h = AssistantRepository.historyFor(conv);
    expect(h.length, 10);
    expect(h.first, {'role': 'user', 'text': 'س2'});
    expect(h.any((m) => m['text'] == 'خطأ'), isFalse);
  });

  test('assistant text: markdown symbols removed, bullets kept readable', () {
    expect(assistantDisplayText('## الملخص\n**الغياب:** 2 يوم\n* تأخير 30 دقيقة\n- خصم 1,250 د.ع\n\n\n\nانتهى'),
        'الملخص\nالغياب: 2 يوم\n• تأخير 30 دقيقة\n• خصم 1,250 د.ع\n\nانتهى');
  });

  testWidgets('not an admin: the assistant is locked', (tester) async {
    AuthService.currentUserRole = 'manager';
    await tester.pumpWidget(_host(_FakeRepo((_) async => const AssistantReply(text: 'x'))));
    expect(find.text('للأدمن فقط'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('admin: a suggestion sends, the reply shows with its file and documents', (tester) async {
    AuthService.currentUserRole = 'admin';
    final repo = _FakeRepo((_) async => const AssistantReply(
          text: '**تم:** سويتلك الملف',
          files: [AssistantFile(name: 'سجل_دوام_علي.xlsx', base64: 'UEs=')],
          documents: [AssistantDocuments(employee: 'علي', urls: ['u1'])],
        ));
    await tester.pumpWidget(_host(repo));
    await tester.tap(find.text('منو غايب ومنو متأخر اليوم بكل فرع؟'));
    await tester.pumpAndSettle();

    expect(repo.sent.single.single, {'role': 'user', 'text': 'منو غايب ومنو متأخر اليوم بكل فرع؟'});
    expect(find.text('تم: سويتلك الملف'), findsOneWidget);
    expect(find.text('سجل_دوام_علي.xlsx'), findsOneWidget);
    expect(find.text('وثيقة 1 — علي'), findsOneWidget);
  });

  testWidgets('decision card: nothing runs until confirmed; confirm runs it once with the reason', (tester) async {
    AuthService.currentUserRole = 'admin';
    final decided = <(String, bool, String)>[];
    final repo = _FakeRepo((_) async => const AssistantReply(
          text: 'جهزتلك البطاقات، أكدها انت',
          decisions: [
            AssistantDecision(eventId: 'ev1', employee: 'علي', date: '2026-10-01', type: 'late', minutes: 25, amount: 1042,
                suggestDeduct: false, reason: 'أول تأخير بالشهر'),
          ],
        ));
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.darkTheme,
      home: AssistantScreen(
        repository: repo,
        decide: (id, {required deduct, required reason}) async => decided.add((id, deduct, reason)),
      ),
    ));
    await tester.tap(find.text('شنو القرارات المعلّقة اللي تنتظرني؟'));
    await tester.pumpAndSettle();

    expect(find.textContaining('علي · تأخير · 2026-10-01'), findsOneWidget);
    expect(find.text('الاقتراح: إعفاء — أول تأخير بالشهر'), findsOneWidget);
    expect(decided, isEmpty); // الاقتراح وحده ما ينفذ شي

    await tester.tap(find.text('تأكيد إعفاء'));
    await tester.pumpAndSettle();
    expect(decided, [('ev1', false, 'أول تأخير بالشهر')]);
    expect(find.text('✓ تم الإعفاء'), findsOneWidget);
    expect(find.text('تأكيد إعفاء'), findsNothing); // ما ينضغط مرتين
  });

  test('reply parses decision cards', () {
    final r = AssistantReply.fromMap({
      'text': 'x',
      'attachments': [
        {'kind': 'decision', 'event_id': 'e9', 'employee': 'باسم', 'date': '2026-10-02', 'type': 'absence', 'minutes': 0,
          'amount': 20000, 'suggest': 'deduct', 'reason': 'متكرر'},
      ],
    });
    expect(r.decisions.single.suggestDeduct, isTrue);
    expect(r.decisions.single.amount, 20000);
  });

  testWidgets('admin: a server error shows as a message and is not sent back as history', (tester) async {
    AuthService.currentUserRole = 'admin';
    var calls = 0;
    final repo = _FakeRepo((_) async {
      calls++;
      if (calls == 1) throw const AssistantException('خلص الحد المجاني للمساعد هسه.');
      return const AssistantReply(text: 'تمام');
    });
    await tester.pumpWidget(_host(repo));
    await tester.enterText(find.byType(TextField), 'سؤال أول');
    await tester.tap(find.byTooltip('إرسال'));
    await tester.pumpAndSettle();
    expect(find.text('خلص الحد المجاني للمساعد هسه.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'سؤال ثاني');
    await tester.tap(find.byTooltip('إرسال'));
    await tester.pumpAndSettle();
    expect(find.text('تمام'), findsOneWidget);
    // الرسالة الأخيرة المرسلة: السؤالين بدون رسالة الخطأ (الريبو يصفّي الأخطاء؛ هنا نتأكد إن الشاشة ترسل المحادثة كاملة)
    expect(repo.sent.last.where((m) => m['role'] == 'user').map((m) => m['text']), ['سؤال أول', 'سؤال ثاني']);
  });

  testWidgets('voice: record, send, the transcript shows as the admin message, then the answer', (tester) async {
    AuthService.currentUserRole = 'admin';
    final rec = _FakeRecorder();
    final repo = _FakeRepo((_) async => const AssistantReply(text: 'علي تأخر 3 مرات', transcript: 'شكد تأخر علي هالشهر؟'));
    await tester.pumpWidget(_host(repo, recorder: rec));
    await tester.tap(find.byTooltip('اسأل بالصوت'));
    await tester.pump();
    expect(rec.started, 1);
    expect(find.textContaining('يسمعك'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.tap(find.byTooltip('إرسال التسجيل'));
    await tester.pumpAndSettle();
    expect(repo.audios.single?.bytes, [82, 73, 70, 70]);
    expect(repo.audios.single?.mime, 'audio/wav');
    expect(find.text('شكد تأخر علي هالشهر؟'), findsOneWidget);
    expect(find.text('سؤال بالصوت · هذا اللي انفهم'), findsOneWidget);
    expect(find.text('علي تأخر 3 مرات'), findsOneWidget);
  });

  testWidgets('voice: mic denied shows a settings hint and records nothing', (tester) async {
    AuthService.currentUserRole = 'admin';
    final denied = _FakeRecorder(allowed: false);
    final repo = _FakeRepo((_) async => const AssistantReply(text: 'x'));
    await tester.pumpWidget(_host(repo, recorder: denied));
    await tester.tap(find.byTooltip('اسأل بالصوت'));
    await tester.pump();
    expect(denied.started, 0);
    expect(find.textContaining('فعّل المايكروفون'), findsOneWidget);
    expect(repo.sent, isEmpty);
  });

  testWidgets('voice: cancelling a recording sends nothing', (tester) async {
    AuthService.currentUserRole = 'admin';
    final rec = _FakeRecorder();
    final repo = _FakeRepo((_) async => const AssistantReply(text: 'x'));
    await tester.pumpWidget(_host(repo, recorder: rec));
    await tester.tap(find.byTooltip('اسأل بالصوت'));
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.byTooltip('إلغاء التسجيل'));
    await tester.pumpAndSettle();
    expect(rec.cancelled, 1);
    expect(repo.sent, isEmpty);
  });

  test('reply: transcript of a voice question', () {
    expect(AssistantReply.fromMap({'text': 'x', 'transcript': 'منو غايب اليوم؟'}).transcript, 'منو غايب اليوم؟');
    expect(AssistantReply.fromMap({'text': 'x'}).transcript, isNull);
  });

  test('reply parses announcement drafts; empty drafts are dropped', () {
    final r = AssistantReply.fromMap({
      'text': 'جهزتلك المسودة',
      'attachments': [
        {'kind': 'draft', 'draft_kind': 'announcement', 'title': 'دوام العيد', 'body': 'الدوام يوم الخميس من 9 إلى 1.'},
        {'kind': 'draft', 'draft_kind': 'message', 'title': 'x', 'body': '  '},
      ],
    });
    expect(r.drafts.single.title, 'دوام العيد');
    expect(r.drafts.single.isAnnouncement, isTrue);
  });

  testWidgets('draft card shows the text with copy and open-as-announcement', (tester) async {
    AuthService.currentUserRole = 'admin';
    final repo = _FakeRepo((_) async => const AssistantReply(
          text: 'جهزتلك المسودة، راجعها وانشرها انت',
          drafts: [AssistantDraft(title: 'دوام العيد', body: 'الدوام يوم الخميس من 9 إلى 1.')],
        ));
    await tester.pumpWidget(_host(repo));
    await tester.enterText(find.byType(TextField), 'اكتبلي تعميم دوام العيد');
    await tester.tap(find.byTooltip('إرسال'));
    await tester.pumpAndSettle();
    expect(find.text('مسودة تعميم'), findsOneWidget);
    expect(find.text('الدوام يوم الخميس من 9 إلى 1.'), findsOneWidget);
    expect(find.text('نسخ'), findsOneWidget);
    expect(find.text('فتح كتعميم'), findsOneWidget);
  });

  testWidgets('each exchange is saved as text into the same conversation; history reopens it', (tester) async {
    AuthService.currentUserRole = 'admin';
    final repo = _FakeRepo((c) async => AssistantReply(text: 'جواب ${c.length}'));
    await tester.pumpWidget(_host(repo));
    await tester.enterText(find.byType(TextField), 'سؤال أول');
    await tester.tap(find.byTooltip('إرسال'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'سؤال ثاني');
    await tester.tap(find.byTooltip('إرسال'));
    await tester.pumpAndSettle();

    expect(repo.saves.length, 2);
    expect(repo.saves.first.$1, isNull); // أول مرة: محادثة جديدة
    expect(repo.saves.first.$2, [
      {'role': 'user', 'text': 'سؤال أول', 'voice': false},
      {'role': 'assistant', 'text': 'جواب 1', 'voice': false},
    ]);
    expect(repo.saves.last.$1, 'c1'); // نفس المحادثة

    await tester.tap(find.byTooltip('محادثة جديدة'));
    await tester.pumpAndSettle();
    expect(find.text('سؤال أول'), findsNothing);

    await tester.tap(find.byTooltip('المحادثات السابقة'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'سؤال أول'));
    await tester.pumpAndSettle();
    expect(find.text('سؤال أول'), findsOneWidget);
    expect(find.text('جواب 3'), findsOneWidget);
  });

  testWidgets('morning summary can be turned off from the menu', (tester) async {
    AuthService.currentUserRole = 'admin';
    final repo = _FakeRepo((_) async => const AssistantReply(text: 'x'));
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('إعدادات المساعد'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('الملخص الصباحي (10:00)'));
    await tester.pumpAndSettle();
    expect(repo.summary, isFalse);
    expect(find.text('انطفى الملخص الصباحي'), findsOneWidget);
  });
}
