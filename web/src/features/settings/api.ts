// أداة تنظيف قاعدة البيانات: حذف بيانات شهر (بعد اعتماد رواتبه) عبر RPC يتحقق من القفل المالي.

import { supabase } from '@/lib/supabase';
import type { PurgeOptions, PurgeResult } from './types';

export async function purgeMonthData(options: PurgeOptions): Promise<PurgeResult | null> {
  const { data, error } = await supabase.rpc('manual_purge_month_data', {
    p_year: Number(options.year),
    p_month: Number(options.month),
    p_notifications: options.notifications,
    p_tracking: options.tracking,
    p_absences: options.absences,
  });
  if (error) throw error;
  return (data as PurgeResult[] | null)?.[0] ?? null;
}
