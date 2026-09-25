'use client';

import { useCallback, useEffect, useState } from 'react';
import confetti from 'canvas-confetti';
import toast from 'react-hot-toast';
import type { Announcement } from '@/lib/db-types';
import { errorMessage } from '@/lib/error-utils';
import {
  deleteAllAnnouncements, deleteAnnouncement, deleteWorkSchedule, fetchAnnouncements, fetchSettingsDataset,
  insertWorkSchedule, purgeMonthData, saveGeneralSettings, type SettingsDataset,
} from './api';
import { buildScheduleRow, purgeSummary } from './logic';
import type { GeneralSettings, PurgeOptions, ScheduleForm } from './types';

/** حالة صفحة الإعدادات: البيانات العامة، جداول الدوام، التعاميم، وأداة التنظيف. */
export function useSettings() {
  const [loading, setLoading] = useState(true);
  const [data, setData] = useState<SettingsDataset | null>(null);
  // يزداد بعد كل تحميل حتى يُعاد تهيئة نموذج الإعدادات بالقيم المحفوظة
  const [version, setVersion] = useState(0);
  const [saving, setSaving] = useState(false);
  const [loadingAnnouncements, setLoadingAnnouncements] = useState(false);

  const load = useCallback(async () => {
    try {
      setData(await fetchSettingsDataset());
      setVersion(v => v + 1);
    } catch (err) {
      console.error('Error fetching settings:', err);
      toast.error(`تعذر تحميل الإعدادات: ${errorMessage(err)}`);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect -- التحميل الأول للصفحة
    void load();
  }, [load]);

  const setAnnouncements = (announcements: Announcement[]) =>
    setData(prev => (prev ? { ...prev, announcements } : prev));

  const reloadAnnouncements = async () => {
    setLoadingAnnouncements(true);
    try {
      setAnnouncements(await fetchAnnouncements());
    } catch (err) {
      console.error('Error fetching announcements:', err);
    } finally {
      setLoadingAnnouncements(false);
    }
  };

  const saveGeneral = async (values: GeneralSettings) => {
    setSaving(true);
    try {
      await saveGeneralSettings(values);
      void confetti({ particleCount: 80, spread: 60, colors: ['#0D9488', '#10B981'] });
      toast.success('تم حفظ وتحديث إعدادات النظام والشركة بنجاح! ✅');
      await load();
    } catch (err: unknown) {
      toast.error(`فشل حفظ الإعدادات: ${errorMessage(err)}`);
    } finally {
      setSaving(false);
    }
  };

  /** يرجع true عند النجاح حتى يمسح النموذج اختياراته. */
  const purge = async (options: PurgeOptions) => {
    try {
      const result = await purgeMonthData(options);
      toast.success(purgeSummary(options, result));
      void confetti({ particleCount: 50, spread: 60, colors: ['#F59E0B', '#EF4444', '#10B981'] });
      return true;
    } catch (err: unknown) {
      console.error('Error during manual purge:', err);
      toast.error(`فشل تنفيذ عملية التنظيف: ${errorMessage(err) || 'خطأ غير معروف'}`);
      return false;
    }
  };

  const addSchedule = async (form: ScheduleForm) => {
    if (!form.name.trim()) {
      toast.error('يرجى إدخال اسم لجدول الدوام');
      return false;
    }
    if (!form.targetId) {
      toast.error('يرجى تحديد الجهة المستهدفة (الفرع/القسم/الموظف)');
      return false;
    }
    try {
      await insertWorkSchedule(buildScheduleRow(form));
      toast.success('تم إضافة جدول الدوام بنجاح! 📅');
      await load();
      return true;
    } catch (err: unknown) {
      toast.error(`فشل إضافة الجدول: ${errorMessage(err)}`);
      return false;
    }
  };

  const removeSchedule = async (id: string) => {
    if (!confirm('هل أنت متأكد من رغبتك في حذف جدول الدوام هذا؟ 🗑️')) return;
    try {
      await deleteWorkSchedule(id);
      toast.success('تم حذف جدول الدوام بنجاح! ✅');
      await load();
    } catch (err: unknown) {
      toast.error(`فشل حذف الجدول: ${errorMessage(err)}`);
    }
  };

  const removeAnnouncement = async (id: string) => {
    if (!confirm('هل أنت متأكد من رغبتك في حذف هذا التعميم نهائياً من أرشيف لوحة الإعلانات؟ 🗑️')) return;
    try {
      await deleteAnnouncement(id);
      toast.success('تم حذف التعميم بنجاح! ✅');
      await reloadAnnouncements();
    } catch (err: unknown) {
      toast.error(`فشل حذف التعميم: ${errorMessage(err)}`);
    }
  };

  const removeAllAnnouncements = async () => {
    if (!confirm('تحذير: هل أنت متأكد من رغبتك في مسح وإخلاء كافة التعميمات من الأرشيف؟ ⚠️ لا يمكن التراجع عن هذا الإجراء!')) return;
    try {
      await deleteAllAnnouncements();
      toast.success('تم إخلاء أرشيف التعميمات بنجاح! 🧹');
      await reloadAnnouncements();
    } catch (err: unknown) {
      toast.error(`فشل إخلاء الأرشيف: ${errorMessage(err)}`);
    }
  };

  return {
    loading, data, version, saving, loadingAnnouncements,
    saveGeneral, purge, addSchedule, removeSchedule, removeAnnouncement, removeAllAnnouncements,
  };
}
