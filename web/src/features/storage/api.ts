// بيانات صفحة التخزين: سلة المحذوفات، أحجام الـ Buckets، حجم قاعدة البيانات وجداولها.

import { supabase } from '@/lib/supabase';
import { bucketFor } from '@/lib/storage';
import type { TableSizeRow } from './logic';

export interface StorageStats {
  trashBytes: number;
  avatars: number;
  documents: number;
  pledges: number;
  others: number;
  /** null = ما رجع حجم (تبقى القيمة السابقة بالشاشة) */
  dbSizeBytes: number | null;
  tableSizes: TableSizeRow[] | null;
}

/** كل الإحصائيات بالتوازي. أخطاء الاستعلامات الفردية تُعامل كقيم فارغة (نفس سلوك الصفحة). */
export async function fetchStorageStats(): Promise<StorageStats> {
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

  // Buckets
  let avatars = 0, documents = 0, pledges = 0, others = 0;
  if (storageResult.data) {
    storageResult.data.forEach((stat: { bucket_name: string; total_size: number; file_count?: number }) => {
      const bucket = stat.bucket_name;
      const size = Number(stat.total_size || 0);
      if (bucket === 'avatars') avatars += size;
      else if (bucket === 'employee-documents') documents += size;
      else if (bucket === 'loan-pledges') pledges += size;
      else others += size;
    });
  }

  return {
    trashBytes: totalTrash,
    avatars,
    documents,
    pledges,
    others,
    dbSizeBytes: dbSizeResult.data && dbSizeResult.data[0] ? Number(dbSizeResult.data[0].db_size || 0) : null,
    tableSizes: tableSizesResult.data ? (tableSizesResult.data as TableSizeRow[]) : null,
  };
}

/** يمسح ملفات السلة من التخزين السحابي (كل ملف من الـ Bucket الخاص بنوعه) ثم سجلاتها. ترمي إذا فشل حذف السجلات. */
export async function emptyTrash(): Promise<void> {
  const { data: files } = await supabase
    .from('deleted_files')
    .select('*')
    .is('restored_at', null);

  if (files && files.length > 0) {
    for (const file of files) {
      const bucket = bucketFor(file.file_type);
      await supabase.storage.from(bucket).remove([file.file_path]);
    }
  }

  const { error } = await supabase
    .from('deleted_files')
    .delete()
    .is('restored_at', null);

  if (error) throw error;
}
