'use client';

import { useCallback, useEffect, useState } from 'react';
import confetti from 'canvas-confetti';
import toast from 'react-hot-toast';
import type { ConfirmOptions } from '@/components/confirm';
import type { ArchivedEmployee, Employee, EmployeeDevice } from '@/lib/db-types';
import { errorMessage } from '@/lib/error-utils';
import { readLocalCache, writeLocalCache } from '@/lib/local-cache';
import {
  approveDeviceRequest, archiveOrDeleteEmployee, createEmployee, destroyArchivedEmployee, fetchArchivedEmployees,
  fetchEmployeesDataset, rejectDeviceRequest, resetDeviceBinding, restoreArchivedEmployee, setDeviceLock,
  updateEmployee, type EmployeesDataset,
} from './api';
import { getLocalDateStr } from '@/lib/dates';
import type { DeleteType, EmployeeFormValues } from './types';

const CACHE_KEY = 'batra_cache_employees';
type EmployeesCache = Partial<EmployeesDataset> & { archivedEmployees?: ArchivedEmployee[] };
const readCache = () => readLocalCache<EmployeesCache>(CACHE_KEY);
const writeCache = (patch: EmployeesCache) => writeLocalCache(CACHE_KEY, patch);

const EMPTY: EmployeesDataset = { employees: [], deviceRequests: [], boundDevices: {}, branches: [], departments: [] };

const celebrate = (colors?: string[]) => confetti({ particleCount: 60, spread: 45, ...(colors ? { colors } : {}) });

/** حالة صفحة الموظفين: البيانات، الأرشيف، وكل الإجراءات. */
type Ask = (options: ConfirmOptions) => Promise<boolean>;
type AskDate = (options: ConfirmOptions) => Promise<string | null>;

export function useEmployees(ask: Ask, askDate: AskDate) {
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

  const resetDevice = async (emp: Employee) => {
    const ok = await ask({
      title: 'إلغاء ربط هاتف الموظف؟',
      message: `سيتمكن ${emp.full_name} من تسجيل الدخول من هاتف جديد، وسيُقفل الحساب على أول جهاز يسجل منه.`,
      confirmLabel: 'إلغاء الربط',
      tone: 'warning',
    });
    if (!ok) return;
    return run(emp.id + '_reset', async () => {
      await resetDeviceBinding(emp.id);
      patchEmployee(emp.id, { device_id_lock: 'force_lock_active' });
      setData(prev => {
        const boundDevices = { ...prev.boundDevices };
        delete boundDevices[emp.id];
        return { ...prev, boundDevices };
      });
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

  const removeEmployee = (emp: Employee, deleteType: DeleteType, reason: string, lastDay?: string) =>
    run('delete_emp', async () => {
      await archiveOrDeleteEmployee(emp, deleteType, reason, lastDay);
      await refreshAll();
      void celebrate(['#EF4444', '#F59E0B']);
      toast.success('تم تنفيذ عملية الحذف/الأرشفة المطلوبة للموظف بنجاح! ✅');
    }, 'فشل إتمام العملية');

  const restoreArchived = async (record: ArchivedEmployee) => {
    // رجوع للعمل بتاريخه (تدقيق 14/10 PAY-009): الأيام بين آخر يوم عمل ويوم الرجوع ما تطلع غياب
    const today = getLocalDateStr();
    const returnDate = await askDate({
      title: 'استعادة الموظف؟',
      message: `يرجع حساب ${record.full_name} يشتغل ويكدر يبصم.`,
      confirmLabel: 'استعادة',
      tone: 'primary',
      date: {
        label: 'تاريخ الرجوع للعمل',
        initial: today,
        max: today,
        hint: 'الأيام من آخر يوم عمل لحد هذا اليوم ما تطلع غياب، وتنقص من راتب ذاك الشهر مثل الأيام قبل المباشرة.',
      },
    });
    if (!returnDate) return;
    return run('restore_' + record.id, async () => {
      const result = await restoreArchivedEmployee(record, returnDate);
      await refreshAll();
      void celebrate(['#10B981', '#34D399']);
      toast.success(result.gap_days > 0
        ? `رجع ${record.full_name} للعمل. ${result.gap_days} يوم انقطاع ما تنحسب غياب ✅`
        : `رجع ${record.full_name} للعمل ✅`);
      for (const w of result.warnings) toast(w, { icon: '⚠️', duration: 8000 });
    }, 'فشل استعادة الموظف');
  };

  const destroyArchived = async (record: ArchivedEmployee) => {
    const ok = await ask({
      title: 'إتلاف بيانات الموظف نهائياً؟',
      message: `سيتم حذف حساب ${record.full_name} وسجلاته وبصماته من قاعدة البيانات بشكل كامل. لا يمكن استعادة البيانات بعد ذلك.`,
      confirmLabel: 'إتلاف نهائي',
    });
    if (!ok) return;
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
