export interface LatLng {
  lat: number;
  lng: number;
}

export const BAGHDAD_CENTER: [number, number] = [33.3152, 44.3661];

/** Great-circle distance in metres between two points (Haversine formula). */
export function distanceMeters(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const R = 6371e3;
  const phi1 = (lat1 * Math.PI) / 180;
  const phi2 = (lat2 * Math.PI) / 180;
  const dPhi = ((lat2 - lat1) * Math.PI) / 180;
  const dLambda = ((lon2 - lon1) * Math.PI) / 180;
  const a = Math.sin(dPhi / 2) ** 2 + Math.cos(phi1) * Math.cos(phi2) * Math.sin(dLambda / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

/**
 * Pulls a latitude/longitude pair out of a Google Maps URL or free text
 * (`@lat,lng`, `?q=lat,lng`, `/place/lat,lng`, or a bare pair inside Iraq).
 */
export function extractCoordsFromText(text: string): LatLng | null {
  if (!text) return null;
  let decoded = text;
  try {
    decoded = decodeURIComponent(text);
  } catch {
    // keep the raw text when it is not valid URI encoding
  }

  const at = decoded.match(/@(-?\d+\.\d+),(-?\d+\.\d+)/);
  if (at) return { lat: parseFloat(at[1]), lng: parseFloat(at[2]) };

  const q = decoded.match(/[?&](q|ll|query|saddr|daddr)=(-?\d+\.\d+),(-?\d+\.\d+)/);
  if (q) return { lat: parseFloat(q[2]), lng: parseFloat(q[3]) };

  const place = decoded.match(/\/place\/(-?\d+\.\d+)(?:\+|,)(-?\d+\.\d+)/);
  if (place) return { lat: parseFloat(place[1]), lng: parseFloat(place[2]) };

  // Bare "lat, lng" pair, accepted only inside Iraq's bounding box.
  const generic = /(-?\d+\.\d+)\s*,\s*(-?\d+\.\d+)/g;
  let m: RegExpExecArray | null;
  while ((m = generic.exec(decoded)) !== null) {
    const lat = parseFloat(m[1]);
    const lng = parseFloat(m[2]);
    if (lat >= 29 && lat <= 38 && lng >= 38 && lng <= 49) return { lat, lng };
  }
  return null;
}

/**
 * Resolves short Google Maps links (goo.gl / maps.app) by fetching them
 * through public CORS proxies and scanning the response for coordinates.
 */
export async function resolveMapUrl(input: string): Promise<LatLng | null> {
  const trimmed = input.trim();
  const local = extractCoordsFromText(trimmed);
  if (local) return local;
  if (!trimmed.startsWith('http') && !trimmed.includes('maps') && !trimmed.includes('goo.gl')) return null;

  const proxies: Array<(u: string) => Promise<{ url: string; body: string }>> = [
    async (u) => {
      const res = await fetch(`https://api.allorigins.win/get?url=${encodeURIComponent(u)}`);
      if (!res.ok) throw new Error('AllOrigins failed');
      const data = await res.json();
      return { url: data.status?.url || '', body: data.contents || '' };
    },
    async (u) => {
      const res = await fetch(`https://api.codetabs.com/v1/proxy?quest=${encodeURIComponent(u)}`);
      if (!res.ok) throw new Error('Codetabs failed');
      return { url: '', body: await res.text() };
    },
    async (u) => {
      const res = await fetch(`https://thingproxy.freeboard.io/fetch/${encodeURIComponent(u)}`);
      if (!res.ok) throw new Error('ThingProxy failed');
      return { url: '', body: await res.text() };
    },
  ];

  for (const proxy of proxies) {
    try {
      const { url, body } = await proxy(trimmed);
      const fromUrl = url ? extractCoordsFromText(url) : null;
      if (fromUrl) return fromUrl;
      if (!body) continue;

      const og = body.match(/property="og:url"\s+content="([^"]+)"/) || body.match(/content="([^"]+)"\s+property="og:url"/);
      const fromOg = og ? extractCoordsFromText(og[1]) : null;
      if (fromOg) return fromOg;

      const canonical = body.match(/rel="canonical"\s+href="([^"]+)"/) || body.match(/href="([^"]+)"\s+rel="canonical"/);
      const fromCanonical = canonical ? extractCoordsFromText(canonical[1]) : null;
      if (fromCanonical) return fromCanonical;

      const init = body.match(/APP_INITIALIZATION_STATE=\[\[\[(-?\d+\.\d+),(-?\d+\.\d+)/);
      if (init) return { lat: parseFloat(init[2]), lng: parseFloat(init[1]) };

      const fromBody = extractCoordsFromText(body);
      if (fromBody) return fromBody;
    } catch (err) {
      console.warn('Map link proxy failed:', err);
    }
  }
  return null;
}
