'use client';

import { useCallback, useEffect, useState } from 'react';
import confetti from 'canvas-confetti';
import toast from 'react-hot-toast';
import { errorMessage } from '@/lib/error-utils';
import { readLocalCache, writeLocalCache } from '@/lib/local-cache';
import { createEmployee } from '@/features/employees/api';
import type { EmployeeFormValues } from '@/features/employees/types';
import { broadcastAnnouncement, fetchDashboardData, runDailyCleanup } from './api';
import type { AnnouncementTarget, DashboardData } from './types';

const CACHE_KEY = 'batra_cache_dashboard';
type DashboardCache = Partial<Omit<DashboardData, 'absentList'>>;

const EMPTY: DashboardData = {
  stats: {
    employees: 0, presentToday: 0, absentToday: 0, pendingLeaves: 0, pendingLoans: 0,
    pendingDevices: 0, securityIncidents: 0, totalStorageBytes: 0,
  },
  securityLogs: [], absentList: [], branches: [], departments: [], employeesList: [],
};

// عناصر الكاش القديمة قد تكون ناقصة؛ تُحذف الصفوف بلا معرّف
const withIds = <T extends { id?: string }>(rows: T[] | undefined) => (rows ?? []).filter(r => r && r.id);

/** حالة الرئيسية: الإحصاءات، الخروقات، الغياب، مع بث التعاميم والإضافة السريعة للموظفين. */
export function useDashboard() {
  const [loading, setLoading] = useState(true);
  const [data, setData] = useState<DashboardData>(EMPTY);
  const [actionLoading, setActionLoading] = useState(false);

  const load = useCallback(async () => {
    try {
      const fresh = await fetchDashboardData();
      setData(fresh);
      writeLocalCache<DashboardCache>(CACHE_KEY, {
        stats: fresh.stats, securityLogs: fresh.securityLogs,
        branches: fresh.branches, departments: fresh.departments, employeesList: fresh.employeesList,
      });
    } catch (err) {
      console.error(err);
      toast.error(`تعذر تحميل بيانات الرئيسية: ${errorMessage(err)}`);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    runDailyCleanup();
    const cached = readLocalCache<DashboardCache>(CACHE_KEY);
    if (cached) {
      // eslint-disable-next-line react-hooks/set-state-in-effect -- عرض الكاش فوراً قبل وصول البيانات
      setData(prev => ({
        ...prev,
        stats: cached.stats ?? prev.stats,
        securityLogs: withIds(cached.securityLogs),
        branches: withIds(cached.branches),
        departments: withIds(cached.departments),
        employeesList: withIds(cached.employeesList),
      }));
      setLoading(false);
    }
    void load();
  }, [load]);

  /** يرجع true عند الإرسال حتى تُغلق النافذة. */
  const postAnnouncement = async (target: AnnouncementTarget, text: string) => {
    if (!text.trim()) return false;
    if (target.type === 'branch' && !target.branchId) {
      toast.error('يرجى اختيار الفرع المستهدف أولاً');
      return false;
    }
    if (target.type === 'employee' && target.employeeIds.length === 0) {
      toast.error('يرجى اختيار موظف واحد على الأقل');
      return false;
    }
    setActionLoading(true);
    try {
      const sent = await broadcastAnnouncement(target, text);
      if (sent === 0) {
        toast('لم يتم العثور على موظفين مستهدفين لإرسال هذا التعميم');
        return false;
      }
      void confetti({ particleCount: 80, spread: 60, origin: { y: 0.8 } });
      toast.success('تم إرسال وبث التعميم الإداري بنجاح! 🚀');
      return true;
    } catch (err: unknown) {
      toast.error(`فشل إرسال التعميم: ${errorMessage(err)}`);
      return false;
    } finally {
      setActionLoading(false);
    }
  };

  /** يرجع null عند النجاح أو رسالة الخطأ لعرضها داخل النافذة. */
  const addEmployee = async (values: EmployeeFormValues, documents: File[]): Promise<string | null> => {
    setActionLoading(true);
    try {
      const { failedUploads } = await createEmployee(values, documents);
      void confetti({ particleCount: 100, spread: 80, colors: ['#0D9488', '#3B82F6'] });
      toast.success('تم إضافة الموظف الجديد وتوليد بياناته بنجاح! 🎉');
      if (failedUploads > 0) toast.error(`تعذر رفع ${failedUploads} من المستمسكات، يمكنك رفعها من صفحة الموظفين.`);
      void load();
      return null;
    } catch (err: unknown) {
      return errorMessage(err) || 'حدث خطأ أثناء الإضافة';
    } finally {
      setActionLoading(false);
    }
  };

  return { loading, ...data, actionLoading, postAnnouncement, addEmployee };
}
