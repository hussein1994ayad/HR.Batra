import type { WorkSchedule } from '@/lib/db-types';

type ScheduleOwner = {
  id: string;
  department_id?: string | null;
  branch_id?: string | null;
};

const byNewest = (a: WorkSchedule, b: WorkSchedule) =>
  (b.created_at ?? '').localeCompare(a.created_at ?? '');

/**
 * جدول الدوام الفعلي للموظف — نفس أولوية get_effective_work_schedule في
 * قاعدة البيانات: جدول الموظف نفسه ← جدول قسمه ← جدول فرعه، والأحدث عند التساوي.
 * (كان كل صفحة تطبّق نسختها، والموظف بدون قسم كان يطابق جدول أي فرع.)
 */
export function resolveWorkSchedule(
  employee: ScheduleOwner,
  schedules: WorkSchedule[] | null | undefined,
): WorkSchedule | undefined {
  const list = [...(schedules ?? [])].sort(byNewest);
  return (
    list.find(s => s.employee_id === employee.id) ??
    list.find(s => !s.employee_id && !!s.department_id && s.department_id === employee.department_id) ??
    list.find(s => !s.employee_id && !s.department_id && !!s.branch_id && s.branch_id === employee.branch_id)
  );
}
