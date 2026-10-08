// =========================================================================
// HR Pro — المساعد الذكي (للأدمن فقط)
// الذكاء والأدوات وملفات Excel كلها بالسيرفر (supabase/functions/hr-assistant)؛ الشاشة ترسل المحادثة وتعرض الرد.
// المحادثة بالذاكرة بس (ما تنحفظ)، وتنمسح لما تطلع من الشاشة.
// =========================================================================

import 'package:flutter/material.dart';

import '../../../core/models/models.dart';
import '../../../core/services/auth_service.dart';
import '../../../data/repositories/assistant_repository.dart';
import '../../shared/ui/ui.dart';
import 'widgets/assistant_widgets.dart';

class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key, this.repository});

  /// للاختبار؛ الافتراضي يتصل بالسيرفر.
  final AssistantRepository? repository;

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  late final AssistantRepository _repo = widget.repository ?? AssistantRepository();
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<AssistantMessage> _messages = [];
  bool _thinking = false;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || _thinking) return;
    _input.clear();
    setState(() {
      _messages.add(AssistantMessage.user(text));
      _thinking = true;
    });
    _scrollToEnd();
    AssistantMessage reply;
    try {
      reply = (await _repo.ask(_messages)).toMessage();
    } on AssistantException catch (e) {
      reply = AssistantMessage.error(e.message);
    } catch (_) {
      reply = const AssistantMessage.error('صار خطأ. جرّب مرة ثانية.');
    }
    if (!mounted) return;
    setState(() {
      _messages.add(reply);
      _thinking = false;
    });
    _scrollToEnd();
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
              onPressed: _thinking ? null : () => setState(_messages.clear),
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
                for (final m in _messages) AssistantBubble(message: m),
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
          _Composer(controller: _input, busy: _thinking, onSend: _send),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({required this.controller, required this.busy, required this.onSend});
  final TextEditingController controller;
  final bool busy;
  final VoidCallback onSend;

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
                  const SizedBox(width: AppSpace.sm),
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
