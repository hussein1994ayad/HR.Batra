// المساعد الذكي: قراءة الرد، تنظيف النص، والشاشة (أدمن فقط، رسالة ← رد + ملف + وثائق، والخطأ).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hr_pro/core/models/models.dart';
import 'package:hr_pro/core/services/auth_service.dart';
import 'package:hr_pro/core/theme/app_theme.dart';
import 'package:hr_pro/data/repositories/assistant_repository.dart';
import 'package:hr_pro/presentation/admin/assistant/assistant_logic.dart';
import 'package:hr_pro/presentation/admin/assistant/assistant_screen.dart';

class _FakeRepo implements AssistantRepository {
  _FakeRepo(this.answer);
  final Future<AssistantReply> Function(List<AssistantMessage>) answer;
  final sent = <List<Map<String, String>>>[];

  @override
  Future<AssistantReply> ask(List<AssistantMessage> conversation) {
    sent.add([for (final m in conversation) m.toHistory()]);
    return answer(conversation);
  }
}

Widget _host(AssistantRepository repo) =>
    MaterialApp(theme: AppTheme.darkTheme, home: AssistantScreen(repository: repo));

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
}
