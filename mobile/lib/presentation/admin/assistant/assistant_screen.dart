// =========================================================================
// HR Pro — المساعد الذكي (للأدمن فقط)
// الذكاء والأدوات وملفات Excel كلها بالسيرفر (supabase/functions/hr-assistant)؛ الشاشة ترسل المحادثة وتعرض الرد.
// المحادثة بالذاكرة بس (ما تنحفظ)، وتنمسح لما تطلع من الشاشة.
// السؤال بالصوت: تسجيل ← السيرفر يكتبه بالعراقي (يرجع نصه كرسالة الأدمن) ويجاوب. التسجيل ما ينحفظ.
// =========================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart' show openAppSettings;

import '../../../core/models/models.dart';
import '../../../core/services/auth_service.dart';
import '../../../data/repositories/admin_actions_repository.dart';
import '../../../data/repositories/assistant_repository.dart';
import '../../shared/ui/ui.dart';
import 'assistant_voice.dart';
import 'widgets/assistant_widgets.dart';

class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key, this.repository, this.decide, this.recorder});

  /// للاختبار؛ الافتراضي يتصل بالسيرفر.
  final AssistantRepository? repository;

  /// تنفيذ بطاقات اقتراح القرارات (الافتراضي: decide_payroll_event عبر AdminActionsRepository).
  final AssistantDecide? decide;

  /// للاختبار؛ الافتراضي يسجّل من المايك.
  final AssistantRecorder? recorder;

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  late final AssistantRepository _repo = widget.repository ?? AssistantRepository();
  // الريبو ينبني بس لما الأدمن يأكد قرار (مو مع فتح الشاشة)
  late final AssistantDecide _decide = widget.decide ??
      (id, {required deduct, required reason}) => AdminActionsRepository().decidePayrollEvent(id, deduct: deduct, reason: reason);
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<AssistantMessage> _messages = [];
  bool _thinking = false;

  // التسجيل الصوتي (المسجّل ينبني أول ما يضغط المايك)
  AssistantRecorder? _recorder;
  bool _recording = false;
  Duration _elapsed = Duration.zero;
  Timer? _ticker;

  bool get _busy => _thinking || _recording;

  @override
  void dispose() {
    _ticker?.cancel();
    if (_recording) _recorder?.cancel();
    _recorder?.dispose();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || _busy) return;
    _input.clear();
    setState(() => _messages.add(AssistantMessage.user(text)));
    await _ask();
  }

  /// يسأل السيرفر. مع [audio]: السؤال هو التسجيل، ونصه (شنو انفهم) ينضاف كرسالة الأدمن قبل الجواب.
  Future<void> _ask({AssistantAudio? audio}) async {
    setState(() => _thinking = true);
    _scrollToEnd();
    final added = <AssistantMessage>[];
    try {
      final reply = await _repo.ask(List.of(_messages), audio: audio);
      final heard = reply.transcript?.trim() ?? '';
      if (audio != null && heard.isNotEmpty) added.add(AssistantMessage.user(heard, voice: true));
      added.add(reply.toMessage());
    } on AssistantException catch (e) {
      added.add(AssistantMessage.error(e.message));
    } catch (_) {
      added.add(const AssistantMessage.error('صار خطأ. جرّب مرة ثانية.'));
    }
    if (!mounted) return;
    setState(() {
      _messages.addAll(added);
      _thinking = false;
    });
    _scrollToEnd();
  }

  Future<void> _startRecording() async {
    if (_busy) return;
    final rec = _recorder ??= widget.recorder ?? RecordAssistantRecorder();
    try {
      if (!await rec.requestPermission()) {
        if (mounted) {
          AppSnack.show(context, 'المايك مسكَّر للتطبيق. افتح الإعدادات وفعّل المايكروفون حتى تسأل بالصوت.',
              tone: AppTone.warning, actionLabel: 'الإعدادات', onAction: openAppSettings);
        }
        return;
      }
      await rec.start();
    } catch (_) {
      if (mounted) AppSnack.show(context, 'ما اشتغل المايك. جرّب مرة ثانية.', tone: AppTone.danger);
      return;
    }
    if (!mounted) return;
    setState(() {
      _recording = true;
      _elapsed = Duration.zero;
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed += const Duration(seconds: 1));
      if (_elapsed >= kAssistantMaxRecording) _finishRecording();
    });
  }

  Future<void> _cancelRecording() async {
    _ticker?.cancel();
    setState(() => _recording = false);
    await _recorder?.cancel();
  }

  Future<void> _finishRecording() async {
    if (!_recording) return;
    _ticker?.cancel();
    final tooShort = _elapsed < const Duration(seconds: 1);
    setState(() => _recording = false);
    final bytes = await _recorder?.stop();
    if (!mounted) return;
    if (bytes == null || bytes.isEmpty || tooShort) {
      AppSnack.show(context, 'التسجيل قصير. اضغط المايك واحچي سؤالك، وبعدين اضغط إرسال.', tone: AppTone.warning);
      return;
    }
    await _ask(audio: AssistantAudio(bytes: bytes));
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent, duration: AppMotion.fast, curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!Roles.isAdmin(AuthService.currentUserRole)) {
      return Scaffold(
        appBar: AppBar(title: const Text('المساعد الذكي')),
        body: const EmptyView(title: 'للأدمن فقط', message: 'المساعد الذكي متاح لمسؤول النظام فقط.', icon: Icons.lock_rounded),
      );
    }
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('المساعد الذكي'),
        actions: [
          if (_messages.isNotEmpty)
            IconButton(
              tooltip: 'محادثة جديدة',
              icon: const Icon(Icons.add_comment_outlined),
              onPressed: _busy ? null : () => setState(_messages.clear),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              controller: _scroll,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.all(AppSpace.page),
              children: [
                if (_messages.isEmpty) AssistantWelcome(onPick: _send),
                for (final m in _messages) AssistantBubble(message: m, decide: _decide),
                if (_thinking)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpace.md),
                    child: Row(children: [
                      SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: AppSpace.sm),
                      Text('يجهّز الجواب…', style: AppText.bodySm),
                    ]),
                  ),
              ],
            ),
          ),
          if (_recording)
            _RecordingBar(elapsed: _elapsed, onCancel: _cancelRecording, onSend: _finishRecording)
          else
            _Composer(controller: _input, busy: _thinking, onSend: _send, onMic: _startRecording),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({required this.controller, required this.busy, required this.onSend, required this.onMic});
  final TextEditingController controller;
  final bool busy;
  final VoidCallback onSend;
  final VoidCallback onMic;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface1,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.page, AppSpace.sm, AppSpace.page, AppSpace.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => onSend(),
                      decoration: const InputDecoration(hintText: 'اسأل عن موظف، دوام، خصومات، سلف…'),
                    ),
                  ),
                  const SizedBox(width: AppSpace.xs),
                  IconButton.filledTonal(
                    tooltip: 'اسأل بالصوت',
                    onPressed: busy ? null : onMic,
                    icon: const Icon(Icons.mic_rounded),
                  ),
                  const SizedBox(width: AppSpace.xs),
                  IconButton.filled(
                    tooltip: 'إرسال',
                    onPressed: busy ? null : onSend,
                    icon: const Icon(Icons.send_rounded),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.xs),
              const Text('يعمل بـ Gemini من Google · للقراءة فقط، ما يعدّل أي شي', style: AppText.caption),
            ],
          ),
        ),
      ),
    );
  }
}

/// شريط أثناء التسجيل: الوقت، إلغاء، وإرسال (يوقف ويرسل تلقائياً عند دقيقة).
class _RecordingBar extends StatelessWidget {
  const _RecordingBar({required this.elapsed, required this.onCancel, required this.onSend});
  final Duration elapsed;
  final VoidCallback onCancel;
  final VoidCallback onSend;

  static String _mmss(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final left = kAssistantMaxRecording - elapsed;
    return Material(
      color: AppColors.surface1,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.page, AppSpace.sm, AppSpace.page, AppSpace.sm),
          child: Row(
            children: [
              IconButton(tooltip: 'إلغاء التسجيل', onPressed: onCancel, icon: const Icon(Icons.delete_outline_rounded)),
              Icon(Icons.fiber_manual_record_rounded, color: AppTone.danger.color, size: 14),
              const SizedBox(width: AppSpace.xs),
              Expanded(
                child: Text(
                  'يسمعك… احچي سؤالك  ${_mmss(elapsed)}  (باقي ${_mmss(left.isNegative ? Duration.zero : left)})',
                  style: AppText.bodySm.copyWith(color: AppColors.textPrimary),
                ),
              ),
              IconButton.filled(tooltip: 'إرسال التسجيل', onPressed: onSend, icon: const Icon(Icons.send_rounded)),
            ],
          ),
        ),
      ),
    );
  }
}
