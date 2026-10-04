// =========================================================================
// أدوار المستخدمين — القيم كما بعمود employees.role
// =========================================================================
// admin   = مسؤول النظام: كل الصلاحيات (الرواتب، السلف، الإعدادات).
// manager = مدير فرع: لوحة الإدارة لموظفي فرعه، بدون الرواتب والسلف.
// employee = موظف.
// السيرفر هو اللي يفرض الصلاحيات فعلياً (require_admin وسياسات RLS)؛ هذي الفحوصات للعرض والتنقل فقط.
// لإضافة دور جديد: أضفه هنا وحدّد بأي دالة يدخل، ثم بالسيرفر.

abstract final class Roles {
  static const admin = 'admin';
  static const manager = 'manager';
  static const employee = 'employee';

  static bool isAdmin(String? role) => role == admin;

  /// يدخل شاشات الإدارة (أدمن أو مدير فرع).
  static bool canManage(String? role) => role == admin || role == manager;
}
