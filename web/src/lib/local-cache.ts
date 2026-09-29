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

/**
 * يمسح كل كاش اللوحة (batra_cache_*) من المتصفح: بيانات الموظفين والرواتب والفروع.
 * يُستدعى عند تسجيل الخروج أو انتهاء الجلسة حتى لا تبقى بيانات حساسة على جهاز مشترك.
 */
export function clearLocalCaches() {
  try {
    for (const key of Object.keys(localStorage)) {
      if (key.startsWith('batra_cache_')) localStorage.removeItem(key);
    }
  } catch {
    // تجاهل
  }
}
