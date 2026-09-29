'use client';

// دور المستخدم في لوحة التحكم (أدمن أو مدير فرع) — يحدد الصفحات والبيانات المعروضة.

import { createContext, useContext } from 'react';

export type DashboardRole = 'admin' | 'manager';

export const RoleContext = createContext<DashboardRole>('admin');

export const useRole = () => useContext(RoleContext);

/** صفحات الأدمن فقط: الرواتب والسلف والإعدادات والنظام (دوال السيرفر ترفضها للمدير أصلاً). */
export const ADMIN_ONLY_PATHS = ['/dashboard/payroll', '/dashboard/loans', '/dashboard/settings', '/dashboard/storage', '/dashboard/trash'];

export function isAdminOnlyPath(path: string | null | undefined): boolean {
  if (!path) return false;
  return ADMIN_ONLY_PATHS.some((p) => path === p || path.startsWith(`${p}/`));
}

export function canSeePath(role: DashboardRole, path: string): boolean {
  return role === 'admin' || !isAdminOnlyPath(path);
}
