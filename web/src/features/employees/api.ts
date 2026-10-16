// استعلامات Supabase الخاصة بصفحة الموظفين. كل دالة ترمي عند الخطأ.

import { imageCompression } from '@/lib/lazy';
import { supabase } from '@/lib/supabase';
import { ensureChanged } from '@/lib/write-guard';
import { EMPLOYEE_COLUMNS, fetchEmployeePay } from '@/lib/employeePay';
import type { ArchivedEmployee, Department, Employee, EmployeeDevice } from '@/lib/db-types';
import { documentList, documentPathFromUrl, salaryUpdateFields } from './logic';
import { currentPayrollMonth } from '@/features/payroll/period';
import type { BranchOption, DeleteType, EmployeeFormValues, EmployeeHistoryEvent, EndOfServicePreview, ReactivateResult } from './types';

const DOCS_BUCKET = 'employee-documents';

export interface EmployeesDataset {
  employees: Employee[];
  deviceRequests: EmployeeDevice[];
  /** الهاتف المعتمد المربوط بكل موظف (employee_id → الموديل). هذا الربط الفعلي الي يشوفه التطبيق. */
  boundDevices: Record<string, string>;
  branches: BranchOption[];
  departments: Department[];
}

export async function fetchEmployeesDataset(): Promise<EmployeesDataset> {
  const [emps, reqs, bound, brs, depts, pay] = await Promise.all([
    supabase.from('employees').select(`${EMPLOYEE_COLUMNS}, branches(name)`).order('full_name', { ascending: true }),
    supabase.from('employee_devices').select('*, employees(full_name)').eq('is_approved', false),
    supabase.from('employee_devices').select('employee_id, model').eq('is_approved', true),
    supabase.from('branches').select('id, name').order('name'),
    // تُستعمل في البحث بالقسم
    supabase.from('departments').select('id, name').order('name'),
    // الراتب من السيرفر (للأدمن؛ المدير ما يوصله شي)
    fetchEmployeePay(),
  ]);
  const firstError = [emps, reqs, bound, brs, depts].find(r => r.error)?.error;
  if (firstError) throw firstError;

  const boundDevices: Record<string, string> = {};
  for (const d of (bound.data ?? []) as { employee_id: string; model: string | null }[]) {
    boundDevices[d.employee_id] = d.model || 'هاتف';
  }

  return {
    employees: ((emps.data ?? []) as unknown as Employee[]).map(e => ({ ...e, ...pay[e.id] })),
    deviceRequests: reqs.data ?? [],
    boundDevices,
    branches: brs.data ?? [],
    departments: depts.data ?? [],
  };
}

export async function fetchArchivedEmployees(): Promise<ArchivedEmployee[]> {
  const { data, error } = await supabase
    .from('archived_employees')
    .select('*')
    .order('archived_at', { ascending: false });
  if (error) throw error;
  return data ?? [];
}

// ------------------------------------------------------------------
// قفل الأجهزة
// ------------------------------------------------------------------

export async function setDeviceLock(employeeId: string, lock: string | null) {
  await ensureChanged(supabase.from('employees').update({ device_id_lock: lock }).eq('id', employeeId).select('id'));
}

/** يمسح أجهزة الموظف المسجلة ويفعّل القفل ليُربط أول هاتف يدخل منه. */
export async function resetDeviceBinding(employeeId: string) {
  const { error } = await supabase.from('employee_devices').delete().eq('employee_id', employeeId);
  if (error) throw error;
  await setDeviceLock(employeeId, 'force_lock_active');
}

/** اعتماد طلب جهاز: يُقفل حساب الموظف على هذا الجهاز ويُرسل له إشعاراً. */
export async function approveDeviceRequest(request: Pick<EmployeeDevice, 'id' | 'employee_id' | 'device_id'>) {
  await ensureChanged(supabase
    .from('employee_devices')
    .update({ is_approved: true, approved_at: new Date().toISOString() })
    .eq('id', request.id)
    .select('id'));

  await setDeviceLock(request.employee_id, request.device_id);

  await supabase.from('notifications').insert({
    employee_id: request.employee_id,
    title: 'اعتماد جهاز الدخول الجديد 📱',
    body: 'تهانينا! تمت موافقة الإدارة على اعتماد هاتف تسجيل دخولك الجديد.',
    type: 'device',
  });
}

export async function rejectDeviceRequest(requestId: string) {
  await ensureChanged(supabase.from('employee_devices').delete().eq('id', requestId).select('id'));
}

// ------------------------------------------------------------------
// الوثائق
// ------------------------------------------------------------------

/** يضغط الصور ويرفع الملفات إلى مجلد الموظف. الملف الذي يفشل يُتخطى ويُحسب في failed. */
export async function uploadEmployeeDocuments(employeeId: string, files: File[]): Promise<{ urls: string[]; failed: number }> {
  const urls: string[] = [];
  let failed = 0;
  for (const file of files) {
    try {
      const fileToUpload = file.type.startsWith('image/')
        ? await imageCompression(file, { maxSizeMB: 1, maxWidthOrHeight: 1920, useWebWorker: true })
        : file;
      const fileExt = file.name.split('.').pop();
      const fileName = `${employeeId}/${Date.now()}_${Math.random().toString(36).substring(7)}.${fileExt}`;

      const { error } = await supabase.storage.from(DOCS_BUCKET).upload(fileName, fileToUpload);
      if (error) throw error;
      urls.push(supabase.storage.from(DOCS_BUCKET).getPublicUrl(fileName).data.publicUrl);
    } catch (err) {
      console.error('Failed to compress/upload file:', err);
      failed++;
    }
  }
  return { urls, failed };
}

/** حذف مباشر من التخزين: بس لملفات انرفعت هسه وما انحفظت (التعديل فشل)، أو سيرفر قبل تحديث 20261023000000. */
async function removeEmployeeDocuments(urls: string[]) {
  const paths = urls.map(documentPathFromUrl).filter((p): p is string => !!p);
  if (paths.length === 0) return;
  const { error } = await supabase.storage.from(DOCS_BUCKET).remove(paths);
  if (error) console.error('Failed to delete old documents:', error);
}

// ------------------------------------------------------------------
// إضافة وتعديل
// ------------------------------------------------------------------

function newUuid(): string {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') return crypto.randomUUID();
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    return (c === 'x' ? r : (r & 0x3) | 0x8).toString(16);
  });
}

/** ينشئ الموظف وحسابه في معاملة واحدة (RPC). المعرّف يُولّد مسبقاً ليكون اسم مجلد الوثائق. */
export async function createEmployee(values: EmployeeFormValues, documents: File[]) {
  const employeeId = newUuid();
  const { urls, failed } = await uploadEmployeeDocuments(employeeId, documents);

  const create = (code: string | null) => supabase.rpc('create_employee_secure', {
    p_email: values.email,
    p_password: values.password,
    p_full_name: values.fullName,
    p_phone: values.phone || null,
    p_role: values.role,
    p_branch_id: values.branchId || null,
    p_monthly_salary_iqd: values.monthlySalary || 0,
    p_document_urls: urls,
    // رقم الموظف بالتسلسل من السيرفر (EMP-003، EMP-004...) بدل رقم عشوائي يتكرر (تدقيق 14/10 BUG-010)
    p_employee_code: code,
    p_employee_id: employeeId,
    p_join_date: values.joinDate,
    p_department_id: values.departmentId || null,
  });
  let { error } = await create(null);
  // سيرفر قبل تحديث 20261023000000: الرقم إجباري
  if (error?.code === '23502') ({ error } = await create(`EMP-${Math.floor(1000 + Math.random() * 9000)}`));
  if (error) {
    await removeEmployeeDocuments(urls);
    throw error;
  }
  return { failedUploads: failed };
}

export async function updateEmployee(
  employee: Employee,
  values: EmployeeFormValues,
  keptDocuments: string[],
  newDocuments: File[],
) {
  const { urls, failed } = await uploadEmployeeDocuments(employee.id, newDocuments);
  const changes = {
    full_name: values.fullName,
    role: values.role,
    branch_id: values.branchId || null,
    department_id: values.departmentId || null,
    ...salaryUpdateFields(values, currentPayrollMonth()),
    document_urls: [...keptDocuments, ...urls],
    join_date: values.joinDate,
  };
  // خطوة وحدة بالسيرفر (تدقيق 14/10 CODE-005): الإيميل وكلمة السر والبيانات يا كلها تنحفظ يا ولا شي.
  // المستمسكات المشالة تروح للسلة بس بعد ما ينحفظ التعديل (BUG-009؛ كانت تنحذف قبل الحفظ)
  const { error } = await supabase.rpc('save_employee', {
    p_employee_id: employee.id,
    p_email: values.email,
    p_password: values.password,
    p_phone: values.phone || '',
    p_changes: changes,
  });
  if (!error) return { failedUploads: failed };
  if (error.code !== 'PGRST202') {
    await removeEmployeeDocuments(urls); // انرفعت هسه وما انحفظت
    throw error;
  }
  // سيرفر قبل التحديث: نفس الخطوات القديمة، بس الحذف بعد ما ينحفظ السطر
  const { error: rpcErr } = await supabase.rpc('update_employee_credentials', {
    p_employee_id: employee.id,
    p_email: values.email,
    p_password: values.password,
    p_phone: values.phone || '',
  });
  if (rpcErr) throw rpcErr;
  const { error: updErr } = await supabase.from('employees').update(changes).eq('id', employee.id);
  if (updErr) throw updErr;
  await removeEmployeeDocuments(documentList(employee.document_urls).filter(url => !keptDocuments.includes(url)));
  return { failedUploads: failed };
}

// ------------------------------------------------------------------
// الأرشفة والحذف
// ------------------------------------------------------------------

// القاعدة تقبل 'archived' (كان 'archive' فيفشل الخيار الافتراضي «أرشفة» بعد ما يعطّل الموظف)
const ARCHIVE_TYPES: Record<DeleteType, { type: string; reason: string }> = {
  immediate: { type: 'permanent', reason: 'حذف فوري نهائي من لوحة التحكم' },
  archive: { type: 'archived', reason: 'أرشفة وتعطيل الحساب الإداري للموظف' },
  scheduled: { type: 'scheduled_deletion', reason: 'حذف مجدول بعد 30 يوماً من لوحة التحكم' },
};

/** إنهاء الخدمات: آخر يوم + تعطيل (أو حذف فوري) + سجل الأرشيف، بخطوة وحدة بالسيرفر (تدقيق 14/10 CODE-005). */
export async function archiveOrDeleteEmployee(employee: Employee, deleteType: DeleteType, reason: string, lastDay?: string) {
  const { error: rpcError } = await supabase.rpc('end_employee_service', {
    p_employee_id: employee.id,
    p_type: deleteType,
    p_reason: reason || null,
    p_last_day: lastDay || null,
  });
  if (!rpcError) return;
  if (rpcError.code !== 'PGRST202') throw rpcError;

  // سيرفر قبل تحديث 20261023000000: الخطوات القديمة
  const { data: { session } } = await supabase.auth.getSession();

  if (deleteType === 'immediate') {
    const { error } = await supabase.rpc('hard_delete_employee', { p_employee_id: employee.id });
    if (error) throw error;
    if (lastDay) {
      const { error: dateErr } = await supabase.from('employees').update({ termination_date: lastDay }).eq('id', employee.id);
      if (dateErr) throw dateErr;
    }
  } else {
    // آخر يوم عمل فعلي يحدد راتب المسير الأخير (بدونه يُعتمد تاريخ اليوم)
    const { error } = await supabase.from('employees')
      .update({ is_active: false, ...(lastDay ? { termination_date: lastDay } : {}) })
      .eq('id', employee.id);
    if (error) throw error;
  }

  let scheduledDeletion: string | undefined;
  if (deleteType === 'scheduled') {
    const date = new Date();
    date.setDate(date.getDate() + 30);
    scheduledDeletion = date.toISOString();
  }

  const { error } = await supabase.from('archived_employees').insert({
    employee_id: employee.id,
    employee_code: employee.employee_code,
    full_name: employee.full_name,
    archive_type: ARCHIVE_TYPES[deleteType].type,
    archive_reason: reason || ARCHIVE_TYPES[deleteType].reason,
    ...(scheduledDeletion ? { scheduled_deletion_date: scheduledDeletion } : {}),
    archived_by: session?.user?.id,
    archived_at: new Date().toISOString(),
  });
  if (error) throw error;
}

/**
 * تفعيل حساب موظف ترك ورجع بتاريخ رجوعه (تدقيق 14/10 PAY-009): أيام الانقطاع ما تطلع غياب وتنقص من راتب ذاك المسير.
 * سيرفر قبل تحديث 20261021000000: تفعيل عادي (الرجوع = اليوم).
 */
export async function reactivateEmployee(employeeId: string, returnDate: string): Promise<ReactivateResult> {
  const { data, error } = await supabase.rpc('reactivate_employee', { p_employee_id: employeeId, p_return_date: returnDate });
  if (!error) return data as ReactivateResult;
  if (error.code !== 'PGRST202') throw error;
  const { error: updErr } = await supabase.from('employees').update({ is_active: true, termination_date: null }).eq('id', employeeId);
  if (updErr) throw updErr;
  return { gap_days: 0, warnings: [] };
}

export async function restoreArchivedEmployee(record: ArchivedEmployee, returnDate: string): Promise<ReactivateResult> {
  // خطوة وحدة بالسيرفر: التفعيل بتاريخ الرجوع + شيل سجل الأرشيف (تدقيق 14/10 CODE-005)
  const { data, error: rpcError } = await supabase.rpc('restore_archived_employee', { p_archive_id: record.id, p_return_date: returnDate });
  if (!rpcError) return (data ?? { gap_days: 0, warnings: [] }) as ReactivateResult;
  if (rpcError.code !== 'PGRST202') throw rpcError;

  let result: ReactivateResult = { gap_days: 0, warnings: [] };
  try {
    result = await reactivateEmployee(record.employee_id, returnDate);
  } catch (err) {
    // سجل أرشيف لحساب مفعّل أصلاً: بس ينشال من الأرشيف
    if (!String((err as { message?: string })?.message ?? '').includes('مفعّل أصلاً')) throw err;
  }
  const { error } = await supabase.from('archived_employees').delete().eq('id', record.id);
  if (error) throw error;
  return result;
}

/** سجل الموظف بالتواريخ (باشر، انتقل، ترك، رجع). null = سيرفر قبل تحديث 20261021000000. */
export async function fetchEmployeeHistory(employeeId: string): Promise<EmployeeHistoryEvent[] | null> {
  const { data, error } = await supabase.rpc('get_employee_history', { p_employee_id: employeeId });
  if (error) {
    if (error.code === 'PGRST202') return null;
    throw error;
  }
  return (data ?? []) as EmployeeHistoryEvent[];
}

export async function destroyArchivedEmployee(record: ArchivedEmployee) {
  // خطوة وحدة بالسيرفر (تدقيق 14/10 CODE-005)؛ مستمسكاته وصورته تروح للسلة 30 يوم (BUG-008)
  const { error: oneStep } = await supabase.rpc('destroy_archived_employee', { p_archive_id: record.id });
  if (!oneStep) return;
  if (oneStep.code !== 'PGRST202') throw oneStep;

  const { error: rpcErr } = await supabase.rpc('hard_delete_employee', { p_employee_id: record.employee_id });
  if (rpcErr) throw rpcErr;
  const { error } = await supabase
    .from('archived_employees')
    .update({ archive_type: 'permanent', notes: 'تم الإتلاف النهائي اليدوي للبيانات والحساب من قبل المسؤول.' })
    .eq('id', record.id);
  if (error) throw error;
}

/**
 * معاينة «إنهاء خدمات»: شلون ينحسب آخر راتب لو آخر يوم = lastDay (أيام الدوام بس، والخصومات اللي قررتها الإدارة).
 * السيرفر يحسبها ويتراجع، فما يتغير شي. null = سيرفر قبل تحديث 20261020000000.
 */
export async function fetchEndOfServicePreview(employeeId: string, lastDay: string): Promise<EndOfServicePreview | null> {
  const { data, error } = await supabase.rpc('end_of_service_preview', { p_employee_id: employeeId, p_last_day: lastDay });
  if (error) {
    if (error.code === 'PGRST202') return null;
    throw error;
  }
  return data as EndOfServicePreview;
}

/** آخر يوم بصم بيه الموظف (اقتراح «آخر يوم عمل» عند التعطيل). */
export async function fetchLastPunchDate(employeeId: string): Promise<string | null> {
  const { data, error } = await supabase
    .from('attendance')
    .select('work_date')
    .eq('employee_id', employeeId)
    .not('check_in_time', 'is', null)
    .order('work_date', { ascending: false })
    .limit(1);
  if (error) return null;
  return (data?.[0]?.work_date as string | undefined) ?? null;
}
