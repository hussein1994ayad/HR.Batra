// =========================================================================
// نظام HR Pro v6.0 - الثوابت العامة (Constants)
// =========================================================================
// طرق تمرير الأسرار (Secrets):
//   الطريقة الافتراضية: القيم أدناه (مناسبة للتطوير فقط)
//   الطريقة الموصى بها للإنتاج: استخدام --dart-define أثناء البناء:
//
//   flutter build apk --release \
//     --dart-define=SUPABASE_URL=https://xxx.supabase.co \
//     --dart-define=SUPABASE_ANON_KEY=sb_publishable_xxx
//
//   بذلك لا تظهر المفاتيح في المستودع، وكل بيئة (dev/staging/prod)
//   تستخدم مفاتيحها الخاصة عبر GitHub Actions Secrets.
// =========================================================================

class AppConstants {
  // ------------------------------------------------------------------------
  // Supabase — يفضّل تمريرها عبر --dart-define في CI
  // ------------------------------------------------------------------------
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://jgjlmddphhncatrhqrej.supabase.co',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_EjrPBiypg0kR-HMDk0uitw_y1aHc7kP',
  );

  // ------------------------------------------------------------------------
  // ثوابت النظام
  // ------------------------------------------------------------------------
  static const String currency = 'د.ع'; // العملة: دينار عراقي
  static const String appName = 'HR Pro';

  /// صفحة سياسة الخصوصية (مطلوبة لمتجري Apple و Google)
  static const String privacyPolicyUrl = String.fromEnvironment(
    'PRIVACY_POLICY_URL',
    defaultValue: 'https://batra-hr-pro.surge.sh/privacy',
  );

  /// تنسيق مبلغ مالي بفواصل الآلاف (نقاط) + رمز العملة.
  static String formatMoney(num amount) {
    final String str = amount.round().toString();
    final RegExp reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    return '${str.replaceAllMapped(reg, (Match m) => '${m[1]}.')} $currency';
  }

  // ------------------------------------------------------------------------
  // معايير التتبع الجغرافي وكشف التزييف
  // ------------------------------------------------------------------------
  static const int minStopDurationMinutes = 5; // مدة الوقفة المعتمدة
  static const double mockGpsThresholdAccuracy = 1.0;

  // ------------------------------------------------------------------------
  // ضغط الصور والملفات
  // ------------------------------------------------------------------------
  static const int maxImageWidthHeight = 1280;
  static const int imageQuality = 80;

  // ------------------------------------------------------------------------
  // الأرشفة والملفات
  // ------------------------------------------------------------------------
  static const int trashExpiryDays = 30;
}
