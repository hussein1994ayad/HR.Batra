'use client';

import { useCallback, useEffect, useState } from 'react';
import confetti from 'canvas-confetti';
import toast from 'react-hot-toast';
import type { AttendanceRecord, Branch } from '@/lib/db-types';
import { errorMessage } from '@/lib/error-utils';
import { readLocalCache, writeLocalCache } from '@/lib/local-cache';
import { createBranch, deleteBranch, fetchBranches, fetchTodayAttendance, updateBranch, type BranchInput } from './api';
import { BAGHDAD } from './logic';

const CACHE_KEY = 'batra_cache_geofences';
type GeofencesCache = { branches?: Branch[]; todayLogs?: AttendanceRecord[] };

/** حالة صفحة الفروع: القائمة، بصمات اليوم، الفرع المحدد وتركيز الخريطة، والإجراءات. */
export function useGeofences() {
  const [loading, setLoading] = useState(true);
  const [branches, setBranches] = useState<Branch[]>([]);
  const [todayLogs, setTodayLogs] = useState<AttendanceRecord[]>([]);
  const [actionLoading, setActionLoading] = useState<string | null>(null);
  const [selectedBranchId, setSelectedBranchId] = useState<string | null>(null);
  const [mapView, setMapView] = useState<{ center: [number, number]; zoom: number }>({
    center: [BAGHDAD.lat, BAGHDAD.lng], zoom: 12,
  });

  const loadBranches = useCallback(async () => {
    try {
      const data = await fetchBranches();
      setBranches(data);
      writeLocalCache<GeofencesCache>(CACHE_KEY, { branches: data });
    } catch (err) {
      console.error(err);
      toast.error(`تعذر تحميل الفروع: ${errorMessage(err)}`);
    } finally {
      setLoading(false);
    }
  }, []);

  const loadTodayLogs = useCallback(async () => {
    try {
      const data = await fetchTodayAttendance();
      setTodayLogs(data);
      writeLocalCache<GeofencesCache>(CACHE_KEY, { todayLogs: data });
    } catch (err) {
      console.error('Error fetching today attendance:', err);
    }
  }, []);

  useEffect(() => {
    const cached = readLocalCache<GeofencesCache>(CACHE_KEY);
    if (cached) {
      // eslint-disable-next-line react-hooks/set-state-in-effect -- عرض الكاش فوراً قبل وصول البيانات
      setBranches(cached.branches ?? []);
      setTodayLogs(cached.todayLogs ?? []);
      setLoading(false);
    }
    void loadBranches();
    void loadTodayLogs();
  }, [loadBranches, loadTodayLogs]);

  const focus = (lat: number, lng: number) => setMapView({ center: [lat, lng], zoom: 16 });

  const selectBranch = (branchId: string) => {
    setSelectedBranchId(branchId);
    const branch = branches.find(b => b.id === branchId);
    if (branch?.latitude && branch.longitude) focus(branch.latitude, branch.longitude);
  };

  const run = async (key: string, action: () => Promise<void>, success: string, failure?: string) => {
    setActionLoading(key);
    try {
      await action();
      toast.success(success);
      return true;
    } catch (err: unknown) {
      const message = errorMessage(err) || 'حدث خطأ غير متوقع';
      toast.error(failure ? `${failure}: ${message}` : message);
      return false;
    } finally {
      setActionLoading(null);
    }
  };

  const addBranch = (input: BranchInput) =>
    run('create', async () => {
      await createBranch(input);
      await loadBranches();
      void confetti({ particleCount: 100, spread: 80, colors: ['#0D9488', '#3B82F6'] });
    }, 'تم إضافة الفرع الجغرافي الجديد ورسم حدود بصمته بنجاح! 🏢');

  const editBranch = (id: string, input: BranchInput) =>
    run('update', async () => {
      await updateBranch(id, input);
      await loadBranches();
      if (selectedBranchId === id) focus(input.latitude, input.longitude);
      void confetti({ particleCount: 80, spread: 60, colors: ['#0D9488', '#00FF66'] });
    }, 'تم تحديث بيانات الفرع ونطاق البصمة بنجاح! 💾');

  const removeBranch = (id: string) => {
    if (!confirm('تحذير: هل أنت متأكد من رغبتك في حذف هذا الفرع الجغرافي بالكامل؟ سيؤدي هذا لإلغاء تبعية الموظفين المربوطين به وقد يؤثر على صلاحية تبصيم الحضور.')) return;
    return run(id + '_delete', async () => {
      await deleteBranch(id);
      setBranches(prev => prev.filter(b => b.id !== id));
      if (selectedBranchId === id) setSelectedBranchId(null);
    }, 'تم حذف الفرع الجغرافي ونطاق البصمة الخاص به بنجاح 🗑️', 'فشل حذف الفرع');
  };

  return {
    loading, branches, todayLogs, actionLoading, selectedBranchId, mapView,
    selectBranch, addBranch, editBranch, removeBranch,
  };
}
