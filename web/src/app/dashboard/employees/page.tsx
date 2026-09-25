'use client';

import React, { useEffect, useMemo, useState } from 'react';
import Image from 'next/image';
import toast from 'react-hot-toast';
import {
  Users,
  Smartphone,
  Lock,
  Unlock,
  Check,
  X,
  Trash2,
  UserPlus,
  Pencil,
  Building,
  Upload,
  Archive,
  RotateCcw,
  Eye,
  EyeOff,
  ShieldAlert,
  Clock,
  AlertTriangle,
  Save,
} from 'lucide-react';
import { createClient } from '@supabase/supabase-js';
import { supabase, supabaseAnonKey, supabaseUrl } from '@/lib/supabase';
import { confetti, imageCompression } from '@/lib/lazy';
import { readCache, useQuery, writeCache } from '@/lib/useQuery';
import { daysUntil, errorMessage, formatDate, formatIQD } from '@/lib/format';
import type { ArchivedEmployee, Branch, DeviceRequest, Employee } from '@/lib/types';
import { useConfirm } from '@/components/confirm';
import {
  AmountInput,
  Avatar,
  Badge,
  Button,
  Card,
  CardHeader,
  DataTable,
  EmptyState,
  Field,
  FilterSelect,
  IconButton,
  Input,
  Modal,
  ModalFooter,
  PageHeader,
  PageSkeleton,
  SearchInput,
  SegmentedTabs,
  Select,
  StatTile,
  TableEmpty,
  cn,
  type Tone,
} from '@/components/ui';

interface EmployeesData {
  employees: Employee[];
  deviceRequests: DeviceRequest[];
  branches: Pick<Branch, 'id' | 'name'>[];
  archived: ArchivedEmployee[];
}

const CACHE_KEY = 'batra_cache_employees_v2';
const DOCS_BUCKET = 'employee-documents';

async function fetchEmployees(): Promise<EmployeesData> {
  const [emps, reqs, brs, arch] = await Promise.all([
    supabase.from('employees').select('*, branches(name)').order('full_name', { ascending: true }),
    supabase.from('employee_devices').select('*, employees(full_name)').eq('is_approved', false),
    supabase.from('branches').select('id, name').order('name'),
    supabase.from('archived_employees').select('*').order('archived_at', { ascending: false }),
  ]);
  if (emps.error) throw emps.error;
  const data: EmployeesData = {
    employees: (emps.data ?? []) as Employee[],
    deviceRequests: (reqs.data ?? []) as DeviceRequest[],
    branches: (brs.data ?? []) as EmployeesData['branches'],
    archived: (arch.data ?? []) as ArchivedEmployee[],
  };
  writeCache(CACHE_KEY, data);
  return data;
}

async function uploadDocuments(employeeId: string, files: File[]): Promise<string[]> {
  const urls: string[] = [];
  for (const file of files) {
    try {
      const compressed = await imageCompression(file, { maxSizeMB: 1, maxWidthOrHeight: 1920, useWebWorker: true });
      const ext = file.name.split('.').pop();
      const path = `${employeeId}/${Date.now()}_${Math.random().toString(36).substring(7)}.${ext}`;
      const { error } = await supabase.storage.from(DOCS_BUCKET).upload(path, compressed);
      if (error) throw error;
      urls.push(supabase.storage.from(DOCS_BUCKET).getPublicUrl(path).data.publicUrl);
    } catch (err) {
      console.error('Failed to compress/upload file:', err);
      toast.error(`تعذر رفع الملف ${file.name}`);
    }
  }
  return urls;
}

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
  const [cached] = useState(() => {
    const c = readCache<EmployeesData>(CACHE_KEY);
    return c && Array.isArray(c.employees) ? c : undefined;
  });
  const query = useQuery('employees', fetchEmployees, cached);

  const [tab, setTab] = useState<'active' | 'archived'>('active');
  const [search, setSearch] = useState('');
  const [branchFilter, setBranchFilter] = useState('all');
  const [busy, setBusy] = useState<string | null>(null);
  const [revealed, setRevealed] = useState<Record<string, boolean>>({});

  // `#new` (from the dashboard quick action) opens the add form directly.
  const [formTarget, setFormTarget] = useState<Employee | 'new' | null>(() =>
    typeof window !== 'undefined' && window.location.hash === '#new' ? 'new' : null,
  );
  const [deleteTarget, setDeleteTarget] = useState<Employee | null>(null);

  useEffect(() => {
    // On client-side navigation the URL (and its hash) is committed after this
    // page first renders, so check again once the navigation has settled.
    const timer = setTimeout(() => {
      if (window.location.hash === '#new') {
        setFormTarget('new');
        history.replaceState(null, '', window.location.pathname);
      }
    }, 0);
    return () => clearTimeout(timer);
  }, []);

  const data = query.data;
  const employees = useMemo(() => data?.employees ?? [], [data]);

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase();
    return employees.filter(
      (e) =>
        (branchFilter === 'all' || e.branch_id === branchFilter) &&
        (!q || (e.full_name || '').toLowerCase().includes(q) || (e.email || '').toLowerCase().includes(q) || (e.phone || '').includes(q)),
    );
  }, [employees, search, branchFilter]);

  if (!data) {
    if (query.error) {
      return <EmptyState icon={AlertTriangle} tone="rose" title="تعذر تحميل الموظفين" description={errorMessage(query.error)} action={<Button size="sm" variant="secondary" onClick={query.reload}>إعادة المحاولة</Button>} />;
    }
    return <PageSkeleton rows={8} />;
  }

  const activeCount = employees.filter((e) => e.is_active !== false).length;
  const lockedCount = employees.filter((e) => e.device_id_lock != null).length;

  const updateEmployeeLocally = (id: string, patch: Partial<Employee>) =>
    query.mutate((d) => ({ ...d, employees: d.employees.map((e) => (e.id === id ? { ...e, ...patch } : e)) }));

  const run = async (key: string, action: () => Promise<void>, failMsg: string) => {
    setBusy(key);
    try {
      await action();
    } catch (err) {
      toast.error(`${failMsg}: ${errorMessage(err)}`);
    } finally {
      setBusy(null);
    }
  };

  const toggleDeviceLock = (emp: Employee) =>
    run(
      emp.id,
      async () => {
        const next = emp.device_id_lock ? null : 'force_lock_active';
        const { error } = await supabase.from('employees').update({ device_id_lock: next }).eq('id', emp.id);
        if (error) throw error;
        updateEmployeeLocally(emp.id, { device_id_lock: next });
        toast.success(next ? 'تم تفعيل قفل الجهاز' : 'تم فك قفل الجهاز');
      },
      'فشل تغيير قفل الجهاز',
    );

  const resetDeviceBinding = async (emp: Employee) => {
    const ok = await confirm({
      title: 'إلغاء ربط هاتف الموظف؟',
      message: `سيتمكن ${emp.full_name} من تسجيل الدخول من هاتف جديد، وسيُقفل الحساب على أول جهاز يسجل منه.`,
      confirmLabel: 'إلغاء الربط',
      tone: 'warning',
    });
    if (!ok) return;
    await run(
      `${emp.id}_reset`,
      async () => {
        const { error: delError } = await supabase.from('employee_devices').delete().eq('employee_id', emp.id);
        if (delError) throw delError;
        const { error } = await supabase.from('employees').update({ device_id_lock: 'force_lock_active' }).eq('id', emp.id);
        if (error) throw error;
        updateEmployeeLocally(emp.id, { device_id_lock: 'force_lock_active' });
        toast.success('تم فك ربط هاتف الموظف');
      },
      'فشل فك ربط الهاتف',
    );
  };

  const processDeviceRequest = (req: DeviceRequest, approve: boolean) =>
    run(
      req.id,
      async () => {
        if (approve) {
          const { error } = await supabase
            .from('employee_devices')
            .update({ is_approved: true, approved_at: new Date().toISOString() })
            .eq('id', req.id);
          if (error) throw error;
          await supabase.from('employees').update({ device_id_lock: req.device_id }).eq('id', req.employee_id);
          await supabase.from('notifications').insert({
            employee_id: req.employee_id,
            title: 'اعتماد جهاز الدخول الجديد 📱',
            body: 'تمت موافقة الإدارة على اعتماد هاتف تسجيل دخولك الجديد.',
            type: 'device',
          });
        } else {
          const { error } = await supabase.from('employee_devices').delete().eq('id', req.id);
          if (error) throw error;
        }
        query.reload();
        toast.success(approve ? 'تم اعتماد الجهاز وتثبيته' : 'تم رفض طلب ربط الجهاز');
      },
      'فشل إتمام العملية',
    );

  const restoreArchived = async (arch: ArchivedEmployee) => {
    const ok = await confirm({
      title: 'استعادة الموظف؟',
      message: `سيتم إعادة تفعيل حساب ${arch.full_name} والسماح له بتسجيل الدوام مجدداً.`,
      confirmLabel: 'استعادة',
      tone: 'primary',
      icon: RotateCcw,
    });
    if (!ok) return;
    await run(
      `restore_${arch.id}`,
      async () => {
        const { error } = await supabase.from('employees').update({ is_active: true }).eq('id', arch.employee_id);
        if (error) throw error;
        const { error: delErr } = await supabase.from('archived_employees').delete().eq('id', arch.id);
        if (delErr) throw delErr;
        query.reload();
        confetti({ particleCount: 50, spread: 40, colors: ['#10B981', '#34D399'] });
        toast.success('تم استعادة الموظف وتنشيط حسابه');
      },
      'فشل استعادة الموظف',
    );
  };

  const destroyArchived = async (arch: ArchivedEmployee) => {
    const ok = await confirm({
      title: 'إتلاف بيانات الموظف نهائياً؟',
      message: `سيتم حذف حساب ${arch.full_name} وسجلاته وبصماته من قاعدة البيانات بشكل كامل. لا يمكن استعادة البيانات بعد ذلك.`,
      confirmLabel: 'إتلاف نهائي',
    });
    if (!ok) return;
    await run(
      `destroy_${arch.id}`,
      async () => {
        await supabase.from('employees').delete().eq('id', arch.employee_id);
        const { error } = await supabase
          .from('archived_employees')
          .update({ archive_type: 'permanent', notes: 'تم الإتلاف النهائي اليدوي للبيانات والحساب من قبل المسؤول.' })
          .eq('id', arch.id);
        if (error) throw error;
        query.reload();
        toast.success('تم إتلاف بيانات الموظف نهائياً');
      },
      'فشل الإتلاف النهائي',
    );
  };

  return (
    <div className="space-y-6 pb-12">
      <PageHeader
        icon={Users}
        title="الموظفون والأجهزة"
        description="إدارة ملفات الموظفين، الرواتب الأساسية، الصلاحيات وربط الهواتف"
        actions={
          <Button icon={UserPlus} onClick={() => setFormTarget('new')}>
            إضافة موظف
          </Button>
        }
      />

      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
        <StatTile label="الموظفون النشطون" value={activeCount} icon={Users} tone="indigo" />
        <StatTile label="أجهزة مربوطة" value={lockedCount} icon={Lock} tone="emerald" />
        <StatTile label="طلبات أجهزة" value={data.deviceRequests.length} icon={Smartphone} tone={data.deviceRequests.length > 0 ? 'violet' : 'slate'} />
        <StatTile label="في الأرشيف" value={data.archived.length} icon={Archive} tone="amber" />
      </div>

      {data.deviceRequests.length > 0 && (
        <Card className="border-violet-500/25">
          <CardHeader
            icon={Smartphone}
            tone="violet"
            title={<>طلبات ربط الأجهزة <Badge tone="violet">{data.deviceRequests.length}</Badge></>}
            description="موظفون سجلوا الدخول من هواتف جديدة ويحتاجون اعتماد الجهاز لتسجيل الدوام"
          />
          <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-3">
            {data.deviceRequests.map((req) => (
              <div key={req.id} className="rounded-2xl bg-slate-900/50 border border-slate-800/80 p-4">
                <div className="flex items-center gap-3 mb-3">
                  <Avatar name={req.employees?.full_name} size="sm" />
                  <div className="min-w-0">
                    <p className="text-xs font-bold text-white truncate">{req.employees?.full_name || 'موظف'}</p>
                    <p className="text-[10px] text-slate-500 truncate">
                      {req.device_model || req.model || 'جهاز غير معروف'} · {req.os_version || '—'}
                    </p>
                  </div>
                </div>
                <p className="text-[10px] font-mono text-slate-500 truncate mb-3" dir="ltr">{req.device_id}</p>
                <div className="flex gap-2">
                  <Button size="sm" variant="success" icon={Check} block loading={busy === req.id} onClick={() => processDeviceRequest(req, true)}>
                    اعتماد
                  </Button>
                  <Button size="sm" variant="soft-danger" icon={X} block disabled={busy === req.id} onClick={() => processDeviceRequest(req, false)}>
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
              { value: 'active', label: 'دليل الموظفين', icon: Users, count: employees.length },
              { value: 'archived', label: 'الأرشيف', icon: Archive, count: data.archived.length },
            ]}
          />
          {tab === 'active' && (
            <div className="flex flex-col sm:flex-row gap-2">
              <SearchInput value={search} onChange={setSearch} placeholder="ابحث بالاسم أو البريد أو الهاتف..." className="w-full sm:w-72" />
              <FilterSelect icon={Building} value={branchFilter} onChange={setBranchFilter} className="sm:w-44">
                <option value="all">جميع الفروع</option>
                {data.branches.map((b) => (
                  <option key={b.id} value={b.id}>
                    {b.name}
                  </option>
                ))}
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
                  return (
                    <tr key={emp.id} className={cn(emp.is_active === false && 'opacity-50')}>
                      <td>
                        <div className="flex items-center gap-3 min-w-[200px]">
                          <Avatar name={emp.full_name} />
                          <div className="min-w-0">
                            <p className="font-bold text-white truncate">{emp.full_name}</p>
                            <p className="text-[11px] text-slate-500 font-mono truncate" dir="ltr">{emp.email}</p>
                          </div>
                        </div>
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
                      <td>
                        <Badge tone={role.tone}>{role.label}</Badge>
                      </td>
                      <td className="font-bold text-slate-200 whitespace-nowrap">{formatIQD(emp.monthly_salary_iqd)}</td>
                      <td>
                        {isLocked ? (
                          <Badge tone="emerald" dot>مربوط</Badge>
                        ) : (
                          <Badge tone="slate">غير مربوط</Badge>
                        )}
                      </td>
                      <td className="!text-left">
                        <div className="flex justify-end gap-1.5">
                          <IconButton icon={Pencil} label="تعديل بيانات الموظف" tone="indigo" onClick={() => setFormTarget(emp)} />
                          <IconButton
                            icon={isLocked ? Unlock : Lock}
                            label={isLocked ? 'فك قفل الجهاز' : 'تفعيل قفل الجهاز'}
                            tone={isLocked ? 'amber' : 'emerald'}
                            loading={busy === emp.id}
                            onClick={() => toggleDeviceLock(emp)}
                          />
                          {isLocked && (
                            <IconButton
                              icon={Smartphone}
                              label="إلغاء ربط الهاتف وربط جهاز جديد"
                              tone="violet"
                              loading={busy === `${emp.id}_reset`}
                              onClick={() => resetDeviceBinding(emp)}
                            />
                          )}
                          <IconButton icon={Trash2} label="حذف أو أرشفة الموظف" tone="rose" onClick={() => setDeleteTarget(emp)} />
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
              {data.archived.length === 0 ? (
                <TableEmpty colSpan={7}>لا يوجد موظفون في الأرشيف</TableEmpty>
              ) : (
                data.archived.map((arch) => {
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
                      <td>
                        <Badge tone={meta.tone}>{meta.label}</Badge>
                      </td>
                      <td className="max-w-[220px] truncate" title={arch.archive_reason ?? undefined}>
                        {arch.archive_reason || '—'}
                      </td>
                      <td>
                        {arch.scheduled_deletion_date ? (
                          <span className="text-amber-300 font-bold whitespace-nowrap">
                            <span dir="ltr">{formatDate(arch.scheduled_deletion_date)}</span> ({daysUntil(arch.scheduled_deletion_date)} يوم)
                          </span>
                        ) : (
                          '—'
                        )}
                      </td>
                      <td className="font-mono text-slate-400" dir="ltr">{formatDate(arch.archived_at)}</td>
                      <td className="!text-left">
                        <div className="flex justify-end gap-1.5">
                          {arch.archive_type !== 'permanent' && (
                            <Button size="xs" variant="soft" icon={RotateCcw} loading={busy === `restore_${arch.id}`} onClick={() => restoreArchived(arch)}>
                              تفعيل
                            </Button>
                          )}
                          <Button size="xs" variant="soft-danger" icon={Trash2} loading={busy === `destroy_${arch.id}`} onClick={() => destroyArchived(arch)}>
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
          employee={formTarget === 'new' ? null : formTarget}
          branches={data.branches}
          onClose={() => setFormTarget(null)}
          onSaved={() => {
            setFormTarget(null);
            query.reload();
          }}
        />
      )}

      {deleteTarget && (
        <DeleteEmployeeModal
          employee={deleteTarget}
          onClose={() => setDeleteTarget(null)}
          onDone={() => {
            setDeleteTarget(null);
            query.reload();
          }}
        />
      )}
    </div>
  );
}

/* ------------------------------ Add / edit ------------------------------ */

function FileThumb({ file, onRemove }: { file: File; onRemove: () => void }) {
  const [url] = useState(() => URL.createObjectURL(file));
  useEffect(() => () => URL.revokeObjectURL(url), [url]);
  return <Thumb src={url} onRemove={onRemove} highlight />;
}

function Thumb({ src, onRemove, highlight }: { src: string; onRemove: () => void; highlight?: boolean }) {
  return (
    <div className="relative group">
      <Image
        src={src}
        alt="مستند"
        width={64}
        height={64}
        unoptimized
        className={cn('w-16 h-16 object-cover rounded-xl border', highlight ? 'border-indigo-500/50' : 'border-slate-700')}
      />
      <button
        type="button"
        onClick={onRemove}
        aria-label="إزالة"
        className="absolute -top-2 -right-2 bg-rose-500 text-white rounded-full p-1 opacity-0 group-hover:opacity-100 focus:opacity-100 transition-opacity shadow-md cursor-pointer"
      >
        <X className="w-3 h-3" />
      </button>
    </div>
  );
}

function EmployeeFormModal({
  employee,
  branches,
  onClose,
  onSaved,
}: {
  employee: Employee | null;
  branches: EmployeesData['branches'];
  onClose: () => void;
  onSaved: () => void;
}) {
  const isEdit = !!employee;
  const [fullName, setFullName] = useState(employee?.full_name ?? '');
  const [email, setEmail] = useState(employee?.email ?? '');
  const [phone, setPhone] = useState(employee?.phone ?? '');
  const [password, setPassword] = useState(employee?.plain_password ?? '');
  const [showPassword, setShowPassword] = useState(false);
  const [role, setRole] = useState<string>(employee?.role ?? 'employee');
  const [branchId, setBranchId] = useState(employee?.branch_id ?? '');
  const [salary, setSalary] = useState(Number(employee?.monthly_salary_iqd) || 0);
  const [futureSalary, setFutureSalary] = useState(Number(employee?.future_salary_iqd) || 0);
  const [futureMonth, setFutureMonth] = useState(employee?.future_salary_month ?? '');
  const [existingDocs, setExistingDocs] = useState<string[]>(employee?.document_urls ?? []);
  const [newDocs, setNewDocs] = useState<File[]>([]);
  const [saving, setSaving] = useState(false);

  const create = async () => {
    // A throwaway client so signing up the employee does not replace the admin's session.
    const tempClient = createClient(supabaseUrl, supabaseAnonKey, {
      auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    });
    const { data: signUp, error: signUpErr } = await tempClient.auth.signUp({
      email,
      password,
      options: { data: { full_name: fullName } },
    });
    if (signUpErr) throw signUpErr;
    if (!signUp.user) throw new Error('فشل إنشاء حساب الموظف في المصادقة');

    const documentUrls = await uploadDocuments(signUp.user.id, newDocs);
    const { error } = await supabase.from('employees').insert({
      id: signUp.user.id,
      employee_code: `EMP-${Math.floor(100 + Math.random() * 900)}`,
      full_name: fullName,
      email,
      phone: phone || null,
      role,
      branch_id: branchId || null,
      monthly_salary_iqd: salary || 0,
      plain_password: password,
      is_active: true,
      must_change_password: true,
      document_urls: documentUrls,
    });
    if (error) throw error;
  };

  const update = async () => {
    if (!employee) return;
    const { error: rpcErr } = await supabase.rpc('update_employee_credentials', {
      p_employee_id: employee.id,
      p_email: email,
      p_password: password,
      p_phone: phone || '',
    });
    if (rpcErr) throw rpcErr;

    const removed = (employee.document_urls ?? []).filter((url) => !existingDocs.includes(url));
    for (const url of removed) {
      const match = url.match(/\/employee-documents\/(.+)$/);
      if (match?.[1]) await supabase.storage.from(DOCS_BUCKET).remove([match[1]]);
    }
    const uploaded = await uploadDocuments(employee.id, newDocs);

    const { error } = await supabase
      .from('employees')
      .update({
        full_name: fullName,
        role,
        branch_id: branchId || null,
        monthly_salary_iqd: salary || 0,
        future_salary_iqd: futureSalary || null,
        future_salary_month: futureMonth || null,
        document_urls: [...existingDocs, ...uploaded],
      })
      .eq('id', employee.id);
    if (error) throw error;
  };

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!isEdit && password.length < 6) {
      toast.error('يجب أن تكون كلمة المرور 6 أحرف على الأقل');
      return;
    }
    setSaving(true);
    try {
      if (isEdit) await update();
      else await create();
      confetti({ particleCount: 70, spread: 55, colors: ['#818CF8', '#34D399'] });
      toast.success(isEdit ? 'تم تحديث بيانات الموظف' : 'تم إضافة الموظف وإنشاء حسابه');
      onSaved();
    } catch (err) {
      toast.error(`${isEdit ? 'فشل تعديل بيانات الموظف' : 'فشل إضافة الموظف'}: ${errorMessage(err)}`);
    } finally {
      setSaving(false);
    }
  };

  return (
    <Modal
      title={isEdit ? 'تعديل بيانات الموظف' : 'إضافة موظف جديد'}
      subtitle={isEdit ? employee?.full_name : 'ينشئ حساب دخول لتطبيق الموبايل ويسجل البيانات الوظيفية'}
      icon={isEdit ? Pencil : UserPlus}
      tone="brand"
      size="lg"
      onClose={onClose}
    >
      <form onSubmit={submit} className="space-y-5">
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <Field label="الاسم الكامل">
            <Input required value={fullName} onChange={(e) => setFullName(e.target.value)} placeholder="محمد علي عبد الحسين" />
          </Field>
          <Field label="البريد الإلكتروني (اسم الدخول)">
            <Input type="email" required value={email} onChange={(e) => setEmail(e.target.value)} placeholder="name@company.com" dir="ltr" className="text-left" />
          </Field>
          <Field label="رقم الهاتف">
            <Input type="tel" value={phone} onChange={(e) => setPhone(e.target.value)} placeholder="077XXXXXXXX" dir="ltr" className="text-left" />
          </Field>
          <Field label={isEdit ? 'كلمة المرور' : 'كلمة المرور (6 أحرف فأكثر)'}>
            <div className="relative">
              <Input
                type={showPassword ? 'text' : 'password'}
                required={!isEdit}
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                placeholder="••••••••"
                dir="ltr"
                className="text-left pl-10"
              />
              <button
                type="button"
                onClick={() => setShowPassword((v) => !v)}
                aria-label={showPassword ? 'إخفاء' : 'إظهار'}
                className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-500 hover:text-white cursor-pointer"
              >
                {showPassword ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
              </button>
            </div>
          </Field>
          <Field label="الفرع">
            <Select required value={branchId} onChange={(e) => setBranchId(e.target.value)}>
              <option value="">اختر الفرع...</option>
              {branches.map((b) => (
                <option key={b.id} value={b.id}>
                  {b.name}
                </option>
              ))}
            </Select>
          </Field>
          <Field label="الصلاحية">
            <Select value={role} onChange={(e) => setRole(e.target.value)}>
              <option value="employee">موظف</option>
              <option value="manager">مدير موارد</option>
              <option value="admin">مدير عام</option>
            </Select>
          </Field>
          <Field label="الراتب الأساسي الشهري (د.ع)">
            <AmountInput required value={salary} onValueChange={setSalary} placeholder="1,500,000" />
          </Field>
        </div>

        {isEdit && (
          <div className="rounded-2xl border border-indigo-500/20 bg-indigo-500/5 p-4">
            <p className="text-xs font-bold text-indigo-200 mb-3 flex items-center gap-1.5">
              <Clock className="w-3.5 h-3.5" /> تغيير راتب مجدول (اختياري)
            </p>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <Field label="الراتب الجديد (د.ع)">
                <AmountInput value={futureSalary} onValueChange={setFutureSalary} placeholder="مبلغ الراتب" />
              </Field>
              <Field label="يبدأ من تاريخ">
                <Input type="date" value={futureMonth} onChange={(e) => setFutureMonth(e.target.value)} dir="ltr" />
              </Field>
            </div>
          </div>
        )}

        <Field label="المستمسكات الثبوتية (اختياري)" hint="تُضغط الصور تلقائياً قبل الرفع. يمكنك حذف القديمة وإضافة جديدة.">
          <div className="flex flex-wrap gap-3">
            {existingDocs.map((url) => (
              <Thumb key={url} src={url} onRemove={() => setExistingDocs((prev) => prev.filter((u) => u !== url))} />
            ))}
            {newDocs.map((file, idx) => (
              <FileThumb key={`${file.name}_${idx}`} file={file} onRemove={() => setNewDocs((prev) => prev.filter((_, i) => i !== idx))} />
            ))}
            <label className="w-16 h-16 flex items-center justify-center border border-dashed border-slate-700 rounded-xl cursor-pointer hover:border-indigo-500 hover:bg-slate-800/50 transition-colors">
              <input
                type="file"
                multiple
                accept="image/*"
                className="hidden"
                onChange={(e) => {
                  const files = e.target.files;
                  if (files) setNewDocs((prev) => [...prev, ...Array.from(files)]);
                  e.target.value = '';
                }}
              />
              <Upload className="w-5 h-5 text-slate-500" />
            </label>
          </div>
        </Field>

        <ModalFooter
          onCancel={onClose}
          loading={saving}
          submitLabel={isEdit ? 'حفظ التعديلات' : 'إضافة الموظف'}
          loadingLabel={isEdit ? 'جاري الحفظ...' : 'جاري إنشاء الحساب...'}
          submitIcon={isEdit ? Save : UserPlus}
        />
      </form>
    </Modal>
  );
}

/* ------------------------------ Delete / archive ------------------------------ */

const DELETE_OPTIONS = [
  {
    value: 'archive' as const,
    icon: Archive,
    tone: 'indigo' as Tone,
    title: 'أرشفة وتجميد الحساب (موصى به)',
    body: 'يُمنع الموظف من تسجيل الدوام مع الحفاظ على كل سجلاته في الأرشيف للرجوع إليها.',
  },
  {
    value: 'scheduled' as const,
    icon: Clock,
    tone: 'amber' as Tone,
    title: 'حذف مجدول بعد 30 يوماً',
    body: 'يُجمّد الحساب فوراً ويُحذف ملفه وسجلاته تلقائياً بعد 30 يوماً.',
  },
  {
    value: 'immediate' as const,
    icon: ShieldAlert,
    tone: 'rose' as Tone,
    title: 'حذف فوري ونهائي',
    body: 'يحذف الحساب وكل البصمات والسلف والإجازات نهائياً بدون أي إمكانية للاسترجاع!',
  },
];

function DeleteEmployeeModal({ employee, onClose, onDone }: { employee: Employee; onClose: () => void; onDone: () => void }) {
  const [type, setType] = useState<'archive' | 'scheduled' | 'immediate'>('archive');
  const [reason, setReason] = useState('');
  const [saving, setSaving] = useState(false);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setSaving(true);
    try {
      const {
        data: { session },
      } = await supabase.auth.getSession();
      const base = {
        employee_id: employee.id,
        employee_code: employee.employee_code,
        full_name: employee.full_name,
        archived_by: session?.user?.id,
        archived_at: new Date().toISOString(),
      };

      if (type === 'immediate') {
        const { error } = await supabase.from('employees').delete().eq('id', employee.id);
        if (error) throw error;
        const { error: insErr } = await supabase.from('archived_employees').insert({
          ...base,
          archive_type: 'permanent',
          archive_reason: reason || 'حذف فوري نهائي من لوحة التحكم',
        });
        if (insErr) throw insErr;
      } else {
        const { error } = await supabase.from('employees').update({ is_active: false }).eq('id', employee.id);
        if (error) throw error;
        const deletion = new Date();
        deletion.setDate(deletion.getDate() + 30);
        const { error: insErr } = await supabase.from('archived_employees').insert(
          type === 'archive'
            ? { ...base, archive_type: 'archived', archive_reason: reason || 'أرشفة وتعطيل حساب الموظف' }
            : {
                ...base,
                archive_type: 'scheduled_deletion',
                archive_reason: reason || 'حذف مجدول بعد 30 يوماً من لوحة التحكم',
                scheduled_deletion_date: deletion.toISOString(),
              },
        );
        if (insErr) throw insErr;
      }

      toast.success('تم تنفيذ الإجراء بنجاح');
      onDone();
    } catch (err) {
      toast.error(`فشل إتمام العملية: ${errorMessage(err)}`);
    } finally {
      setSaving(false);
    }
  };

  const selected = DELETE_OPTIONS.find((o) => o.value === type)!;

  return (
    <Modal title="حذف أو أرشفة الموظف" subtitle={`${employee.full_name} · ${employee.employee_code || 'بدون رمز'}`} icon={Trash2} tone="rose" onClose={onClose}>
      <form onSubmit={submit} className="space-y-4">
        <div className="space-y-2">
          {DELETE_OPTIONS.map((opt) => {
            const active = type === opt.value;
            return (
              <label
                key={opt.value}
                className={cn(
                  'flex gap-3 p-3.5 rounded-2xl border cursor-pointer transition-colors',
                  active ? 'border-indigo-400/50 bg-indigo-500/10' : 'border-slate-800 bg-slate-950/40 hover:border-slate-700',
                )}
              >
                <input type="radio" name="deleteType" checked={active} onChange={() => setType(opt.value)} className="mt-1" />
                <opt.icon className={cn('w-4 h-4 mt-0.5 shrink-0', opt.tone === 'rose' ? 'text-rose-400' : opt.tone === 'amber' ? 'text-amber-400' : 'text-indigo-300')} />
                <div>
                  <p className="text-xs font-bold text-white">{opt.title}</p>
                  <p className={cn('text-[11px] mt-1 leading-relaxed', opt.tone === 'rose' ? 'text-rose-300/90' : 'text-slate-400')}>{opt.body}</p>
                </div>
              </label>
            );
          })}
        </div>
        <Field label="السبب (اختياري)">
          <Input value={reason} onChange={(e) => setReason(e.target.value)} placeholder="مثال: استقالة، انتهاء العقد..." />
        </Field>
        <ModalFooter
          onCancel={onClose}
          loading={saving}
          submitLabel="تأكيد وتنفيذ"
          variant={selected.value === 'immediate' ? 'danger' : selected.value === 'scheduled' ? 'warning' : 'primary'}
        />
      </form>
    </Modal>
  );
}
