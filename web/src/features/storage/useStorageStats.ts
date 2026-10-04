'use client';

// حالة صفحة التخزين: التحميل والتحديث، إفراغ السلة، والنسب المحسوبة (تحذير عند 80%).

import { useEffect, useState } from 'react';
import confetti from 'canvas-confetti';
import toast from 'react-hot-toast';
import { errorMessage } from '@/lib/error-utils';
import { emptyTrash, fetchStorageStats } from './api';
import { MAX_DB_BYTES, MAX_STORAGE_BYTES, type TableSizeRow } from './logic';

export function useStorageStats() {
  const [loading, setLoading] = useState(true);
  const [trashSizeBytes, setTrashSizeBytes] = useState(0);
  const [actionLoading, setActionLoading] = useState(false);

  // Storage Buckets
  const [avatarBytes, setAvatarBytes] = useState(0);
  const [documentBytes, setDocumentBytes] = useState(0);
  const [pledgeBytes, setPledgeBytes] = useState(0);
  const [otherBytes, setOtherBytes] = useState(0);

  // Database
  const [dbSizeBytes, setDbSizeBytes] = useState(0);
  const [tableSizes, setTableSizes] = useState<TableSizeRow[]>([]);

  const maxStorageBytes = MAX_STORAGE_BYTES;
  const maxDbBytes = MAX_DB_BYTES;

  const fetchAllStats = async () => {
    setLoading(true);
    try {
      const stats = await fetchStorageStats();
      setTrashSizeBytes(stats.trashBytes);
      setAvatarBytes(stats.avatars);
      setDocumentBytes(stats.documents);
      setPledgeBytes(stats.pledges);
      setOtherBytes(stats.others);
      if (stats.dbSizeBytes !== null) setDbSizeBytes(stats.dbSizeBytes);
      if (stats.tableSizes) setTableSizes(stats.tableSizes);
    } catch (err) {
      console.error(err);
      toast.error('فشل في تحميل بيانات التخزين');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect -- جلب الإحصائيات عند فتح الصفحة
    fetchAllStats();
  }, []);

  const handleEmptyTrash = async () => {
    if (!confirm('تحذير شديد! هل أنت متأكد من رغبتك في إفراغ سلة المحذوفات بالكامل وتطهير السحابة؟ سيتم مسح كافة الملفات الموجودة نهائياً ولن تتمكن من استعادتها أبداً.')) return;

    setActionLoading(true);
    try {
      await emptyTrash();
      setTrashSizeBytes(0);
      confetti({ particleCount: 100, spread: 70, colors: ['#EF4444', '#F87171'] });
      toast('تم إفراغ سلة المحذوفات بالكامل وتطهير المساحة السحابية! 🗑️');
    } catch (err: unknown) {
      toast.error(`فشل إفراغ السلة: ${errorMessage(err)}`);
    } finally {
      setActionLoading(false);
    }
  };

  const totalStorageBytes = avatarBytes + documentBytes + pledgeBytes + otherBytes + trashSizeBytes;
  const storageUsagePercent = (totalStorageBytes / maxStorageBytes) * 100;
  const dbUsagePercent = (dbSizeBytes / maxDbBytes) * 100;
  const isStorageWarning = storageUsagePercent >= 80;
  const isDbWarning = dbUsagePercent >= 80;

  // Total combined usage for the grand summary
  const totalCombinedBytes = totalStorageBytes + dbSizeBytes;
  const maxCombinedBytes = maxStorageBytes + maxDbBytes;
  const combinedUsagePercent = (totalCombinedBytes / maxCombinedBytes) * 100;

  // Tables grouped by total bytes for the bar chart
  const totalTableBytes = tableSizes.reduce((sum, t) => sum + t.total_bytes, 0);

  const storageCategories = [
    { name: 'المستندات والوثائق', size: documentBytes, color: 'bg-teal-500' },
    { name: 'تعهدات السلف', size: pledgeBytes, color: 'bg-blue-500' },
    { name: 'الصور الشخصية', size: avatarBytes, color: 'bg-purple-500' },
    { name: 'سلة المحذوفات', size: trashSizeBytes, color: 'bg-rose-500' },
    { name: 'ملفات أخرى', size: otherBytes, color: 'bg-amber-500' },
  ];

  return {
    loading, actionLoading, trashSizeBytes, dbSizeBytes, tableSizes, maxStorageBytes, maxDbBytes,
    fetchAllStats, handleEmptyTrash,
    totalStorageBytes, storageUsagePercent, dbUsagePercent, isStorageWarning, isDbWarning,
    totalCombinedBytes, maxCombinedBytes, combinedUsagePercent, totalTableBytes, storageCategories,
  };
}

export type StorageState = ReturnType<typeof useStorageStats>;
