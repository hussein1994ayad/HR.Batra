'use client';

import React, { useState, useEffect } from 'react';
import { supabase } from '@/lib/supabase';
import { 
  Trash2, 
  RotateCcw, 
  Trash, 
  AlertTriangle,
  Loader2,
  FileIcon,
  ShieldAlert,
  Clock
} from 'lucide-react';
import confetti from 'canvas-confetti';

export default function TrashPage() {
  const [loading, setLoading] = useState(true);
  const [deletedFiles, setDeletedFiles] = useState<any[]>([]);
  const [actionLoading, setActionLoading] = useState<string | null>(null);

  useEffect(() => {
    fetchDeletedFiles();
  }, []);

  const fetchDeletedFiles = async () => {
    setLoading(true);
    try {
      const { data, error } = await supabase
        .from('deleted_files')
        .select('*, employees(full_name)')
        .is('restored_at', null)
        .order('deleted_at', { ascending: false });

      if (data) setDeletedFiles(data);
    } catch (err) {
      console.error(err);
    } finally {
      setLoading(false);
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

  const getFileTypeNameArabic = (fileType: string) => {
    switch (fileType) {
      case 'avatar': return 'الصورة الشخصية';
      case 'document': return 'مستند رسمي';
      case 'pledge': return 'تعهد السلفة';
      case 'logo': return 'شعار الشركة';
      default: return 'ملف آخر';
    }
  };

  const formatBytes = (bytes: number) => {
    if (!bytes) return 'غير محدد';
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  };

  const handleRestoreFile = async (fileRow: any) => {
    setActionLoading(fileRow.id);
    try {
      const { error } = await supabase
        .from('deleted_files')
        .update({
          restored_at: new Date().toISOString(),
        })
        .eq('id', fileRow.id);

      if (error) throw error;

      // Filter locally
      setDeletedFiles(prev => prev.filter(f => f.id !== fileRow.id));

      confetti({
        particleCount: 50,
        spread: 40,
        colors: ['#0D9488', '#34D399']
      });

      alert('تم استعادة الملف بنجاح وإرجاعه لمساره الأصلي ✅');
    } catch (err: any) {
      alert(`فشل استعادة الملف: ${err.message}`);
    } finally {
      setActionLoading(null);
    }
  };

  const handlePermanentDelete = async (fileRow: any) => {
    if (!confirm('تحذير: هل أنت متأكد من رغبتك في حذف هذا الملف وإتلافه بشكل نهائي من الخادم؟ لا يمكن التراجع عن هذا الإجراء.')) return;
    
    setActionLoading(fileRow.id + '_delete');
    const bucket = getBucketName(fileRow.file_type);

    try {
      // 1. Delete from storage
      const { error: storeErr } = await supabase.storage
        .from(bucket)
        .remove([fileRow.file_path]);

      if (storeErr) throw storeErr;

      // 2. Delete row from DB
      const { error: dbErr } = await supabase
        .from('deleted_files')
        .delete()
        .eq('id', fileRow.id);

      if (dbErr) throw dbErr;

      // Filter locally
      setDeletedFiles(prev => prev.filter(f => f.id !== fileRow.id));

      alert('تم إتلاف وحذف الملف نهائياً وتصفية مساحته السحابية 🗑️');
    } catch (err: any) {
      alert(`فشل إتلاف الملف: ${err.message}`);
    } finally {
      setActionLoading(null);
    }
  };

  if (loading) {
    return (
      <div className="flex-grow flex items-center justify-center">
        <Loader2 className="w-10 h-10 text-teal-400 animate-spin" />
      </div>
    );
  }

  return (
    <div className="space-y-8 pb-12">
      <div className="bg-slate-900/40 backdrop-blur-xl border border-slate-800/80 rounded-3xl p-6 shadow-xl space-y-6">
        <div>
          <h3 className="text-lg font-extrabold text-white flex items-center gap-2">
            <Trash2 className="w-5 h-5 text-rose-500" />
            <span>سلة المحذوفات للملفات المحذوفة مؤقتاً</span>
          </h3>
          <p className="text-[11px] text-slate-400">يتم الاحتفاظ بالملفات المحذوفة هنا لمدة 30 يوماً من تاريخ الحذف لتسهيل استعادتها قبل إتلافها بالكامل تلقائياً</p>
        </div>

        {deletedFiles.length === 0 ? (
          <div className="h-64 flex flex-col items-center justify-center text-slate-500 text-xs">
            <Trash className="w-12 h-12 text-slate-600/30 mb-2 animate-bounce" />
            <span>سلة المحذوفات فارغة حالياً. كل التخزين نظيف! ✨</span>
          </div>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            {deletedFiles.map((file) => {
              const filename = file.file_path.split('/').pop() || 'ملف مجهول';
              const deletedBy = file.employees?.full_name || 'غير معروف';
              const expiryDate = new Date(file.scheduled_deletion_date);
              const daysLeft = Math.ceil((expiryDate.getTime() - new Date().getTime()) / (1000 * 3600 * 24));
              
              return (
                <div 
                  key={file.id} 
                  className="bg-slate-950/40 border border-slate-850 hover:border-slate-800 rounded-2xl p-5 flex flex-col justify-between"
                >
                  <div className="space-y-3">
                    <div className="flex items-center justify-between mb-2">
                      <div className="flex items-center gap-2 max-w-[70%]">
                        <FileIcon className="w-5 h-5 text-teal-400 shrink-0" />
                        <h4 className="text-xs font-bold text-white truncate" title={filename}>{filename}</h4>
                      </div>
                      <span className="text-[8px] font-bold text-rose-400 bg-rose-500/10 border border-rose-500/20 px-2 py-0.5 rounded-full">
                        متبقي {daysLeft} يوم
                      </span>
                    </div>

                    <div className="space-y-1.5 text-[10px] text-slate-400 border-b border-slate-900 pb-3">
                      <p>نوع المستند: <span className="text-slate-200">{getFileTypeNameArabic(file.file_type)}</span></p>
                      <p>الحجم الكلي: <span className="text-slate-200 font-mono">{formatBytes(file.file_size_bytes)}</span></p>
                      <p>حذف بواسطة: <span className="text-slate-200">{deletedBy}</span></p>
                    </div>

                    <div className="flex items-center gap-1.5 text-[10px] text-slate-500">
                      <Clock className="w-3.5 h-3.5 text-slate-600" />
                      <span>حُذف بتاريخ {new Date(file.deleted_at).toLocaleDateString('ar-IQ')}</span>
                    </div>
                  </div>

                  <div className="flex gap-2 pt-4 mt-4 border-t border-slate-900">
                    <button
                      disabled={actionLoading === file.id}
                      onClick={() => handleRestoreFile(file)}
                      className="flex-1 flex items-center justify-center gap-1 py-2 px-2 bg-teal-600 hover:bg-teal-500 text-white rounded-xl text-[10px] font-bold transition-colors cursor-pointer"
                    >
                      <RotateCcw className="w-3.5 h-3.5" />
                      <span>استعادة</span>
                    </button>
                    <button
                      disabled={actionLoading === file.id + '_delete'}
                      onClick={() => handlePermanentDelete(file)}
                      className="flex-1 flex items-center justify-center gap-1 py-2 px-2 bg-red-500/10 hover:bg-red-500/20 text-red-400 border border-red-500/20 rounded-xl text-[10px] font-bold transition-colors cursor-pointer"
                    >
                      <Trash className="w-3.5 h-3.5" />
                      <span>إتلاف نهائي</span>
                    </button>
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
}
