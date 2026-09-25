// كاش localStorage لعرض الصفحات فوراً قبل وصول البيانات.
// قد يكون التخزين محجوباً (نافذة خاصة، إعدادات المتصفح)، فكل الأخطاء تُتجاهل.

export function readLocalCache<T>(key: string): T | null {
  try {
    const raw = localStorage.getItem(key);
    return raw ? (JSON.parse(raw) as T) : null;
  } catch {
    return null;
  }
}

/** يدمج القيم الجديدة مع المخزّن مسبقاً تحت نفس المفتاح. */
export function writeLocalCache<T extends object>(key: string, patch: T) {
  try {
    localStorage.setItem(key, JSON.stringify({ ...readLocalCache<T>(key), ...patch }));
  } catch {
    // تجاهل
  }
}
