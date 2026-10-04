// دخول لوحة الإدارة: فحص الجلسة الحالية، وتسجيل الدخول مع التأكد إن الحساب أدمن أو مدير فرع.

import { isDashboardRole } from '@/lib/role';
import { supabase } from '@/lib/supabase';

export { isDashboardRole };

/** هل توجد جلسة لحساب أدمن أو مدير؟ (ترمي إذا فشل جلب الجلسة) */
export async function hasDashboardSession(): Promise<boolean> {
  const { data: { session } } = await supabase.auth.getSession();
  if (!session) return false;
  // Verify role in employee table
  const { data: emp } = await supabase
    .from('employees')
    .select('role')
    .eq('id', session.user.id)
    .single();
  return !!emp && isDashboardRole(emp.role);
}

/**
 * تسجيل الدخول للوحة. ترمي Error برسالة عربية جاهزة للعرض إذا فشل الدخول أو الحساب مو أدمن/مدير
 * (وبهالحالة تسجّل الخروج حتى ما تبقى جلسة موظف بالمتصفح).
 */
export async function signInToDashboard(email: string, password: string): Promise<void> {
  // 1. Sign in with Supabase auth
  const { data: authData, error: authErr } = await supabase.auth.signInWithPassword({
    email,
    password,
  });

  if (authErr) {
    throw new Error('بيانات الدخول غير صحيحة، يرجى التحقق وإعادة المحاولة.');
  }

  if (!authData.user) {
    throw new Error('فشل تسجيل الدخول.');
  }

  // 2. verify role in employees table (must be admin or manager)
  const { data: emp, error: empErr } = await supabase
    .from('employees')
    .select('role, full_name')
    .eq('id', authData.user.id)
    .single();

  if (empErr || !emp) {
    // Sign out if not an admin
    await supabase.auth.signOut();
    throw new Error('عذراً! لا تمتلك صلاحيات كافية للوصول إلى لوحة الإدارة.');
  }

  if (!isDashboardRole(emp.role)) {
    await supabase.auth.signOut();
    throw new Error('عذراً! هذا الحساب مخصص للموظفين فقط. لوحة الويب للمسؤولين فقط.');
  }
}
