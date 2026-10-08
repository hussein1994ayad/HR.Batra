'use client';

// المساعد الذكي (للأدمن فقط): الحالة في features/assistant/useAssistant، والواجهة في components/AssistantChat.

import { Sparkles } from 'lucide-react';
import { PageHeader } from '@/components/ui';
import { useAssistant } from '@/features/assistant/useAssistant';
import { AssistantChat } from '@/features/assistant/components/AssistantChat';

export default function AssistantPage() {
  const a = useAssistant();
  return (
    <div className="space-y-6 pb-12" dir="rtl">
      <PageHeader icon={Sparkles} tone="violet" title="المساعد الذكي"
        description="مساعد موارد بشرية يجاوب من بيانات النظام: الدوام، الخصومات، السلف، الإجازات والوثائق، ويسوي ملفات Excel. تكدر تسأل بالكتابة أو بالصوت" />
      <AssistantChat messages={a.messages} thinking={a.thinking} onSend={a.send} onVoice={a.sendVoice} onReset={a.reset} />
    </div>
  );
}
