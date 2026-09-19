'use client';

import React, { useState, useEffect } from 'react';
import { supabase } from '@/lib/supabase';
import { 
  HardDrive, 
  AlertTriangle, 
  Trash2, 
  RefreshCw,
  Loader2,
  Database,
  Cloud,
  Table2,
  ArrowDownUp,
  Info,
  ShieldCheck,
  TrendingUp,
  Gauge
} from 'lucide-react';
import confetti from 'canvas-confetti';
import toast from 'react-hot-toast';

interface TableSizeRow {
  table_name: string;
  row_count: number;
  total_bytes: number;
  pretty_size: string;
}

// Arabic-friendly names for tables
const TABLE_LABELS: Record<string, string> = {
  employees: 'الموظفين',
  attendance: 'الحضور والغياب',
  salary_slips: 'كشوف الرواتب',
  loans: 'السلف والقروض',
  loan_installments: 'أقساط السلف',
  leave_requests: 'طلبات الإجازات',
  leave_balances: 'أرصدة الإجازات',
  notifications: 'الإشعارات',
  location_tracking: 'تتبع المواقع GPS',
  tracked_stops: 'الوقفات المرصودة',
  geofence_violations: 'مخالفات السياج الجغرافي',
  geofence_zones: 'مناطق السياج الجغرافي',
  employee_geofence_assignments: 'تعيينات السياج للموظفين',
  mock_gps_attempts: 'محاولات GPS المزيف',
  departments: 'الأقسام',
  branches: 'الفروع',
  branch_schedules: 'جداول الفروع',
  work_schedules: 'جداول العمل',
  tracking_schedules: 'جداول التتبع',
  company_settings: 'إعدادات الشركة',
  system_settings: 'إعدادات النظام',
  announcements: 'الإعلانات',
  bonuses_deductions: 'المكافآت والخصومات',
  documents: 'المستندات',
  deleted_files: 'الملفات المحذوفة',
  archived_employees: 'الموظفين المؤرشفين',
  archived_months: 'الأشهر المؤرشفة',
  fcm_tokens: 'رموز الإشعارات FCM',
  device_tokens: 'رموز الأجهزة',
  employee_devices: 'أجهزة الموظفين',
  app_versions: 'إصدارات التطبيق',
};

// Color assignment based on table category
const getTableColor = (name: string): string => {
  if (['location_tracking', 'tracked_stops', 'geofence_violations', 'mock_gps_attempts', 'geofence_zones', 'employee_geofence_assignments'].includes(name)) return 'bg-red-500';
  if (['attendance'].includes(name)) return 'bg-amber-500';
  if (['notifications', 'announcements'].includes(name)) return 'bg-blue-500';
  if (['salary_slips', 'loans', 'loan_installments', 'bonuses_deductions'].includes(name)) return 'bg-emerald-500';
  if (['employees', 'employee_devices', 'departments', 'branches'].includes(name)) return 'bg-purple-500';
  if (['leave_requests', 'leave_balances'].includes(name)) return 'bg-cyan-500';
  return 'bg-slate-500';
};

const getTableDotColor = (name: string): string => {
  if (['location_tracking', 'tracked_stops', 'geofence_violations', 'mock_gps_attempts', 'geofence_zones', 'employee_geofence_assignments'].includes(name)) return 'bg-red-400';
  if (['attendance'].includes(name)) return 'bg-amber-400';
  if (['notifications', 'announcements'].includes(name)) return 'bg-blue-400';
  if (['salary_slips', 'loans', 'loan_installments', 'bonuses_deductions'].includes(name)) return 'bg-emerald-400';
  if (['employees', 'employee_devices', 'departments', 'branches'].includes(name)) return 'bg-purple-400';
  if (['leave_requests', 'leave_balances'].includes(name)) return 'bg-cyan-400';
  return 'bg-slate-400';
};

export default function StoragePage() {
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

  // Supabase Free Tier limits
  const maxStorageBytes = 1.0 * 1024 * 1024 * 1024; // 1 GB Storage
  const maxDbBytes = 500 * 1024 * 1024; // 500 MB Database

  useEffect(() => {
    fetchAllStats();
  }, []);

  const fetchAllStats = async () => {
    setLoading(true);
    try {
      // Parallel fetch for all data
      const [trashResult, storageResult, dbSizeResult, tableSizesResult] = await Promise.all([
        supabase.from('deleted_files').select('file_size_bytes').is('restored_at', null),
        supabase.rpc('get_storage_stats'),
        supabase.rpc('get_database_size'),
        supabase.rpc('get_database_table_sizes'),
      ]);

      // Trash
      let totalTrash = 0;
      if (trashResult.data) {
        trashResult.data.forEach(row => {
          if (row.file_size_bytes) totalTrash += Number(row.file_size_bytes);
        });
      }
      setTrashSizeBytes(totalTrash);

      // Buckets
      let avatars = 0, documents = 0, pledges = 0, others = 0;
      if (storageResult.data) {
        storageResult.data.forEach((stat: any) => {
          const bucket = stat.bucket_name;
          const size = Number(stat.total_size || 0);
          if (bucket === 'avatars') avatars += size;
          else if (bucket === 'employee-documents') documents += size;
          else if (bucket === 'loan-pledges') pledges += size;
          else others += size;
        });
      }
      setAvatarBytes(avatars);
      setDocumentBytes(documents);
      setPledgeBytes(pledges);
      setOtherBytes(others);

      // Database size
      if (dbSizeResult.data && dbSizeResult.data[0]) {
        setDbSizeBytes(Number(dbSizeResult.data[0].db_size || 0));
      }

      // Table sizes
      if (tableSizesResult.data) {
        setTableSizes(tableSizesResult.data as TableSizeRow[]);
      }
    } catch (err) {
      console.error(err);
      toast.error('فشل في تحميل بيانات التخزين');
    } finally {
      setLoading(false);
    }
  };

  const handleEmptyTrash = async () => {
    if (!confirm('تحذير شديد! هل أنت متأكد من رغبتك في إفراغ سلة المحذوفات بالكامل وتطهير السحابة؟ سيتم مسح كافة الملفات الموجودة نهائياً ولن تتمكن من استعادتها أبداً.')) return;
    
    setActionLoading(true);
    try {
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

      const { error } = await supabase
        .from('deleted_files')
        .delete()
        .is('restored_at', null);

      if (error) throw error;

      setTrashSizeBytes(0);
      confetti({ particleCount: 100, spread: 70, colors: ['#EF4444', '#F87171'] });
      toast('تم إفراغ سلة المحذوفات بالكامل وتطهير المساحة السحابية! 🗑️');
    } catch (err: any) {
      toast.error(`فشل إفراغ السلة: ${err.message}`);
    } finally {
      setActionLoading(false);
    }
  };

  const getBucketName = (fileType: string) => {
    switch (fileType) {
      case 'avatar': return 'avatars';
      case 'document': return 'employee-documents';
      case 'pledge': return 'loan-pledges';
      case 'logo': return 'company-logos';
      default: return 'employee-documents';
    }
  };

  const formatBytes = (bytes: number) => {
    if (bytes < 1024) return `${bytes.toFixed(0)} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
    if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
    return `${(bytes / (1024 * 1024 * 1024)).toFixed(2)} GB`;
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

  if (loading) {
    return (
      <div className="flex-grow flex items-center justify-center">
        <Loader2 className="w-10 h-10 text-teal-400 animate-spin" />
      </div>
    );
  }

  return (
    <div className="space-y-8 pb-12" dir="rtl">
      
      {/* Grand Summary Header */}
      <div className="bg-gradient-to-br from-slate-900/60 via-slate-900/40 to-slate-950/60 backdrop-blur-xl border border-slate-800/80 rounded-3xl p-8 shadow-xl">
        <div className="flex flex-col md:flex-row md:items-center justify-between gap-6 mb-8">
          <div>
            <h3 className="text-lg font-extrabold text-white flex items-center gap-2">
              <Gauge className="w-5 h-5 text-teal-400" />
              <span>لوحة تحليلات التخزين الشاملة — Supabase</span>
            </h3>
            <p className="text-[11px] text-slate-400 mt-1">عرض لحظي لكل شيء يستهلك مساحة من خوادم Supabase (قاعدة البيانات + التخزين السحابي للملفات)</p>
          </div>

          <button
            onClick={fetchAllStats}
            className="flex items-center gap-2 py-2.5 px-5 bg-slate-800 hover:bg-slate-750 text-white rounded-xl text-xs font-bold transition-all border border-slate-700/60 cursor-pointer active:scale-95"
          >
            <RefreshCw className="w-4 h-4" />
            <span>تحديث لحظي</span>
          </button>
        </div>

        {/* Two main gauges: Database + Storage side by side */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-8">

          {/* Database Gauge */}
          <div className="bg-slate-950/50 border border-slate-850 rounded-2xl p-6 space-y-4">
            <div className="flex items-center gap-2 mb-2">
              <Database className="w-5 h-5 text-violet-400" />
              <h4 className="text-sm font-extrabold text-white">قاعدة البيانات (Database)</h4>
              <span className="mr-auto text-[10px] text-slate-500 font-bold">الحد الأقصى: {formatBytes(maxDbBytes)}</span>
            </div>
            <div className="flex items-end justify-between">
              <div>
                <span className={`text-3xl font-black ${isDbWarning ? 'text-rose-400' : 'text-violet-400'}`}>
                  {formatBytes(dbSizeBytes)}
                </span>
                <span className="text-slate-500 text-xs font-bold mr-2">مستهلك</span>
              </div>
              <div className="text-left">
                <span className={`text-lg font-extrabold ${isDbWarning ? 'text-rose-400' : 'text-violet-300'}`}>
                  {dbUsagePercent.toFixed(1)}%
                </span>
                <span className="block text-[10px] text-slate-500 font-bold">
                  المتبقي: {formatBytes(maxDbBytes - dbSizeBytes)}
                </span>
              </div>
            </div>
            <div className="w-full h-3 bg-slate-900 rounded-full overflow-hidden">
              <div 
                className={`h-full rounded-full transition-all duration-700 ${isDbWarning ? 'bg-gradient-to-l from-rose-500 to-rose-600' : 'bg-gradient-to-l from-violet-500 to-violet-600'}`}
                style={{ width: `${Math.min(dbUsagePercent, 100)}%` }}
              />
            </div>
          </div>

          {/* Storage Gauge */}
          <div className="bg-slate-950/50 border border-slate-850 rounded-2xl p-6 space-y-4">
            <div className="flex items-center gap-2 mb-2">
              <Cloud className="w-5 h-5 text-teal-400" />
              <h4 className="text-sm font-extrabold text-white">التخزين السحابي (Storage Buckets)</h4>
              <span className="mr-auto text-[10px] text-slate-500 font-bold">الحد الأقصى: {formatBytes(maxStorageBytes)}</span>
            </div>
            <div className="flex items-end justify-between">
              <div>
                <span className={`text-3xl font-black ${isStorageWarning ? 'text-rose-400' : 'text-teal-400'}`}>
                  {formatBytes(totalStorageBytes)}
                </span>
                <span className="text-slate-500 text-xs font-bold mr-2">مستهلك</span>
              </div>
              <div className="text-left">
                <span className={`text-lg font-extrabold ${isStorageWarning ? 'text-rose-400' : 'text-teal-300'}`}>
                  {storageUsagePercent.toFixed(1)}%
                </span>
                <span className="block text-[10px] text-slate-500 font-bold">
                  المتبقي: {formatBytes(maxStorageBytes - totalStorageBytes)}
                </span>
              </div>
            </div>
            <div className="w-full h-3 bg-slate-900 rounded-full overflow-hidden">
              <div 
                className={`h-full rounded-full transition-all duration-700 ${isStorageWarning ? 'bg-gradient-to-l from-rose-500 to-rose-600' : 'bg-gradient-to-l from-teal-500 to-teal-600'}`}
                style={{ width: `${Math.min(storageUsagePercent, 100)}%` }}
              />
            </div>
          </div>
        </div>

        {/* Grand total bar */}
        <div className="mt-6 bg-slate-950/40 border border-slate-850 rounded-2xl p-5">
          <div className="flex items-center justify-between mb-3">
            <div className="flex items-center gap-2">
              <TrendingUp className="w-4 h-4 text-amber-400" />
              <span className="text-xs font-extrabold text-white">إجمالي الاستهلاك الكلي من Supabase</span>
            </div>
            <span className="text-xs font-bold text-slate-400">
              {formatBytes(totalCombinedBytes)} من {formatBytes(maxCombinedBytes)}
            </span>
          </div>
          <div className="w-full h-4 bg-slate-900 rounded-full overflow-hidden flex">
            {/* DB portion */}
            <div 
              className="bg-gradient-to-l from-violet-500 to-violet-600 h-full transition-all duration-700"
              style={{ width: `${(dbSizeBytes / maxCombinedBytes) * 100}%` }}
              title={`قاعدة البيانات: ${formatBytes(dbSizeBytes)}`}
            />
            {/* Storage portion */}
            <div 
              className="bg-gradient-to-l from-teal-500 to-teal-600 h-full transition-all duration-700"
              style={{ width: `${(totalStorageBytes / maxCombinedBytes) * 100}%` }}
              title={`التخزين السحابي: ${formatBytes(totalStorageBytes)}`}
            />
          </div>
          <div className="flex items-center gap-6 mt-3 text-[10px] font-bold text-slate-500">
            <span className="flex items-center gap-1.5"><span className="w-2.5 h-2.5 rounded-full bg-violet-500 inline-block" /> قاعدة البيانات ({formatBytes(dbSizeBytes)})</span>
            <span className="flex items-center gap-1.5"><span className="w-2.5 h-2.5 rounded-full bg-teal-500 inline-block" /> التخزين السحابي ({formatBytes(totalStorageBytes)})</span>
            <span className="mr-auto">استهلاك {combinedUsagePercent.toFixed(2)}% — المتبقي {formatBytes(maxCombinedBytes - totalCombinedBytes)}</span>
          </div>
        </div>
      </div>

      {/* Database Tables Breakdown */}
      <div className="bg-slate-900/40 backdrop-blur-xl border border-slate-800/80 rounded-3xl p-8 shadow-xl">
        <div className="flex items-center gap-2 mb-6">
          <Table2 className="w-5 h-5 text-violet-400" />
          <h3 className="text-sm font-extrabold text-white">تفصيل جداول قاعدة البيانات — كل جدول وشقد ماخذ</h3>
          <span className="mr-auto text-[10px] text-slate-500 font-bold flex items-center gap-1">
            <ArrowDownUp className="w-3 h-3" /> مرتب من الأكبر للأصغر
          </span>
        </div>

        <div className="space-y-2">
          {tableSizes.map((table, i) => {
            const pctOfDb = totalTableBytes > 0 ? (table.total_bytes / totalTableBytes) * 100 : 0;
            const label = TABLE_LABELS[table.table_name] || table.table_name;
            const barColor = getTableColor(table.table_name);
            const dotColor = getTableDotColor(table.table_name);

            return (
              <div 
                key={table.table_name}
                className="bg-slate-950/30 border border-slate-850 hover:border-slate-800 rounded-xl p-3.5 transition-all group"
              >
                <div className="flex items-center gap-3">
                  <span className="text-[10px] text-slate-600 font-mono w-5 text-center shrink-0">{i + 1}</span>
                  <span className={`w-2.5 h-2.5 rounded-full shrink-0 ${dotColor}`} />
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center justify-between mb-1.5">
                      <div className="flex items-center gap-2 min-w-0">
                        <span className="text-xs font-bold text-white truncate">{label}</span>
                        <span className="text-[9px] text-slate-600 font-mono hidden sm:inline">({table.table_name})</span>
                      </div>
                      <div className="flex items-center gap-4 shrink-0">
                        <span className="text-[10px] text-slate-500 font-bold">{table.row_count.toLocaleString()} سجل</span>
                        <span className="text-xs font-extrabold text-white min-w-[60px] text-left">{table.pretty_size}</span>
                        <span className="text-[10px] font-mono text-slate-600 min-w-[45px] text-left">{pctOfDb.toFixed(1)}%</span>
                      </div>
                    </div>
                    <div className="w-full h-1.5 bg-slate-900 rounded-full overflow-hidden">
                      <div 
                        className={`h-full rounded-full transition-all duration-500 ${barColor}`}
                        style={{ width: `${Math.max(pctOfDb, 0.5)}%` }}
                      />
                    </div>
                  </div>
                </div>
              </div>
            );
          })}
        </div>

        <div className="flex items-center justify-between mt-4 pt-4 border-t border-slate-850 text-xs font-bold">
          <span className="text-slate-400">إجمالي جميع الجداول:</span>
          <span className="text-white">{formatBytes(totalTableBytes)} ({tableSizes.length} جدول)</span>
        </div>
      </div>

      {/* Storage Buckets Breakdown */}
      <div className="bg-slate-900/40 backdrop-blur-xl border border-slate-800/80 rounded-3xl p-8 shadow-xl">
        <div className="flex items-center gap-2 mb-6">
          <Cloud className="w-5 h-5 text-teal-400" />
          <h3 className="text-sm font-extrabold text-white">تفصيل الملفات والتخزين السحابي (Storage Buckets)</h3>
        </div>

        {/* Bucket category bar */}
        <div className="w-full h-4 bg-slate-950 rounded-full overflow-hidden flex mb-6">
          {storageCategories.map((cat, i) => (
            <div 
              key={i} 
              className={`${cat.color} h-full transition-all duration-500`}
              style={{ width: totalStorageBytes > 0 ? `${(cat.size / maxStorageBytes) * 100}%` : '0%' }}
              title={`${cat.name}: ${formatBytes(cat.size)}`}
            />
          ))}
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {storageCategories.map((cat, i) => (
            <div 
              key={i} 
              className="bg-slate-950/30 border border-slate-850 hover:border-slate-800 rounded-2xl p-4 flex items-center gap-4 transition-all"
            >
              <div className={`w-3.5 h-3.5 rounded-full shrink-0 ${cat.color}`} />
              <div className="flex-1 min-w-0">
                <span className="text-xs font-bold text-white block truncate mb-1">{cat.name}</span>
                <div className="flex justify-between items-center text-[10px] text-slate-400 font-bold">
                  <span>{formatBytes(cat.size)}</span>
                  <span className="font-mono">{totalStorageBytes > 0 ? ((cat.size / totalStorageBytes) * 100).toFixed(1) : '0.0'}%</span>
                </div>
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* Warnings & Actions */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
        
        {/* Status */}
        <div className="lg:col-span-2 space-y-4">
          {/* DB warning */}
          <div className={`bg-slate-900/40 backdrop-blur-xl border rounded-2xl p-5 flex items-start gap-4 shadow-xl ${isDbWarning ? 'border-rose-500/30' : 'border-slate-850'}`}>
            <div className={`p-2.5 rounded-xl border shrink-0 ${isDbWarning ? 'bg-rose-500/10 border-rose-500/20 text-rose-400' : 'bg-violet-500/10 border-violet-500/20 text-violet-400'}`}>
              <Database className="w-5 h-5 shrink-0" />
            </div>
            <div>
              <h4 className="font-extrabold text-xs text-white mb-1">
                {isDbWarning ? '⚠️ تحذير: قاعدة البيانات تقترب من الحد الأقصى!' : '✅ قاعدة البيانات مستقرة'}
              </h4>
              <p className="text-[11px] text-slate-400 leading-relaxed">
                {isDbWarning 
                  ? `استهلاك قاعدة البيانات وصل ${dbUsagePercent.toFixed(1)}%. استخدم أداة تنظيف البيانات في الإعدادات لحذف سجلات التتبع والحضور القديمة بعد اعتماد الرواتب.`
                  : `قاعدة البيانات تستهلك ${dbUsagePercent.toFixed(1)}% فقط (${formatBytes(dbSizeBytes)} من ${formatBytes(maxDbBytes)}). المتبقي ${formatBytes(maxDbBytes - dbSizeBytes)}.`}
              </p>
            </div>
          </div>

          {/* Storage warning */}
          <div className={`bg-slate-900/40 backdrop-blur-xl border rounded-2xl p-5 flex items-start gap-4 shadow-xl ${isStorageWarning ? 'border-rose-500/30' : 'border-slate-850'}`}>
            <div className={`p-2.5 rounded-xl border shrink-0 ${isStorageWarning ? 'bg-rose-500/10 border-rose-500/20 text-rose-400' : 'bg-teal-500/10 border-teal-500/20 text-teal-400'}`}>
              <Cloud className="w-5 h-5 shrink-0" />
            </div>
            <div>
              <h4 className="font-extrabold text-xs text-white mb-1">
                {isStorageWarning ? '⚠️ تحذير: التخزين السحابي يوشك على الامتلاء!' : '✅ التخزين السحابي مستقر'}
              </h4>
              <p className="text-[11px] text-slate-400 leading-relaxed">
                {isStorageWarning 
                  ? 'لقد تجاوزت نسبة استهلاك التخزين 80%. يرجى إفراغ سلة المحذوفات وتقليل أحجام الملفات.'
                  : `التخزين السحابي يستهلك ${storageUsagePercent.toFixed(1)}% فقط (${formatBytes(totalStorageBytes)} من ${formatBytes(maxStorageBytes)}). المتبقي ${formatBytes(maxStorageBytes - totalStorageBytes)}.`}
              </p>
            </div>
          </div>

          {/* Info box */}
          <div className="bg-slate-900/40 backdrop-blur-xl border border-slate-850 rounded-2xl p-5 flex items-start gap-4 shadow-xl">
            <div className="p-2.5 rounded-xl bg-amber-500/10 border border-amber-500/20 text-amber-400 shrink-0">
              <Info className="w-5 h-5" />
            </div>
            <div>
              <h4 className="font-extrabold text-xs text-white mb-1">💡 نصيحة لتوفير المساحة</h4>
              <p className="text-[11px] text-slate-400 leading-relaxed">
                أكبر مستهلك للمساحة عادةً هو جدول <strong className="text-white">تتبع المواقع GPS</strong> وجدول <strong className="text-white">الحضور والغياب</strong>. بعد اعتماد رواتب الشهر بالكامل، يمكنك حذف هذه السجلات من قسم <strong className="text-amber-400">إعدادات النظام → أداة تنظيف قاعدة البيانات</strong> بأمان تام.
              </p>
            </div>
          </div>
        </div>

        {/* Purge panel */}
        <div className="bg-slate-900/40 backdrop-blur-xl border border-slate-850 rounded-3xl p-6 shadow-xl flex flex-col justify-between">
          <div>
            <h4 className="font-extrabold text-sm text-white mb-2">إجراءات تصفية المساحة</h4>
            <p className="text-xs text-slate-400 mb-6">إفراغ سلة المحذوفات لتحرير مساحة التخزين السحابي فوراً</p>

            <button
              disabled={actionLoading || trashSizeBytes === 0}
              onClick={handleEmptyTrash}
              className="w-full flex items-center justify-center gap-2 py-4 px-4 bg-rose-500/10 hover:bg-rose-500/20 text-rose-400 hover:text-rose-300 border border-rose-500/20 hover:border-rose-500/30 rounded-2xl font-bold transition-all text-xs cursor-pointer disabled:opacity-40 disabled:pointer-events-none"
            >
              <Trash2 className="w-4.5 h-4.5" />
              <span>إفراغ سلة المحذوفات بالكامل 🗑️</span>
            </button>
          </div>

          <div className="mt-6 p-4 bg-slate-950/50 border border-slate-850 rounded-2xl">
            <div className="flex items-center gap-2 mb-2">
              <ShieldCheck className="w-4 h-4 text-emerald-400" />
              <span className="text-[10px] font-bold text-white">حدود الباقة المجانية</span>
            </div>
            <ul className="text-[10px] text-slate-400 space-y-1.5 font-bold">
              <li className="flex justify-between">
                <span>قاعدة البيانات:</span>
                <span className="text-slate-300">500 MB</span>
              </li>
              <li className="flex justify-between">
                <span>التخزين السحابي:</span>
                <span className="text-slate-300">1 GB</span>
              </li>
              <li className="flex justify-between border-t border-slate-850 pt-1.5 mt-1.5">
                <span>الإجمالي المتاح:</span>
                <span className="text-teal-400">1.5 GB</span>
              </li>
            </ul>
          </div>
        </div>
      </div>

    </div>
  );
}
