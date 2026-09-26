// روابط الملفات الخاصة (مستندات الموظفين، تعهدات السلف، مرفقات الإجازات).
// الحاويات خاصة، فالرابط المحفوظ (/object/public/...) لا يفتح. نحوّله لرابط
// موقّع مؤقت، والسيرفر يتحقق أن الطالب أدمن أو صاحب الملف.

'use client';

import { useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';

export const PRIVATE_BUCKETS = new Set(['employee-documents', 'loan-pledges', 'documents']);
const PATTERN = /\/storage\/v1\/object\/(?:public|sign|authenticated)\/([^/]+)\/([^?]+)/;

export function parseStorageUrl(url: string): { bucket: string; path: string } | null {
  const m = PATTERN.exec(url);
  if (!m || !PRIVATE_BUCKETS.has(m[1])) return null;
  return { bucket: m[1], path: decodeURIComponent(m[2]) };
}

const cache = new Map<string, { url: string; expires: number }>();

/** رابط قابل للفتح الآن (ساعة افتراضياً). الروابط العامة ترجع كما هي. */
export async function resolveStorageUrl(url: string, seconds = 3600): Promise<string> {
  const ref = parseStorageUrl(url);
  if (!ref) return url;
  const key = `${seconds}|${url}`;
  const hit = cache.get(key);
  if (hit && hit.expires > Date.now()) return hit.url;

  const { data, error } = await supabase.storage.from(ref.bucket).createSignedUrl(ref.path, seconds);
  if (error || !data) throw error ?? new Error('تعذر إنشاء رابط الملف');
  cache.set(key, { url: data.signedUrl, expires: Date.now() + (seconds - 300) * 1000 });
  return data.signedUrl;
}

/** يفتح الملف في تبويب جديد. التبويب يُفتح فوراً (قبل الانتظار) حتى لا يمنعه المتصفح. */
export async function openStorageUrl(url: string) {
  // بدون 'noopener' هنا لأنه يجعل window.open يرجع null؛ نقطع opener يدوياً
  const tab = window.open('', '_blank');
  if (tab) tab.opener = null;
  try {
    const signed = await resolveStorageUrl(url);
    if (tab) tab.location.href = signed;
    else window.open(signed, '_blank', 'noopener');
  } catch (e) {
    tab?.close();
    throw e;
  }
}

/** رابط موقّع لعرضه في <img>/<iframe>؛ null أثناء التحميل. */
export function useSignedUrl(url: string | null | undefined): string | null {
  const [signed, setSigned] = useState<{ src: string; url: string } | null>(null);
  useEffect(() => {
    if (!url) return;
    let alive = true;
    resolveStorageUrl(url)
      .then((s) => alive && setSigned({ src: url, url: s }))
      .catch(() => alive && setSigned({ src: url, url }));
    return () => {
      alive = false;
    };
  }, [url]);
  if (!url) return null;
  if (!parseStorageUrl(url)) return url;
  return signed?.src === url ? signed.url : null;
}
