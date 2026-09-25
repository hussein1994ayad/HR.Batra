'use client';

import { useEffect, useMemo, useState } from 'react';
import {
  Archive, Building, Check, Eye, EyeOff, FolderOpen, Lock, Pencil, RotateCcw, Smartphone, Trash2, Unlock, UserPlus, Users, X,
} from 'lucide-react';
import type { Employee } from '@/lib/db-types';
import { useConfirm } from '@/components/confirm';
import {
  Avatar, Badge, Button, Card, CardHeader, DataTable, FilterSelect, IconButton, PageHeader, PageSkeleton, SearchInput,
  SegmentedTabs, StatTile, TableEmpty, cn, type Tone,
} from '@/components/ui';
import { formatDate, formatIQD } from '@/lib/format';
import { useEmployees } from '@/features/employees/useEmployees';
import { daysUntil, filterEmployees } from '@/features/employees/logic';
import { DeleteEmployeeModal } from '@/features/employees/components/DeleteEmployeeModal';
import { DocumentPreviewModal } from '@/features/employees/components/DocumentPreviewModal';
import { EmployeeFormModal } from '@/features/employees/components/EmployeeFormModal';
import { EmployeeProfileModal } from '@/features/employees/components/EmployeeProfileModal';

const ROLE_META: Record<string, { label: string; tone: Tone }> = {
  admin: { label: 'مدير عام', tone: 'rose' },
  manager: { label: 'مدير موارد', tone: 'amber' },
  employee: { label: 'موظف', tone: 'sky' },
};

const ARCHIVE_META: Record<string, { label: string; tone: Tone }> = {
  permanent: { label: 'إتلاف نهائي', tone: 'rose' },
  scheduled_deletion: { label: 'حذف مجدول', tone: 'amber' },
};

export default function EmployeesPage() {
  const confirm = useConfirm();
  const e = useEmployees(confirm);
  const [tab, setTab] = useState<'active' | 'archived'>('active');
  const [search, setSearch] = useState('');
  const [branchFilter, setBranchFilter] = useState('all');
  const [revealed, setRevealed] = useState<Record<string, boolean>>({});

  const [formTarget, setFormTarget] = useState<Employee | 'new' | null>(null);
  const [deleting, setDeleting] = useState<Employee | null>(null);
  const [profile, setProfile] = useState<Employee | null>(null);
  const [preview, setPreview] = useState<{ url: string; title: string } | null>(null);

  // `#new` (زر "إضافة موظف" في الرئيسية) يفتح نموذج الإضافة مباشرة
  useEffect(() => {
    const timer = setTimeout(() => {
      if (window.location.hash === '#new') {
        setFormTarget('new');
        history.replaceState(null, '', window.location.pathname);
      }
    }, 0);
    return () => clearTimeout(timer);
  }, []);

  const filtered = useMemo(() => filterEmployees({
    employees: e.employees, departments: e.departments, branches: e.branches, searchTerm: search, branchId: branchFilter,
  }), [e.employees, e.departments, e.branches, search, branchFilter]);

  if (e.loading) return <PageSkeleton rows={8} />;

  const activeCount = e.employees.filter((x) => x.is_active !== false).length;
  const lockedCount = e.employees.filter((x) => x.device_id_lock != null).length;
  const busy = e.actionLoading;

  return (
    <div className="space-y-6 pb-12">
      <PageHeader
        icon={Users}
        title="الموظفون والأجهزة"
        description="إدارة ملفات الموظفين، الرواتب الأساسية، الصلاحيات، المستمسكات وربط الهواتف"
        actions={<Button icon={UserPlus} onClick={() => setFormTarget('new')}>إضافة موظف</Button>}
      />

      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
        <StatTile label="الموظفون النشطون" value={activeCount} icon={Users} tone="indigo" />
        <StatTile label="أجهزة مربوطة" value={lockedCount} icon={Lock} tone="emerald" />
        <StatTile label="طلبات أجهزة" value={e.deviceRequests.length} icon={Smartphone} tone={e.deviceRequests.length > 0 ? 'violet' : 'slate'} />
        <StatTile label="في الأرشيف" value={e.archivedEmployees.length} icon={Archive} tone="amber" />
      </div>

      {e.deviceRequests.length > 0 && (
        <Card className="border-violet-500/25">
          <CardHeader
            icon={Smartphone}
            tone="violet"
            title={<>طلبات ربط الأجهزة <Badge tone="violet">{e.deviceRequests.length}</Badge></>}
            description="موظفون سجلوا الدخول من هواتف جديدة ويحتاجون اعتماد الجهاز لتسجيل الدوام"
          />
          <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-3">
            {e.deviceRequests.map((req) => (
              <div key={req.id} className="rounded-2xl bg-slate-900/50 border border-slate-800/80 p-4">
                <div className="flex items-center gap-3 mb-3">
                  <Avatar name={req.employees?.full_name} size="sm" />
                  <div className="min-w-0">
                    <p className="text-xs font-bold text-white truncate">{req.employees?.full_name || 'موظف'}</p>
                    <p className="text-[10px] text-slate-500 truncate">{req.model || 'جهاز غير معروف'} · {req.os_version || '—'}</p>
                  </div>
                </div>
                <p className="text-[10px] font-mono text-slate-500 truncate mb-3" dir="ltr">{req.device_id}</p>
                <div className="flex gap-2">
                  <Button size="sm" variant="success" icon={Check} block loading={busy === req.id} onClick={() => void e.processDeviceRequest(req, true)}>
                    اعتماد
                  </Button>
                  <Button size="sm" variant="soft-danger" icon={X} block disabled={busy === req.id} onClick={() => void e.processDeviceRequest(req, false)}>
                    رفض
                  </Button>
                </div>
              </div>
            ))}
          </div>
        </Card>
      )}

      <Card>
        <div className="flex flex-col lg:flex-row lg:items-center justify-between gap-3 mb-5">
          <SegmentedTabs
            value={tab}
            onChange={setTab}
            options={[
              { value: 'active', label: 'دليل الموظفين', icon: Users, count: e.employees.length },
              { value: 'archived', label: 'الأرشيف', icon: Archive, count: e.archivedEmployees.length },
            ]}
          />
          {tab === 'active' && (
            <div className="flex flex-col sm:flex-row gap-2">
              <SearchInput value={search} onChange={setSearch} placeholder="ابحث بالاسم، الكود، البريد، الهاتف، القسم، الفرع..." className="w-full sm:w-80" />
              <FilterSelect icon={Building} value={branchFilter} onChange={setBranchFilter} className="sm:w-44">
                <option value="all">جميع الفروع</option>
                {e.branches.map((b) => <option key={b.id} value={b.id}>{b.name}</option>)}
              </FilterSelect>
            </div>
          )}
        </div>

        {tab === 'active' ? (
          <DataTable>
            <thead>
              <tr>
                <th>الموظف</th>
                <th>الهاتف</th>
                <th>كلمة المرور</th>
                <th>الفرع</th>
                <th>الصلاحية</th>
                <th>الراتب الأساسي</th>
                <th>الجهاز</th>
                <th className="!text-left">الإجراءات</th>
              </tr>
            </thead>
            <tbody>
              {filtered.length === 0 ? (
                <TableEmpty colSpan={8}>{search || branchFilter !== 'all' ? 'لا توجد نتائج مطابقة للبحث' : 'لا يوجد موظفون بعد'}</TableEmpty>
              ) : (
                filtered.map((emp) => {
                  const isLocked = emp.device_id_lock != null;
                  const role = ROLE_META[emp.role ?? 'employee'] ?? ROLE_META.employee;
                  const docCount = emp.document_urls?.length ?? 0;
                  return (
                    <tr key={emp.id} className={cn(emp.is_active === false && 'opacity-50')}>
                      <td>
                        <button type="button" onClick={() => setProfile(emp)} className="flex items-center gap-3 min-w-[200px] text-right cursor-pointer group">
                          <Avatar name={emp.full_name} />
                          <div className="min-w-0">
                            <p className="font-bold text-white truncate group-hover:text-indigo-200">
                              {emp.full_name}
                              {docCount > 0 && <Badge tone="violet" className="mr-1.5">{docCount} مستمسك</Badge>}
                            </p>
                            <p className="text-[11px] text-slate-500 font-mono truncate" dir="ltr">{emp.email}</p>
                          </div>
                        </button>
                      </td>
                      <td className="font-mono" dir="ltr">{emp.phone || '—'}</td>
                      <td>
                        {emp.plain_password ? (
                          <button
                            type="button"
                            onClick={() => setRevealed((r) => ({ ...r, [emp.id]: !r[emp.id] }))}
                            className="inline-flex items-center gap-1.5 font-mono text-slate-300 hover:text-white cursor-pointer"
                            title={revealed[emp.id] ? 'إخفاء' : 'إظهار'}
                          >
                            {revealed[emp.id] ? <EyeOff className="w-3.5 h-3.5 text-slate-500" /> : <Eye className="w-3.5 h-3.5 text-slate-500" />}
                            <span dir="ltr">{revealed[emp.id] ? emp.plain_password : '••••••'}</span>
                          </button>
                        ) : (
                          <span className="text-slate-600">—</span>
                        )}
                      </td>
                      <td>{emp.branches?.name || <span className="text-slate-600">—</span>}</td>
                      <td><Badge tone={role.tone}>{role.label}</Badge></td>
                      <td className="font-bold text-slate-200 whitespace-nowrap">{formatIQD(emp.monthly_salary_iqd)}</td>
                      <td>{isLocked ? <Badge tone="emerald" dot>مربوط</Badge> : <Badge tone="slate">غير مربوط</Badge>}</td>
                      <td className="!text-left">
                        <div className="flex justify-end gap-1.5">
                          <IconButton icon={FolderOpen} label="الملف والوثائق" tone="violet" onClick={() => setProfile(emp)} />
                          <IconButton icon={Pencil} label="تعديل بيانات الموظف" tone="indigo" onClick={() => setFormTarget(emp)} />
                          <IconButton
                            icon={isLocked ? Unlock : Lock}
                            label={isLocked ? 'فك قفل الجهاز' : 'تفعيل قفل الجهاز'}
                            tone={isLocked ? 'amber' : 'emerald'}
                            loading={busy === emp.id}
                            onClick={() => void e.toggleDeviceLock(emp)}
                          />
                          {isLocked && (
                            <IconButton
                              icon={Smartphone}
                              label="إلغاء ربط الهاتف وربط جهاز جديد"
                              tone="violet"
                              loading={busy === `${emp.id}_reset`}
                              onClick={() => void e.resetDevice(emp)}
                            />
                          )}
                          <IconButton icon={Trash2} label="حذف أو أرشفة الموظف" tone="rose" onClick={() => setDeleting(emp)} />
                        </div>
                      </td>
                    </tr>
                  );
                })
              )}
            </tbody>
          </DataTable>
        ) : (
          <DataTable>
            <thead>
              <tr>
                <th>الموظف</th>
                <th>الرمز</th>
                <th>الإجراء</th>
                <th>السبب</th>
                <th>الحذف المجدول</th>
                <th>تاريخ الأرشفة</th>
                <th className="!text-left">الإجراءات</th>
              </tr>
            </thead>
            <tbody>
              {e.archivedEmployees.length === 0 ? (
                <TableEmpty colSpan={7}>لا يوجد موظفون في الأرشيف</TableEmpty>
              ) : (
                e.archivedEmployees.map((arch) => {
                  const meta = ARCHIVE_META[arch.archive_type] ?? { label: 'أرشفة مؤقتة', tone: 'sky' as Tone };
                  return (
                    <tr key={arch.id}>
                      <td>
                        <div className="flex items-center gap-2.5">
                          <Avatar name={arch.full_name} size="sm" />
                          <span className="font-bold text-white">{arch.full_name}</span>
                        </div>
                      </td>
                      <td className="font-mono text-slate-400" dir="ltr">{arch.employee_code || '—'}</td>
                      <td><Badge tone={meta.tone}>{meta.label}</Badge></td>
                      <td className="max-w-[220px] truncate" title={arch.archive_reason ?? undefined}>{arch.archive_reason || '—'}</td>
                      <td>
                        {arch.scheduled_deletion_date ? (
                          <span className="text-amber-300 font-bold whitespace-nowrap">
                            <span dir="ltr">{formatDate(arch.scheduled_deletion_date)}</span> ({daysUntil(arch.scheduled_deletion_date)} يوم)
                          </span>
                        ) : '—'}
                      </td>
                      <td className="font-mono text-slate-400" dir="ltr">{formatDate(arch.archived_at)}</td>
                      <td className="!text-left">
                        <div className="flex justify-end gap-1.5">
                          {arch.archive_type !== 'permanent' && (
                            <Button size="xs" variant="soft" icon={RotateCcw} loading={busy === `restore_${arch.id}`} onClick={() => void e.restoreArchived(arch)}>
                              تفعيل
                            </Button>
                          )}
                          <Button size="xs" variant="soft-danger" icon={Trash2} loading={busy === `perm_del_${arch.id}`} onClick={() => void e.destroyArchived(arch)}>
                            إتلاف
                          </Button>
                        </div>
                      </td>
                    </tr>
                  );
                })
              )}
            </tbody>
          </DataTable>
        )}
      </Card>

      {formTarget && (
        <EmployeeFormModal
          key={formTarget === 'new' ? 'new' : formTarget.id}
          employee={formTarget === 'new' ? null : formTarget}
          branches={e.branches}
          saving={busy === 'create_emp' || busy === 'update_emp'}
          onClose={() => setFormTarget(null)}
          onSubmit={async (values, kept, newDocs) => {
            const ok = formTarget === 'new'
              ? await e.addEmployee(values, newDocs)
              : await e.editEmployee(formTarget, values, kept, newDocs);
            if (ok) setFormTarget(null);
          }}
        />
      )}

      {deleting && (
        <DeleteEmployeeModal
          employeeToDelete={deleting}
          saving={busy === 'delete_emp'}
          onClose={() => setDeleting(null)}
          onSubmit={async (deleteType, reason) => {
            if (await e.removeEmployee(deleting, deleteType, reason)) setDeleting(null);
          }}
        />
      )}

      {profile && (
        <EmployeeProfileModal
          profileEmployee={profile}
          onClose={() => setProfile(null)}
          onEdit={(emp) => {
            setProfile(null);
            setFormTarget(emp);
          }}
          onPreview={(url, title) => setPreview({ url, title })}
        />
      )}

      {preview && <DocumentPreviewModal previewDocUrl={preview.url} previewDocTitle={preview.title} onClose={() => setPreview(null)} />}
    </div>
  );
}
