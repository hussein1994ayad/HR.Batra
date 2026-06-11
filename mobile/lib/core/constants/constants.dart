// ==========================================
// نظام HR Pro v6.0 - الثوابت العامة (Constants)
// ==========================================

class AppConstants {
  // إعدادات ربط قاعدة البيانات Supabase (مشروع HR.BATRA)
  static const String supabaseUrl = 'https://jgjlmddphhncatrhqrej.supabase.co';
  static const String supabaseAnonKey = 'sb_publishable_EjrPBiypg0kR-HMDk0uitw_y1aHc7kP';

  // ثوابت النظام
  static const String currency = 'د.ع'; // العملة المعتمدة: دينار عراقي
  static const String appName = 'HR Pro';

  // معايير التتبع الجغرافي وكشف التزييف
  static const int minStopDurationMinutes = 5; // مدة الوقفة المعتمدة (5 دقائق)
  static const double mockGpsThresholdAccuracy = 1.0; // دقة الكشف
  
  // معايير ضغط الصور والملفات
  static const int maxImageWidthHeight = 1280; // الحد الأقصى للعرض/الارتفاع
  static const int imageQuality = 80; // جودة ضغط الصورة (80%)
  
  // إعدادات الأرشفة والملفات
  static const int trashExpiryDays = 30; // مدة حفظ الملفات في سلة المحذوفات
}
