// قائمة لوحة الإدارة (الشريط الجانبي + البحث السريع Ctrl K). إضافة صفحة جديدة = عنصر هنا فقط؛
// إخفاء صفحة عن مدير الفرع يكون في lib/role.ts (canSeePath / isAdminOnlyPath).

import {
  LayoutDashboard,
  Users,
  MapPin,
  Settings,
  ShieldAlert,
  Trash2,
  HardDrive,
  CalendarRange,
  Coins,
  Banknote,
  Sparkles,
  type LucideIcon,
} from 'lucide-react';

export interface SidebarItem {
  name: string;
  description: string;
  href: string;
  icon: LucideIcon;
  /** عدّاد الطلبات المعلّقة الظاهر بجانب العنصر */
  badgeKey?: 'leaves' | 'loans';
}

export interface SidebarGroup {
  label: string;
  items: SidebarItem[];
}

export const NAV_GROUPS: SidebarGroup[] = [
  {
    label: 'الرئيسية',
    items: [
      { name: 'نظرة عامة', description: 'ملخص فوري لحالة الكادر والحضور والتنبيهات', href: '/dashboard', icon: LayoutDashboard },
      { name: 'المساعد الذكي', description: 'اسأل عن الدوام والخصومات والسلف والوثائق، وملفات Excel', href: '/dashboard/assistant', icon: Sparkles },
    ],
  },
  {
    label: 'الموارد البشرية',
    items: [
      { name: 'الموظفون والأجهزة', description: 'دليل الموظفين، البيانات الشخصية واعتماد الأجهزة', href: '/dashboard/employees', icon: Users },
      { name: 'الحضور والتتبع', description: 'سجلات الحضور والانصراف والتتبع المباشر على الخريطة', href: '/dashboard/tracking', icon: MapPin },
      { name: 'السياج الجغرافي', description: 'تخطيط وإدارة مناطق العمل المسموح بها', href: '/dashboard/geofences', icon: ShieldAlert },
      { name: 'الإجازات', description: 'مراجعة واعتماد طلبات الإجازات الزمنية واليومية', href: '/dashboard/leaves', icon: CalendarRange, badgeKey: 'leaves' },
    ],
  },
  {
    label: 'المالية',
    items: [
      { name: 'السلف والأقساط', description: 'طلبات السلف وجدولة الأقساط الشهرية', href: '/dashboard/loans', icon: Coins, badgeKey: 'loans' },
      { name: 'الرواتب والمكافآت', description: 'احتساب الرواتب والاستقطاعات والمكافآت', href: '/dashboard/payroll', icon: Banknote },
    ],
  },
  {
    label: 'النظام',
    items: [
      { name: 'سلة المحذوفات', description: 'استعادة أو حذف الملفات نهائياً', href: '/dashboard/trash', icon: Trash2 },
      { name: 'التخزين', description: 'تحليلات المساحة المستخدمة في الـ Buckets', href: '/dashboard/storage', icon: HardDrive },
      { name: 'الإعدادات', description: 'إعدادات الشركة، الفروع، الأقسام وجداول الدوام', href: '/dashboard/settings', icon: Settings },
    ],
  },
];

export const ALL_ITEMS = NAV_GROUPS.flatMap((g) => g.items);

/** عنصر القائمة النشط: أطول بادئة مطابقة تفوز حتى تبقى الصفحات الفرعية تحت عنصرها الأب. */
export function findActiveItem(pathname: string | null): SidebarItem | undefined {
  return [...ALL_ITEMS]
    .sort((a, b) => b.href.length - a.href.length)
    .find((item) => pathname === item.href || (item.href !== '/dashboard' && pathname?.startsWith(item.href + '/')));
}

/** حرفان من اسم المستخدم للصورة الرمزية بالشريط والرأس. */
export function initialsOf(name: string) {
  const parts = (name || 'مدير').trim().split(/\s+/);
  if (parts.length >= 2) return parts[0][0] + parts[1][0];
  return (parts[0] || 'م').substring(0, 2);
}
