// =========================================================================
// نظام HR Pro v6.0 - Edge Function للتنظيف اليومي (daily-cleanup)
// يشتغل تلقائياً عبر نظام الجدولة الزمني لتفريغ سلة المحذوفات وأرشفة بيانات المواقع
// =========================================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

serve(async (req) => {
  // التحقق من طريقة الطلب للوظيفة
  if (req.method === 'OPTIONS') {
    return new Response('ok', { 
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
      }
    });
  }

  try {
    console.log("بدء تشغيل عملية التنظيف اليومي المؤتمتة...");

    // 1. إنشاء زبون بـ Service Role لتخطي قيود الـ RLS والتحكم المطلق بالتخزين وحذف الملفات نهائياً
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // 2. استدعاء الدالة المخزنة في قاعدة البيانات لإتمام التنظيف وأرشفة بيانات التتبع
    const { data: expiredFiles, error: cleanupError } = await supabase.rpc('perform_daily_cleanup');

    if (cleanupError) {
      console.error("خطأ أثناء تنفيذ دالة perform_daily_cleanup في قاعدة البيانات:", cleanupError);
      throw cleanupError;
    }

    console.log(`تم الكشف عن ${expiredFiles?.length || 0} ملفاً منتهياً في سلة المحذوفات (تجاوزت 30 يوماً).`);

    let successfullyDeletedCount = 0;

    // 3. حذف الملفات الفعلي من مجلدات التخزين
    if (expiredFiles && expiredFiles.length > 0) {
      for (const file of expiredFiles) {
        const { expired_file_path, expired_bucket_id, file_record_id } = file;
        
        console.log(`جاري الحذف التام والنهائي للملف: [${expired_file_path}] من المجلد [${expired_bucket_id}]`);
        
        // حذف الملف الفعلي من مجلد التخزين (Storage Bucket)
        const { error: deleteStorageError } = await supabase.storage
          .from(expired_bucket_id)
          .remove([expired_file_path]);

        if (deleteStorageError) {
          console.error(`فشل حذف الملف [${expired_file_path}] من التخزين:`, deleteStorageError);
        } else {
          console.log(`تم حذف الملف [${expired_file_path}] بنجاح من التخزين.`);
          
          // بعد التأكد من الحذف من التخزين، نمسح السجل نهائياً من قاعدة البيانات في جدول deleted_files
          const { error: deleteRecordError } = await supabase
            .from('deleted_files')
            .delete()
            .eq('id', file_record_id);

          if (deleteRecordError) {
            console.error(`خطأ في مسح سجل سلة المحذوفات للمعرف [${file_record_id}]:`, deleteRecordError);
          } else {
            successfullyDeletedCount++;
          }
        }
      }
    }

    console.log(`تم الانتهاء بنجاح. الملفات المحذوفة نهائياً: ${successfullyDeletedCount}/${expiredFiles?.length || 0}`);

    return new Response(
      JSON.stringify({ 
        success: true, 
        message: "تم إجراء عملية التنظيف اليومي وتفريغ سلة المحذوفات وأرشفة بيانات التتبع بنجاح.",
        total_expired_detected: expiredFiles?.length || 0,
        successfully_deleted_from_storage: successfullyDeletedCount
      }),
      {
        headers: { 
          "Content-Type": "application/json",
          "Access-Control-Allow-Origin": "*"
        },
        status: 200,
      }
    );

  } catch (error) {
    console.error("حدث خطأ غير متوقع أثناء عملية التنظيف اليومي:", error);
    return new Response(
      JSON.stringify({ 
        success: false, 
        error: error.message 
      }),
      {
        headers: { 
          "Content-Type": "application/json",
          "Access-Control-Allow-Origin": "*"
        },
        status: 500,
      }
    );
  }
});
