'use client';

// تسجيل سؤال بالصوت من المايك: start ← stop يرجع WAV (أو cancel). يوقف تلقائياً عند دقيقة.

import { useEffect, useRef, useState } from 'react';
import { blobToWav, MAX_RECORDING_SECONDS, micErrorMessage } from './voice';

export function useVoiceRecorder(onRecorded: (wav: Uint8Array) => void) {
  const [recording, setRecording] = useState(false);
  const [seconds, setSeconds] = useState(0);
  const [error, setError] = useState('');
  const rec = useRef<MediaRecorder | null>(null);
  const chunks = useRef<Blob[]>([]);
  const cancelled = useRef(false);
  const timer = useRef<ReturnType<typeof setInterval> | null>(null);
  const done = useRef(onRecorded);
  useEffect(() => { done.current = onRecorded; }, [onRecorded]);

  const cleanup = () => {
    if (timer.current) clearInterval(timer.current);
    timer.current = null;
    rec.current?.stream.getTracks().forEach((t) => t.stop());
    rec.current = null;
    setRecording(false);
  };

  const stop = () => {
    if (rec.current?.state === 'recording') rec.current.stop();
  };

  const cancel = () => {
    cancelled.current = true;
    stop();
  };

  const start = async () => {
    if (recording) return;
    setError('');
    if (!navigator.mediaDevices?.getUserMedia || typeof MediaRecorder === 'undefined') {
      setError('هذا المتصفح ما يدعم التسجيل. جرّب Chrome أو Edge.');
      return;
    }
    let stream: MediaStream;
    try {
      stream = await navigator.mediaDevices.getUserMedia({ audio: { channelCount: 1, echoCancellation: true, noiseSuppression: true } });
    } catch (e) {
      setError(micErrorMessage(e));
      return;
    }
    const r = new MediaRecorder(stream);
    chunks.current = [];
    cancelled.current = false;
    let startedAt = Date.now();
    r.ondataavailable = (e) => { if (e.data.size) chunks.current.push(e.data); };
    r.onstop = async () => {
      const tooShort = Date.now() - startedAt < 1000;
      const wasCancelled = cancelled.current;
      const blob = new Blob(chunks.current, { type: r.mimeType });
      cleanup();
      if (wasCancelled) return;
      if (tooShort || !blob.size) {
        setError('التسجيل قصير. اضغط المايك واحچي سؤالك، وبعدين اضغط إرسال.');
        return;
      }
      try {
        done.current(await blobToWav(blob));
      } catch {
        setError('ما انقرا التسجيل. جرّب مرة ثانية.');
      }
    };
    rec.current = r;
    r.start();
    startedAt = Date.now();
    setSeconds(0);
    setRecording(true);
    timer.current = setInterval(() => {
      setSeconds((s) => {
        if (s + 1 >= MAX_RECORDING_SECONDS) stop();
        return s + 1;
      });
    }, 1000);
  };

  // طلعة من الصفحة أثناء التسجيل: نلغي ونطفي المايك
  useEffect(() => () => {
    cancelled.current = true;
    if (rec.current?.state === 'recording') rec.current.stop();
    if (timer.current) clearInterval(timer.current);
    rec.current?.stream.getTracks().forEach((t) => t.stop());
  }, []);

  return { recording, seconds, error, clearError: () => setError(''), start, stop, cancel };
}
