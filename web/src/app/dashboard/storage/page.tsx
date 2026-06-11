'use client';

import React, { useState, useEffect } from 'react';
import { supabase } from '@/lib/supabase';
import { 
  HardDrive, 
  AlertTriangle, 
  RotateCcw, 
  Trash2, 
  RefreshCw,
  Loader2,
  PieChart,
  Server
} from 'lucide-react';
import confetti from 'canvas-confetti';

export default function StoragePage() {
  const [loading, setLoading] = useState(true);
  const [trashSizeBytes, setTrashSizeBytes] = useState(0);
  const [actionLoading, setActionLoading] = useState(false);

  const [avatarBytes, setAvatarBytes] = useState(0);
  const [documentBytes, setDocumentBytes] = useState(0);
  const [pledgeBytes, setPledgeBytes] = useState(0);
  const [otherBytes, setOtherBytes] = useState(0);
  const maxCapacityBytes = 3.0 * 1024 * 1024 * 1024; // Free Tier Limit: 3.0 GB

  useEffect(() => {
    fetchStorageStats();
  }, []);

  const fetchStorageStats = async () => {
    setLoading(true);
    try {
      const { data } = await supabase
        .from('deleted_files')
        .select('file_size_bytes')
        .is('restored_at', null);

      let totalTrash = 0;
      if (data) {
        data.forEach(row => {
          if (row.file_size_bytes) {
            totalTrash += Number(row.file_size_bytes);
          }
        });
      }
      setTrashSizeBytes(totalTrash);

      // Fetch actual storage buckets size
      const { data: statsData } = await supabase.rpc('get_storage_stats');
      
      let avatars = 0;
      let documents = 0;
      let pledges = 0;
      let others = 0;

      if (statsData) {
        statsData.forEach((stat: any) => {
          const bucket = stat.bucket_name;
          const size = Number(stat.total_size || 0);
          if (bucket === 'avatars') avatars += size;
          else if (bucket === 'documents') documents += size;
          else if (bucket === 'loan-pledges') pledges += size;
          else others += size;
        });
      }

      setAvatarBytes(avatars);
      setDocumentBytes(documents);
      setPledgeBytes(pledges);
      setOtherBytes(others);
    } catch (err) {
      console.error(err);
    } finally {
      setLoading(false);
    }
  };

  const handleEmptyTrash = async () => {
    if (!confirm('تحذير شديد! هل أنت متأكد من رغبتك في إفراغ سلة المحذوفات بالكامل وتطهير السحابة؟ سيتم مسح كافة الملفات الموجودة نهائياً ولن تتمكن من استعادتها أبداً.')) return;
    
    setActionLoading(true);
    try {
      // 1. Fetch all trash files to delete them from storage
      const { data: files } = await supabase
        .from('deleted_files')
        .select('*')
        .is('restored_at', null);

      if (files && files.length > 0) {
        for (const file of files) {
          const bucket = getBucketName(file.file_type);
          await supabase.storage.from(bucket).remove([file.file_path]);
        }
      }

      // 2. Delete all records from db
      const { error } = await supabase
        .from('deleted_files')
        .delete()
        .is('restored_at', null);

      if (error) throw error;

      setTrashSizeBytes(0);
      confetti({
        particleCount: 100,
        spread: 70,
        colors: ['#EF4444', '#F87171']
      });
      alert('تم إفراغ سلة المحذوفات بالكامل وتطهير المساحة السحابية! 🗑️');
    } catch (err: any) {
      alert(`فشل إفراغ السلة: ${err.message}`);
    } finally {
      setActionLoading(false);
    }
  };

  const getBucketName = (fileType: string) => {
    switch (fileType) {
      case 'avatar': return 'avatars';
      case 'document': return 'documents';
      case 'pledge': return 'loan-pledges';
      case 'logo': return 'company-logos';
      default: return 'documents';
    }
  };

  const formatBytes = (bytes: number) => {
    if (bytes < 1024) return `${bytes.toFixed(0)} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
    if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
    return `${(bytes / (1024 * 1024 * 1024)).toFixed(2)} GB`;
  };

  const totalUsedBytes = avatarBytes + documentBytes + pledgeBytes + otherBytes + trashSizeBytes;
  const usageRatio = totalUsedBytes / maxCapacityBytes;
  const usagePercentage = usageRatio * 100;
  const isWarning = usageRatio >= 0.8;

  const categories = [
    { name: 'المستندات والوثائق الرسمية', size: documentBytes, color: 'bg-teal-500', percentage: (documentBytes / totalUsedBytes) * 100 },
    { name: 'تعهدات السلف خطية الموقعة', size: pledgeBytes, color: 'bg-blue-500', percentage: (pledgeBytes / totalUsedBytes) * 100 },
    { name: 'الصور الشخصية (Avatars)', size: avatarBytes, color: 'bg-purple-500', percentage: (avatarBytes / totalUsedBytes) * 100 },
    { name: 'سلة المحذوفات مؤقتاً', size: trashSizeBytes, color: 'bg-rose-500', percentage: (trashSizeBytes / totalUsedBytes) * 100 },
    { name: 'أخرى والنسخ الاحتياطية للشركة', size: otherBytes, color: 'bg-amber-500', percentage: (otherBytes / totalUsedBytes) * 100 },
  ];

  if (loading) {
    return (
      <div className="flex-grow flex items-center justify-center">
        <Loader2 className="w-10 h-10 text-teal-400 animate-spin" />
      </div>
    );
  }

  return (
    <div className="space-y-8 pb-12">
      
      {/* Visual Analytics Box */}
      <div className="bg-slate-900/40 backdrop-blur-xl border border-slate-800/80 rounded-3xl p-8 shadow-xl">
        <div className="flex flex-col md:flex-row md:items-center justify-between gap-6 mb-8">
          <div>
            <h3 className="text-lg font-extrabold text-white flex items-center gap-2">
              <HardDrive className="w-5 h-5 text-teal-400" />
              <span>تحليلات ومساحات التخزين السحابي للمؤسسة</span>
            </h3>
            <p className="text-[11px] text-slate-400">إحصائيات المساحات المستهلكة من الباقة المجانية على خوادم Supabase Storage</p>
          </div>

          <button
            onClick={fetchStorageStats}
            className="flex items-center gap-2 py-2.5 px-4 bg-slate-800 hover:bg-slate-750 text-white rounded-xl text-xs font-bold transition-all border border-slate-700/60 cursor-pointer"
          >
            <RefreshCw className="w-4 h-4" />
            <span>تحديث المساحة المباشرة</span>
          </button>
        </div>

        {/* Big visual progress circle / bar */}
        <div className="space-y-6">
          <div className="flex justify-between items-end">
            <div>
              <span className="text-xs text-slate-400 block mb-1">المساحة الإجمالية المستهلكة</span>
              <span className={`text-4xl font-black ${isWarning ? 'text-rose-500' : 'text-teal-400'}`}>
                {formatBytes(totalUsedBytes)}
              </span>
              <span className="text-slate-500 text-xs font-medium mr-2">
                من أصل {formatBytes(maxCapacityBytes)} المتاحة
              </span>
            </div>
            <div className="text-right">
              <span className={`text-xl font-extrabold block ${isWarning ? 'text-rose-400' : 'text-teal-300'}`}>
                {usagePercentage.toFixed(1)}% مستهلك
              </span>
              <span className="text-[10px] text-slate-500 font-bold block mt-1">
                المتبقي: {formatBytes(maxCapacityBytes - totalUsedBytes)}
              </span>
            </div>
          </div>

          {/* Progress bar */}
          <div className="w-full h-4 bg-slate-950 rounded-full overflow-hidden flex">
            {categories.map((cat, i) => (
              <div 
                key={i} 
                className={`${cat.color} h-full transition-all duration-500`}
                style={{ width: `${(cat.size / maxCapacityBytes) * 100}%` }}
                title={`${cat.name}: ${formatBytes(cat.size)}`}
              />
            ))}
          </div>

          {/* Category distribution directory */}
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6 pt-6 border-t border-slate-900">
            {categories.map((cat, i) => (
              <div 
                key={i} 
                className="bg-slate-950/30 border border-slate-850 hover:border-slate-800 rounded-2xl p-4 flex items-center gap-4 transition-all"
              >
                <div className={`w-3.5 h-3.5 rounded-full shrink-0 ${cat.color}`} />
                <div className="flex-1 min-w-0">
                  <span className="text-xs font-bold text-white block truncate mb-1">{cat.name}</span>
                  <div className="flex justify-between items-center text-[10px] text-slate-400 font-bold">
                    <span>{formatBytes(cat.size)}</span>
                    <span className="font-mono">{cat.percentage.toFixed(1)}%</span>
                  </div>
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>

      {/* Warnings & Action control */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
        
        {/* Storage space warning */}
        <div className="lg:col-span-2 bg-slate-900/40 backdrop-blur-xl border border-slate-850 rounded-3xl p-6 flex items-start gap-4 shadow-xl">
          <div className={`p-3 rounded-2xl border shrink-0 ${isWarning ? 'bg-rose-500/10 border-rose-500/20 text-rose-400' : 'bg-teal-500/10 border-teal-500/20 text-teal-400'}`}>
            <AlertTriangle className="w-6 h-6 shrink-0" />
          </div>
          <div>
            <h4 className="font-extrabold text-sm text-white mb-2">
              {isWarning ? 'تحذير أمني: التخزين يوشك على الامتلاء! ⚠️' : 'حالة استقرار التخزين السحابي ممتازة ✅'}
            </h4>
            <p className="text-xs text-slate-400 leading-relaxed font-medium">
              {isWarning 
                ? 'لقد تجاوزت نسبة استهلاك المساحة السحابية 80%. يرجى إفراغ سلة المحذوفات أو تقليص أحجام الملفات وصور الهويات الشخصية لتفادي توقف استقبال وثائق وعقود وسلف الموظفين.'
                : 'مساحة تخزين خوادمك مستقرة وفي الحدود الآمنة تماماً. يوصى بإجراء مراجعة وتصفية دورية لسلة المحذوفات للحفاظ على أفضل أداء للأنظمة التفاعلية.'}
            </p>
          </div>
        </div>

        {/* Purge panel */}
        <div className="bg-slate-900/40 backdrop-blur-xl border border-slate-850 rounded-3xl p-6 shadow-xl flex flex-col justify-between">
          <div>
            <h4 className="font-extrabold text-sm text-white mb-2">إجراءات تصفية المساحة</h4>
            <p className="text-xs text-slate-400 mb-6">فك الضغط التخزيني وإتلاف الملفات المحذوفة فوراً</p>

            <button
              disabled={actionLoading || trashSizeBytes === 0}
              onClick={handleEmptyTrash}
              className="w-full flex items-center justify-center gap-2 py-4 px-4 bg-rose-500/10 hover:bg-rose-500/20 text-rose-400 hover:text-rose-300 border border-rose-500/20 hover:border-rose-500/30 rounded-2xl font-bold transition-all text-xs cursor-pointer disabled:opacity-40 disabled:pointer-events-none"
            >
              <Trash2 className="w-4.5 h-4.5" />
              <span>إفراغ سلة المحذوفات بالكامل 🗑️</span>
            </button>
          </div>

          <span className="text-[10px] text-slate-500 font-bold block mt-6 text-center">
            تطهير دائم لكافة الـ Buckets السحابية للملفات
          </span>
        </div>

      </div>

    </div>
  );
}
