// بيانات صفحة الفروع: الفروع + حضور اليوم (لمعرفة من بصم بكل فرع)، مع كاش محلي يظهر فوراً.

import { supabase } from '@/lib/supabase';
import { writeCache } from '@/lib/useQuery';
import { localDateStr } from '@/lib/format';
import type { Attendance, Branch } from '@/lib/db-types';

export interface GeofencesData {
  branches: Branch[];
  todayLogs: Attendance[];
}

export const GEOFENCES_CACHE_KEY = 'batra_cache_geofences_v2';

export async function fetchGeofences(): Promise<GeofencesData> {
  const [branches, logs] = await Promise.all([
    supabase.from('branches').select('*').order('created_at', { ascending: false }),
    supabase
      .from('attendance')
      .select('*, employees!employee_id(full_name, phone, email, branch_id)')
      .eq('work_date', localDateStr()),
  ]);
  if (branches.error) throw branches.error;
  const data = { branches: (branches.data ?? []) as Branch[], todayLogs: (logs.data ?? []) as Attendance[] };
  writeCache(GEOFENCES_CACHE_KEY, data);
  return data;
}

export async function deleteBranch(id: string): Promise<void> {
  const { error } = await supabase.from('branches').delete().eq('id', id);
  if (error) throw error;
}

/** إضافة فرع (بدون id) أو تحديثه. ترمي عند الخطأ. */
export async function saveBranch(
  payload: { name: string; latitude: number; longitude: number; radius_meters: number; address: string },
  id?: string,
): Promise<void> {
  if (id) {
    const { error } = await supabase.from('branches').update(payload).eq('id', id);
    if (error) throw error;
  } else {
    const { error } = await supabase.from('branches').insert(payload);
    if (error) throw error;
  }
}
