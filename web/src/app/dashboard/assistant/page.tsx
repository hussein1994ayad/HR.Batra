'use client';

// المساعد الذكي (للأدمن فقط): الحالة في features/assistant/useAssistant، والواجهة في components/AssistantChat
// و components/AssistantHistory (المحادثات السابقة + الملخص الصباحي).

import { Sparkles } from 'lucide-react';
import toast from 'react-hot-toast';
import { PageHeader } from '@/components/ui';
import { useAssistant } from '@/features/assistant/useAssistant';
import { AssistantChat } from '@/features/assistant/components/AssistantChat';
import { AssistantToolbar } from '@/features/assistant/components/AssistantHistory';

export default function AssistantPage() {
  const a = useAssistant();
  const open = (id: string) => a.open(id).catch(() => toast.error('ما انفتحت المحادثة. تأكد من الإنترنت.'));
  return (
    <div className="space-y-6 pb-12" dir="rtl">
      <PageHeader icon={Sparkles} tone="violet" title="المساعد الذكي"
        description="مساعد موارد بشرية يجاوب من بيانات النظام: الدوام، الخصومات، السلف، الإجازات والوثائق، ويسوي ملفات Excel ومسودات تعاميم. تكدر تسأل بالكتابة أو بالصوت" />
      <AssistantToolbar currentId={a.conversationId} busy={a.thinking} onOpen={open} />
      <AssistantChat messages={a.messages} thinking={a.thinking} onSend={a.send} onVoice={a.sendVoice} onReset={a.reset} />
    </div>
  );
}
