// تسليم مسودة تعميم من المساعد إلى نافذة «بث تعميم» بالرئيسية (sessionStorage لنفس التبويب فقط).
// النشر يبقى بيد الأدمن من النافذة؛ المسودة تنمسح بعد ما تنسد النافذة.

const KEY = 'assistant_announcement_draft';

export interface AnnouncementDraft {
  title: string;
  body: string;
}

export function stashAnnouncementDraft(d: AnnouncementDraft) {
  try {
    sessionStorage.setItem(KEY, JSON.stringify({ title: d.title, body: d.body }));
  } catch {
    /* التخزين مقفول: الأدمن يكدر ينسخ المسودة يدوياً */
  }
}

export function peekAnnouncementDraft(): AnnouncementDraft | null {
  try {
    const v = JSON.parse(sessionStorage.getItem(KEY) ?? 'null');
    return v && typeof v.body === 'string' ? { title: String(v.title ?? ''), body: v.body } : null;
  } catch {
    return null;
  }
}

export function clearAnnouncementDraft() {
  try {
    sessionStorage.removeItem(KEY);
  } catch {
    /* لا شيء */
  }
}
