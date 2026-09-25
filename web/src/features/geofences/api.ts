// استعلامات Supabase الخاصة بصفحة الفروع الجغرافية. كل دالة ترمي عند الخطأ.

import { supabase } from '@/lib/supabase';
import { getLocalDateStr } from '@/lib/dates';
import type { AttendanceRecord, Branch } from '@/lib/db-types';

export type BranchInput = Pick<Branch, 'name' | 'latitude' | 'longitude' | 'radius_meters' | 'address'>;

export async function fetchBranches(): Promise<Branch[]> {
  const { data, error } = await supabase.from('branches').select('*').order('created_at', { ascending: false });
  if (error) throw error;
  return data ?? [];
}

export async function fetchTodayAttendance(): Promise<AttendanceRecord[]> {
  const { data, error } = await supabase
    .from('attendance')
    .select('*, employees!employee_id(full_name, phone, email, branch_id)')
    .eq('work_date', getLocalDateStr());
  if (error) throw error;
  return data ?? [];
}

function validate(input: BranchInput) {
  if (!(input.radius_meters > 0)) throw new Error('يجب أن يكون مدى البصمة (نصف القطر) أكبر من 0 متر');
}

export async function createBranch(input: BranchInput) {
  validate(input);
  const { error } = await supabase.from('branches').insert(input);
  if (error) throw error;
}

export async function updateBranch(id: string, input: BranchInput) {
  validate(input);
  const { error } = await supabase.from('branches').update(input).eq('id', id);
  if (error) throw error;
}

export async function deleteBranch(id: string) {
  const { error } = await supabase.from('branches').delete().eq('id', id);
  if (error) throw error;
}
