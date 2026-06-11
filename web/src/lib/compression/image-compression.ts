// =========================================================================
// نظام HR Pro v6.0 - خدمة ضغط الصور في المتصفح للويب (Web Image Compression)
// =========================================================================

import imageCompression from 'browser-image-compression';

export interface CompressionOptions {
  maxSizeMB?: number;
  maxWidthOrHeight?: number;
  useWebWorker?: boolean;
  initialQuality?: number;
}

/**
 * دالة ذكية لضغط الصور قبل الرفع من المتصفح إلى Supabase Storage.
 * تقوم بتقليص الحجم والأبعاد وإزالة الـ EXIF تلقائياً للحفاظ على الخصوصية والمساحة.
 * 
 * @param file ملف الصورة الأصلي المختار من المستخدم
 * @param options خيارات الضغط الإضافية (اختيارية)
 */
export async function compressWebImage(
  file: File,
  options: CompressionOptions = {}
): Promise<File> {
  // التحقق من أن الملف الممرر هو صورة فعلاً
  if (!file.type.startsWith('image/')) {
    console.log(`الملف ليس صورة (${file.type})، سيتم رفعه دون تعديل: ${file.name}`);
    return file;
  }

  // الاستثناءات لملفات GIF أو الأيقونات للحفاظ على حركتها وجودتها الأصلية
  if (file.type === 'image/gif' || file.type === 'image/x-icon') {
    return file;
  }

  const defaultOptions = {
    maxSizeMB: 0.5, // الحد الأقصى للحجم المقدر (~ 500 كيلوبايت)
    maxWidthOrHeight: 1280, // تصغير العرض/الارتفاع الأقصى إلى 1280px
    useWebWorker: true, // استخدام ويب ووركر لتحسين الأداء وتجنب تجميد الواجهة
    initialQuality: 0.8, // جودة الضغط (80%)
    ...options
  };

  try {
    console.log(`بدء ضغط الصورة: ${file.name} | الحجم الأصلي: ${(file.size / 1024 / 1024).toFixed(2)} ميجابايت`);
    
    // تنفيذ الضغط تلقائياً (browser-image-compression يزيل بيانات EXIF جغرافياً بشكل تلقائي)
    const compressedBlob = await imageCompression(file, defaultOptions);
    
    // تحويل الـ Blob إلى File
    const compressedFile = new File([compressedBlob], file.name, {
      type: file.type,
      lastModified: Date.now()
    });

    console.log(`اكتمل الضغط بنجاح: ${compressedFile.name} | الحجم الجديد: ${(compressedFile.size / 1024).toFixed(2)} كيلوبايت | المساحة الموفرة: ${(((file.size - compressedFile.size) / file.size) * 100).toFixed(1)}%`);

    return compressedFile;

  } catch (error) {
    console.error("حدث خطأ غير متوقع أثناء عملية ضغط الصورة بالويب:", error);
    return file; // إرجاع الصورة الأصلية كبديل في حال حدوث خطأ مفاجئ
  }
}
