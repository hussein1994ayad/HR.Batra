import { useSyncExternalStore } from 'react';

const noop = () => () => {};

/**
 * false أثناء البناء المسبق (static export) و true في المتصفح.
 * أي نص يعتمد على الوقت أو المنطقة الزمنية (تاريخ اليوم، التحية) يُعرض فقط بعد
 * التحميل، وإلا يختلف بين HTML المبني (بتوقيت خادم البناء UTC) والمتصفح (بغداد)
 * ويرمي React خطأ hydration رقم 418.
 */
export function useIsClient(): boolean {
  return useSyncExternalStore(noop, () => true, () => false);
}
