// Heavy client-only libraries are loaded on first use instead of being bundled
// into every dashboard page, which keeps initial page loads small and fast.

import type { Options as ConfettiOptions } from 'canvas-confetti';
import type { Options as CompressionOptions } from 'browser-image-compression';

export function confetti(options?: ConfettiOptions) {
  import('canvas-confetti')
    .then(({ default: fire }) => fire(options))
    .catch((err) => console.error('Failed to load confetti:', err));
}

export async function imageCompression(file: File, options: CompressionOptions): Promise<File> {
  const { default: compress } = await import('browser-image-compression');
  return compress(file, options);
}
