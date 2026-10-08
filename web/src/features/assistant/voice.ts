// السؤال بالصوت: المتصفح يسجّل (MediaRecorder) ← نحوله WAV أحادي 16kHz (نفس التطبيق، واضح للنسخ وصغير)
// ← ينرسل للمساعد. التسجيل ما ينحفظ بأي مكان.

/** أقصى طول للتسجيل (نفس حد السيرفر). */
export const MAX_RECORDING_SECONDS = 60;
export const WAV_SAMPLE_RATE = 16000;

/** PCM 16-bit أحادي داخل حاوية WAV. */
export function encodeWav(samples: Float32Array, sampleRate = WAV_SAMPLE_RATE): Uint8Array {
  const buf = new ArrayBuffer(44 + samples.length * 2);
  const v = new DataView(buf);
  const str = (o: number, s: string) => { for (let i = 0; i < s.length; i++) v.setUint8(o + i, s.charCodeAt(i)); };
  str(0, 'RIFF');
  v.setUint32(4, 36 + samples.length * 2, true);
  str(8, 'WAVE');
  str(12, 'fmt ');
  v.setUint32(16, 16, true); // حجم fmt
  v.setUint16(20, 1, true); // PCM
  v.setUint16(22, 1, true); // قناة وحدة
  v.setUint32(24, sampleRate, true);
  v.setUint32(28, sampleRate * 2, true); // بايت بالثانية
  v.setUint16(32, 2, true);
  v.setUint16(34, 16, true);
  str(36, 'data');
  v.setUint32(40, samples.length * 2, true);
  samples.forEach((x, i) => {
    const s = Math.max(-1, Math.min(1, x));
    v.setInt16(44 + i * 2, s < 0 ? s * 0x8000 : s * 0x7fff, true);
  });
  return new Uint8Array(buf);
}

export function bytesToBase64(bytes: Uint8Array): string {
  let bin = '';
  for (let i = 0; i < bytes.length; i += 0x8000) bin += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(bin);
}

/** يحوّل تسجيل المتصفح (webm/ogg/mp4) إلى WAV أحادي 16kHz. */
export async function blobToWav(blob: Blob): Promise<Uint8Array> {
  const ctx = new AudioContext();
  try {
    const decoded = await ctx.decodeAudioData(await blob.arrayBuffer());
    const length = Math.max(1, Math.ceil(decoded.duration * WAV_SAMPLE_RATE));
    const offline = new OfflineAudioContext(1, length, WAV_SAMPLE_RATE);
    const src = offline.createBufferSource();
    src.buffer = decoded;
    src.connect(offline.destination);
    src.start();
    const rendered = await offline.startRendering();
    return encodeWav(rendered.getChannelData(0));
  } finally {
    void ctx.close();
  }
}

/** رسالة مفهومة لأخطاء المايك. */
export function micErrorMessage(e: unknown): string {
  const name = e instanceof DOMException ? e.name : '';
  if (name === 'NotAllowedError' || name === 'SecurityError') {
    return 'المتصفح مسكّر المايك لهذا الموقع. اضغط على القفل جنب العنوان وفعّل المايكروفون.';
  }
  if (name === 'NotFoundError') return 'ماكو مايك متصل بالجهاز.';
  return 'ما اشتغل المايك. جرّب مرة ثانية.';
}
