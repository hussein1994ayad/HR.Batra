// تحويل رابط خرائط جوجل (بما فيه الروابط المختصرة maps.app.goo.gl) إلى إحداثيات.
// الروابط المختصرة تحتاج فتح الصفحة، والمتصفح يمنع ذلك مباشرة (CORS)، فتُجرب بروكسيات عامة بالترتيب.
// ملاحظة: البروكسي طرف ثالث يرى الرابط الملصوق؛ لصق "lat, lng" مباشرة لا يرسل أي شيء.

import { extractCoordsFromHtml, extractCoordsFromText, type LatLng } from './logic';

type Proxy = (url: string) => Promise<{ url: string; body: string }>;

const PROXIES: Proxy[] = [
  async (u) => {
    const res = await fetch(`https://api.allorigins.win/get?url=${encodeURIComponent(u)}`);
    if (!res.ok) throw new Error('AllOrigins fail');
    const data = (await res.json()) as { status?: { url?: string }; contents?: string };
    return { url: data.status?.url || '', body: data.contents || '' };
  },
  async (u) => {
    const res = await fetch(`https://api.codetabs.com/v1/proxy?quest=${encodeURIComponent(u)}`);
    if (!res.ok) throw new Error('Codetabs fail');
    return { url: '', body: await res.text() };
  },
  async (u) => {
    const res = await fetch(`https://thingproxy.freeboard.io/fetch/${encodeURIComponent(u)}`);
    if (!res.ok) throw new Error('ThingProxy fail');
    return { url: '', body: await res.text() };
  },
];

export async function resolveMapUrl(input: string): Promise<LatLng | null> {
  const trimmed = input.trim();
  const local = extractCoordsFromText(trimmed);
  if (local) return local;
  if (!trimmed.startsWith('http') && !trimmed.includes('maps') && !trimmed.includes('goo.gl')) return null;

  for (const [i, proxy] of PROXIES.entries()) {
    try {
      const { url, body } = await proxy(trimmed);
      const coords = (url && extractCoordsFromText(url)) || (body && extractCoordsFromHtml(body));
      if (coords) return coords;
    } catch (err) {
      console.warn(`Proxy ${i + 1} bypass warn:`, err);
    }
  }
  return null;
}
