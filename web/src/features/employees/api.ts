// استعلامات Supabase الخاصة بصفحة الموظفين. كل دالة ترمي عند الخطأ.

import imageCompression from 'browser-image-compression';
import { supabase } from '@/lib/supabase';
import type { ArchivedEmployee, Department, Employee, EmployeeDevice } from '@/lib/db-types';
import { documentPathFromUrl } from './logic';
import type { BranchOption, DeleteType, EmployeeFormValues } from './types';

const DOCS_BUCKET = 'employee-documents';

export interface EmployeesDataset {
  employees: Employee[];
  deviceRequests: EmployeeDevice[];
  branches: BranchOption[];
  departments: Department[];
}

export async function fetchEmployeesDataset(): Promise<EmployeesDataset> {
  const [emps, reqs, brs, depts] = await Promise.all([
    supabase.from('employees').select('*, branches(name)').order('full_name', { ascending: true }),
    supabase.from('employee_devices').select('*, employees(full_name)').eq('is_approved', false),
    supabase.from('branches').select('id, name').order('name'),
    // تُستعمل في البحث بالقسم
    supabase.from('departments').select('id, name').order('name'),
  ]);
  const firstError = [emps, reqs, brs, depts].find(r => r.error)?.error;
  if (firstError) throw firstError;

  return {
    employees: emps.data ?? [],
    deviceRequests: reqs.data ?? [],
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
  const { error } = await supabase.from('employees').update({ device_id_lock: lock }).eq('id', employeeId);
  if (error) throw error;
}

/** يمسح أجهزة الموظف المسجلة ويفعّل القفل ليُربط أول هاتف يدخل منه. */
export async function resetDeviceBinding(employeeId: string) {
  const { error } = await supabase.from('employee_devices').delete().eq('employee_id', employeeId);
  if (error) throw error;
  await setDeviceLock(employeeId, 'force_lock_active');
}

/** اعتماد طلب جهاز: يُقفل حساب الموظف على هذا الجهاز ويُرسل له إشعاراً. */
export async function approveDeviceRequest(request: Pick<EmployeeDevice, 'id' | 'employee_id' | 'device_id'>) {
  const { error } = await supabase
    .from('employee_devices')
    .update({ is_approved: true, approved_at: new Date().toISOString() })
    .eq('id', request.id);
  if (error) throw error;

  await setDeviceLock(request.employee_id, request.device_id);

  await supabase.from('notifications').insert({
    employee_id: request.employee_id,
    title: 'اعتماد جهاز الدخول الجديد 📱',
    body: 'تهانينا! تمت موافقة الإدارة على اعتماد هاتف تسجيل دخولك الجديد.',
    type: 'device',
  });
}

export async function rejectDeviceRequest(requestId: string) {
  const { error } = await supabase.from('employee_devices').delete().eq('id', requestId);
  if (error) throw error;
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

  const { error } = await supabase.rpc('create_employee_secure', {
    p_email: values.email,
    p_password: values.password,
    p_full_name: values.fullName,
    p_phone: values.phone || null,
    p_role: values.role,
    p_branch_id: values.branchId || null,
    p_monthly_salary_iqd: values.monthlySalary || 0,
    p_document_urls: urls,
    p_employee_code: `EMP-${Math.floor(100 + Math.random() * 900)}`,
    p_employee_id: employeeId,
    p_join_date: values.joinDate,
  });
  if (error) throw error;
  return { failedUploads: failed };
}

export async function updateEmployee(
  employee: Employee,
  values: EmployeeFormValues,
  keptDocuments: string[],
  newDocuments: File[],
) {
  const { error: rpcErr } = await supabase.rpc('update_employee_credentials', {
    p_employee_id: employee.id,
    p_email: values.email,
    p_password: values.password,
    p_phone: values.phone || '',
  });
  if (rpcErr) throw rpcErr;

  await removeEmployeeDocuments((employee.document_urls || []).filter(url => !keptDocuments.includes(url)));
  const { urls, failed } = await uploadEmployeeDocuments(employee.id, newDocuments);

  const { error } = await supabase
    .from('employees')
    .update({
      full_name: values.fullName,
      role: values.role,
      branch_id: values.branchId || null,
      monthly_salary_iqd: values.monthlySalary || 0,
      future_salary_iqd: values.futureSalary || null,
      future_salary_month: values.futureSalaryMonth || null,
      plain_password: values.password,
      document_urls: [...keptDocuments, ...urls],
      join_date: values.joinDate,
    })
    .eq('id', employee.id);
  if (error) throw error;
  return { failedUploads: failed };
}

// ------------------------------------------------------------------
// الأرشفة والحذف
// ------------------------------------------------------------------

const ARCHIVE_TYPES: Record<DeleteType, { type: string; reason: string }> = {
  immediate: { type: 'permanent', reason: 'حذف فوري نهائي من لوحة التحكم' },
  archive: { type: 'archive', reason: 'أرشفة وتعطيل الحساب الإداري للموظف' },
  scheduled: { type: 'scheduled_deletion', reason: 'حذف مجدول بعد 30 يوماً من لوحة التحكم' },
};

/** حذف فوري (RPC) أو تعطيل الحساب، ثم تسجيل الإجراء في الأرشيف. */
export async function archiveOrDeleteEmployee(employee: Employee, deleteType: DeleteType, reason: string) {
  const { data: { session } } = await supabase.auth.getSession();

  if (deleteType === 'immediate') {
    const { error } = await supabase.rpc('hard_delete_employee', { p_employee_id: employee.id });
    if (error) throw error;
  } else {
    const { error } = await supabase.from('employees').update({ is_active: false }).eq('id', employee.id);
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

export async function restoreArchivedEmployee(record: ArchivedEmployee) {
  const { error: updErr } = await supabase.from('employees').update({ is_active: true }).eq('id', record.employee_id);
  if (updErr) throw updErr;
  const { error } = await supabase.from('archived_employees').delete().eq('id', record.id);
  if (error) throw error;
}

export async function destroyArchivedEmployee(record: ArchivedEmployee) {
  const { error: rpcErr } = await supabase.rpc('hard_delete_employee', { p_employee_id: record.employee_id });
  if (rpcErr) throw rpcErr;
  const { error } = await supabase
    .from('archived_employees')
    .update({ archive_type: 'permanent', notes: 'تم الإتلاف النهائي اليدوي للبيانات والحساب من قبل المسؤول.' })
    .eq('id', record.id);
  if (error) throw error;
}
