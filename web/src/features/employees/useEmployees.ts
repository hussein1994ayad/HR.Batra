'use client';

import { useCallback, useEffect, useState } from 'react';
import confetti from 'canvas-confetti';
import toast from 'react-hot-toast';
import type { ArchivedEmployee, Employee, EmployeeDevice } from '@/lib/db-types';
import { errorMessage } from '@/lib/error-utils';
import { readLocalCache, writeLocalCache } from '@/lib/local-cache';
import {
  approveDeviceRequest, archiveOrDeleteEmployee, createEmployee, destroyArchivedEmployee, fetchArchivedEmployees,
  fetchEmployeesDataset, rejectDeviceRequest, resetDeviceBinding, restoreArchivedEmployee, setDeviceLock,
  updateEmployee, type EmployeesDataset,
} from './api';
import type { DeleteType, EmployeeFormValues } from './types';

const CACHE_KEY = 'batra_cache_employees';
type EmployeesCache = Partial<EmployeesDataset> & { archivedEmployees?: ArchivedEmployee[] };
const readCache = () => readLocalCache<EmployeesCache>(CACHE_KEY);
const writeCache = (patch: EmployeesCache) => writeLocalCache(CACHE_KEY, patch);

const EMPTY: EmployeesDataset = { employees: [], deviceRequests: [], branches: [], departments: [] };

const celebrate = (colors?: string[]) => confetti({ particleCount: 60, spread: 45, ...(colors ? { colors } : {}) });

/** حالة صفحة الموظفين: البيانات، الأرشيف، وكل الإجراءات. */
export function useEmployees() {
  const [loading, setLoading] = useState(true);
  const [data, setData] = useState<EmployeesDataset>(EMPTY);
  const [archivedEmployees, setArchivedEmployees] = useState<ArchivedEmployee[]>([]);
  // مفتاح الزر الجاري تنفيذه (معرّف الموظف/الطلب أو اسم الإجراء) لتعطيله
  const [actionLoading, setActionLoading] = useState<string | null>(null);

  const loadEmployees = useCallback(async () => {
    try {
      const dataset = await fetchEmployeesDataset();
      setData(dataset);
      writeCache(dataset);
    } catch (err) {
      console.error(err);
      toast.error(`تعذر تحميل الموظفين: ${errorMessage(err)}`);
    } finally {
      setLoading(false);
    }
  }, []);

  const loadArchive = useCallback(async () => {
    try {
      const archived = await fetchArchivedEmployees();
      setArchivedEmployees(archived);
      writeCache({ archivedEmployees: archived });
    } catch (err) {
      console.error(err);
    }
  }, []);

  useEffect(() => {
    const cached = readCache();
    if (cached) {
      // eslint-disable-next-line react-hooks/set-state-in-effect -- عرض الكاش فوراً قبل وصول البيانات
      setData({ ...EMPTY, ...cached });
      setArchivedEmployees(cached.archivedEmployees ?? []);
      setLoading(false);
    }
    void loadEmployees();
    void loadArchive();
  }, [loadEmployees, loadArchive]);

  const refreshAll = () => Promise.all([loadEmployees(), loadArchive()]);

  /** ينفذ إجراءً مع تعطيل زره، ويعرض رسالة الفشل. يرجع true عند النجاح. */
  const run = async (key: string, action: () => Promise<void>, failure: string) => {
    setActionLoading(key);
    try {
      await action();
      return true;
    } catch (err: unknown) {
      toast.error(`${failure}: ${errorMessage(err) || 'حدث خطأ غير متوقع'}`);
      return false;
    } finally {
      setActionLoading(null);
    }
  };

  const warnFailedUploads = (failed: number) => {
    if (failed > 0) toast.error(`تعذر رفع ${failed} من الوثائق، يمكنك إعادة رفعها من التعديل.`);
  };

  const patchEmployee = (id: string, patch: Partial<Employee>) =>
    setData(prev => ({ ...prev, employees: prev.employees.map(e => (e.id === id ? { ...e, ...patch } : e)) }));

  // ------------------------------------------------------------------
  // الأجهزة
  // ------------------------------------------------------------------
  const toggleDeviceLock = (emp: Employee) =>
    run(emp.id, async () => {
      const lock = emp.device_id_lock ? null : 'force_lock_active';
      await setDeviceLock(emp.id, lock);
      patchEmployee(emp.id, { device_id_lock: lock });
      void celebrate(['#0D9488', '#10B981']);
    }, 'فشل تغيير قفل الجهاز');

  const resetDevice = (emp: Employee) => {
    if (!confirm('هل تريد فعلاً إلغاء ربط هاتف هذا الموظف بالكامل؟ سيمكنه هذا من تسجيل الدخول من أي هاتف جديد.')) return;
    return run(emp.id + '_reset', async () => {
      await resetDeviceBinding(emp.id);
      patchEmployee(emp.id, { device_id_lock: 'force_lock_active' });
      toast.success('تم فك قفل وربط هاتف الموظف بنجاح ✅');
    }, 'فشل فك ربط الهاتف');
  };

  const processDeviceRequest = (request: EmployeeDevice, approve: boolean) =>
    run(request.id, async () => {
      if (approve) await approveDeviceRequest(request);
      else await rejectDeviceRequest(request.id);
      await loadEmployees();
      void celebrate();
      toast.success(approve ? 'تم اعتماد وتثبيت الجهاز بنجاح! ✅' : 'تم رفض وإزالة طلب ربط الجهاز. ❌');
    }, 'فشل إتمام العملية');

  // ------------------------------------------------------------------
  // إضافة / تعديل / حذف
  // ------------------------------------------------------------------
  const addEmployee = (values: EmployeeFormValues, documents: File[]) =>
    run('create_emp', async () => {
      const { failedUploads } = await createEmployee(values, documents);
      await loadEmployees();
      void celebrate(['#0D9488', '#10B981']);
      toast.success('تم إضافة الموظف الجديد بنجاح وإنشاء حسابه الجغرافي! ✅');
      warnFailedUploads(failedUploads);
    }, 'فشل إضافة الموظف');

  const editEmployee = (emp: Employee, values: EmployeeFormValues, keptDocuments: string[], newDocuments: File[]) =>
    run('update_emp', async () => {
      const { failedUploads } = await updateEmployee(emp, values, keptDocuments, newDocuments);
      await loadEmployees();
      void celebrate(['#3B82F6', '#10B981']);
      toast.success('تم تحديث بيانات الموظف وسجلاته بنجاح! ✅');
      warnFailedUploads(failedUploads);
    }, 'فشل تعديل بيانات الموظف');

  const removeEmployee = (emp: Employee, deleteType: DeleteType, reason: string) =>
    run('delete_emp', async () => {
      await archiveOrDeleteEmployee(emp, deleteType, reason);
      await refreshAll();
      void celebrate(['#EF4444', '#F59E0B']);
      toast.success('تم تنفيذ عملية الحذف/الأرشفة المطلوبة للموظف بنجاح! ✅');
    }, 'فشل إتمام العملية');

  const restoreArchived = (record: ArchivedEmployee) => {
    if (!confirm(`هل أنت متأكد من رغبتك في استعادة الموظف (${record.full_name}) وتنشيط حسابه الجغرافي للدوام مجدداً؟`)) return;
    return run('restore_' + record.id, async () => {
      await restoreArchivedEmployee(record);
      await refreshAll();
      void celebrate(['#10B981', '#34D399']);
      toast.success('تم استعادة الموظف وتنشيط حسابه بالكامل بنجاح! ✅');
    }, 'فشل استعادة الموظف');
  };

  const destroyArchived = (record: ArchivedEmployee) => {
    if (!confirm(`تحذير نهائي: هل تريد حقاً حذف الموظف (${record.full_name}) وإتلاف حسابه وسجلاته وبصماته من قاعدة البيانات بشكل كامل ونهائي؟ لا يمكن استعادة البيانات بعد ذلك.`)) return;
    return run('perm_del_' + record.id, async () => {
      await destroyArchivedEmployee(record);
      await refreshAll();
      toast.success('تم إتلاف بيانات وحساب الموظف نهائياً وبنجاح! 🗑️');
    }, 'فشل الإتلاف النهائي');
  };

  return {
    loading, ...data, archivedEmployees, actionLoading,
    toggleDeviceLock, resetDevice, processDeviceRequest,
    addEmployee, editEmployee, removeEmployee, restoreArchived, destroyArchived,
  };
}
