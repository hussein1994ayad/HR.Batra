'use client';

import React, { useEffect, useMemo, useState } from 'react';
import dynamic from 'next/dynamic';
import toast from 'react-hot-toast';
import {
  Building,
  Plus,
  MapPin,
  Trash2,
  Globe,
  Pencil,
  Users,
  ExternalLink,
  Radius,
  Link2,
  Loader2,
  CheckCircle2,
  Info,
  AlertTriangle,
  Save,
} from 'lucide-react';
import { supabase } from '@/lib/supabase';
import { confetti } from '@/lib/lazy';
import { readCache, useQuery, writeCache } from '@/lib/useQuery';
import { BAGHDAD_CENTER, distanceMeters, resolveMapUrl } from '@/lib/geo';
import { errorMessage, formatClock, localDateStr } from '@/lib/format';
import type { Attendance, Branch } from '@/lib/types';
import { useConfirm } from '@/components/confirm';
import {
  Avatar,
  Badge,
  Button,
  Card,
  CardHeader,
  EmptyState,
  Field,
  IconButton,
  InfoNote,
  Input,
  Modal,
  ModalFooter,
  PageHeader,
  PageSkeleton,
  StatTile,
  Textarea,
  cn,
} from '@/components/ui';

const MapComponent = dynamic(() => import('@/components/MapComponent'), {
  ssr: false,
  loading: () => <div className="skeleton w-full h-full min-h-[420px] rounded-2xl" />,
});

interface GeofencesData {
  branches: Branch[];
  todayLogs: Attendance[];
}

const CACHE_KEY = 'batra_cache_geofences_v2';
const DEFAULT_RADIUS = 150;

async function fetchGeofences(): Promise<GeofencesData> {
  const [branches, logs] = await Promise.all([
    supabase.from('branches').select('*').order('created_at', { ascending: false }),
    supabase
      .from('attendance')
      .select('*, employees!employee_id(full_name, phone, email, branch_id)')
      .eq('work_date', localDateStr()),
  ]);
  if (branches.error) throw branches.error;
  const data = { branches: (branches.data ?? []) as Branch[], todayLogs: (logs.data ?? []) as Attendance[] };
  writeCache(CACHE_KEY, data);
  return data;
}

interface BranchDraft {
  id?: string;
  name: string;
  lat: number;
  lng: number;
  radius: number;
  address: string;
}

export default function GeofencesPage() {
  const confirm = useConfirm();
  const [cached] = useState(() => {
    const c = readCache<GeofencesData>(CACHE_KEY);
    return c && Array.isArray(c.branches) ? c : undefined;
  });
  const query = useQuery('geofences', fetchGeofences, cached);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [draft, setDraft] = useState<BranchDraft | null>(null);
  const [deleting, setDeleting] = useState<string | null>(null);

  const branches = useMemo(() => query.data?.branches ?? [], [query.data]);
  const selected = branches.find((b) => b.id === selectedId) ?? null;

  const circles = useMemo(
    () =>
      branches
        .filter((b) => b.latitude && b.longitude)
        .map((b) => ({ id: b.id, name: b.name, lat: Number(b.latitude), lng: Number(b.longitude), radius: Number(b.radius_meters) || DEFAULT_RADIUS })),
    [branches],
  );

  const attendees = useMemo(() => {
    if (!selected || !query.data) return [];
    const bLat = Number(selected.latitude);
    const bLng = Number(selected.longitude);
    const radius = Number(selected.radius_meters) || DEFAULT_RADIUS;
    return query.data.todayLogs
      .map((log) => {
        const hasCoords = !!log.check_in_lat && !!log.check_in_lng;
        const distance = hasCoords ? distanceMeters(Number(log.check_in_lat), Number(log.check_in_lng), bLat, bLng) : null;
        const belongs =
          log.branch_id === selected.id || log.employees?.branch_id === selected.id || (distance !== null && distance <= radius);
        return belongs ? { log, distance } : null;
      })
      .filter((x): x is { log: Attendance; distance: number | null } => x !== null);
  }, [selected, query.data]);

  if (!query.data) {
    if (query.error) {
      return <EmptyState icon={AlertTriangle} tone="rose" title="تعذر تحميل الفروع" description={errorMessage(query.error)} action={<Button size="sm" variant="secondary" onClick={query.reload}>إعادة المحاولة</Button>} />;
    }
    return <PageSkeleton />;
  }

  const mapCenter: [number, number] = selected?.latitude && selected?.longitude ? [Number(selected.latitude), Number(selected.longitude)] : BAGHDAD_CENTER;
  const mapZoom = selected ? 16 : 12;

  const openNew = (lat = BAGHDAD_CENTER[0], lng = BAGHDAD_CENTER[1]) =>
    setDraft({ name: '', lat, lng, radius: DEFAULT_RADIUS, address: '' });

  const openEdit = (b: Branch) =>
    setDraft({
      id: b.id,
      name: b.name,
      lat: Number(b.latitude),
      lng: Number(b.longitude),
      radius: Number(b.radius_meters) || DEFAULT_RADIUS,
      address: b.address || '',
    });

  const deleteBranch = async (b: Branch) => {
    const ok = await confirm({
      title: `حذف فرع «${b.name}»؟`,
      message: 'سيُلغى ربط الموظفين التابعين لهذا الفرع وقد يتعذر عليهم تسجيل الحضور حتى ربطهم بفرع آخر.',
      confirmLabel: 'حذف الفرع',
    });
    if (!ok) return;
    setDeleting(b.id);
    try {
      const { error } = await supabase.from('branches').delete().eq('id', b.id);
      if (error) throw error;
      query.mutate((d) => ({ ...d, branches: d.branches.filter((x) => x.id !== b.id) }));
      if (selectedId === b.id) setSelectedId(null);
      toast.success('تم حذف الفرع ونطاق البصمة الخاص به');
    } catch (err) {
      toast.error(`فشل حذف الفرع: ${errorMessage(err)}`);
    } finally {
      setDeleting(null);
    }
  };

  return (
    <div className="space-y-6 pb-12">
      <PageHeader
        icon={Globe}
        tone="teal"
        title="الفروع والسياج الجغرافي"
        description="مواقع الفروع ونطاق البصمة المسموح به لتسجيل الحضور من تطبيق الموظفين"
        actions={
          <Button icon={Plus} onClick={() => openNew()}>
            إضافة فرع
          </Button>
        }
      />

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <Card className="flex flex-col">
          <CardHeader icon={Building} tone="teal" title={<>الفروع <Badge tone="teal">{branches.length}</Badge></>} description="اختر فرعاً لعرضه على الخريطة" />
          {branches.length === 0 ? (
            <EmptyState icon={Building} title="لا توجد فروع بعد" description="أضف فرعاً أو انقر على الخريطة لتحديد موقعه." action={<Button size="sm" icon={Plus} onClick={() => openNew()}>إضافة فرع</Button>} />
          ) : (
            <div className="space-y-2 max-h-[440px] overflow-y-auto -mx-1 px-1">
              {branches.map((b) => {
                const active = b.id === selectedId;
                return (
                  <div
                    key={b.id}
                    role="button"
                    tabIndex={0}
                    onClick={() => setSelectedId(active ? null : b.id)}
                    onKeyDown={(e) => (e.key === 'Enter' || e.key === ' ') && setSelectedId(active ? null : b.id)}
                    className={cn(
                      'group p-3.5 rounded-2xl border flex items-center gap-3 cursor-pointer transition-colors',
                      active ? 'bg-teal-500/10 border-teal-400/40' : 'bg-slate-900/50 border-slate-800/80 hover:border-slate-700',
                    )}
                  >
                    <div className={cn('w-9 h-9 shrink-0 rounded-xl border flex items-center justify-center', active ? 'bg-teal-500/20 border-teal-400/30 text-teal-200' : 'bg-slate-800/70 border-slate-700/70 text-slate-400')}>
                      <MapPin className="w-4 h-4" />
                    </div>
                    <div className="flex-1 min-w-0">
                      <p className="text-[13px] font-bold text-white truncate">{b.name}</p>
                      <p className="text-[11px] text-slate-500 truncate">{b.address || 'بدون عنوان'}</p>
                    </div>
                    <Badge tone="slate" className="font-mono">{Number(b.radius_meters) || DEFAULT_RADIUS}م</Badge>
                    <div className="flex gap-1" onClick={(e) => e.stopPropagation()}>
                      <IconButton icon={Pencil} label="تعديل الفرع" tone="indigo" onClick={() => openEdit(b)} />
                      <IconButton icon={Trash2} label="حذف الفرع" tone="rose" loading={deleting === b.id} onClick={() => deleteBranch(b)} />
                    </div>
                  </div>
                );
              })}
            </div>
          )}
          <InfoNote tone="slate" icon={Info} className="mt-4">
            لا يستطيع الموظف تسجيل الحضور أو الانصراف إلا إذا كان داخل دائرة نطاق البصمة لفرعه.
          </InfoNote>
        </Card>

        <Card className="lg:col-span-2 flex flex-col">
          <CardHeader icon={Globe} tone="sky" title="خريطة الفروع" description="انقر على الخريطة لإضافة فرع في ذلك الموقع، أو على دائرة فرع لعرض تفاصيله" />
          <div className="flex-1 min-h-[460px]">
            <MapComponent
              circles={circles}
              selectedCircleId={selectedId}
              center={mapCenter}
              zoom={mapZoom}
              onCircleClick={setSelectedId}
              onMapClick={(lat, lng) => openNew(lat, lng)}
            />
          </div>
        </Card>
      </div>

      {selected && (
        <Card className="animate-fade">
          <CardHeader
            icon={MapPin}
            tone="teal"
            title={selected.name}
            description={selected.address || 'تفاصيل الفرع والموظفين المتواجدين ضمن نطاقه اليوم'}
            actions={
              <a
                href={`https://www.google.com/maps/search/?api=1&query=${selected.latitude},${selected.longitude}`}
                target="_blank"
                rel="noopener noreferrer"
                className="inline-flex items-center gap-1.5 h-9 px-3 rounded-xl bg-slate-800/80 border border-slate-700/80 text-xs font-bold text-slate-100 hover:bg-slate-700/80"
              >
                <ExternalLink className="w-3.5 h-3.5" /> فتح في خرائط Google
              </a>
            }
          />
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-5">
            <StatTile label="نطاق البصمة" value={`${Number(selected.radius_meters) || DEFAULT_RADIUS} متر`} icon={Radius} tone="teal" />
            <StatTile label="الإحداثيات" value={<span className="text-sm font-mono" dir="ltr">{Number(selected.latitude).toFixed(5)}, {Number(selected.longitude).toFixed(5)}</span>} icon={MapPin} tone="sky" />
            <StatTile label="المتواجدون اليوم" value={attendees.length} icon={Users} tone="emerald" />
          </div>
          {attendees.length === 0 ? (
            <EmptyState icon={Users} title="لا يوجد موظفون داخل نطاق هذا الفرع اليوم" />
          ) : (
            <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-3">
              {attendees.map(({ log, distance }) => (
                <div key={log.id} className="flex items-center gap-3 p-3 rounded-2xl bg-slate-900/50 border border-slate-800/80">
                  <Avatar name={log.employees?.full_name} />
                  <div className="flex-1 min-w-0">
                    <p className="text-xs font-bold text-white truncate">{log.employees?.full_name || 'موظف'}</p>
                    <p className="text-[10px] text-slate-500 font-mono" dir="ltr">{log.employees?.phone || '—'}</p>
                  </div>
                  <div className="text-left">
                    <Badge tone="emerald">{formatClock(log.check_in_time)}</Badge>
                    <p className="text-[10px] text-slate-500 mt-1">{distance !== null ? `على بُعد ${Math.round(distance)} م` : 'بصمة يدوية'}</p>
                  </div>
                </div>
              ))}
            </div>
          )}
        </Card>
      )}

      {draft && (
        <BranchFormModal
          draft={draft}
          onClose={() => setDraft(null)}
          onSaved={(savedId) => {
            setDraft(null);
            if (savedId) setSelectedId(savedId);
            query.reload();
          }}
        />
      )}
    </div>
  );
}

function BranchFormModal({ draft, onClose, onSaved }: { draft: BranchDraft; onClose: () => void; onSaved: (id?: string) => void }) {
  const [form, setForm] = useState(draft);
  const [mapLink, setMapLink] = useState('');
  const [resolving, setResolving] = useState(false);
  const [resolved, setResolved] = useState(false);
  const [saving, setSaving] = useState(false);
  const isEdit = !!draft.id;

  // Resolve pasted Google Maps links / coordinates shortly after typing stops.
  useEffect(() => {
    const text = mapLink.trim();
    if (!text) return;
    let cancelled = false;
    const timer = setTimeout(() => {
      setResolving(true);
      setResolved(false);
      resolveMapUrl(text)
        .then((coords) => {
          if (cancelled) return;
          if (coords) {
            setForm((f) => ({ ...f, lat: coords.lat, lng: coords.lng }));
            setResolved(true);
          } else {
            toast.error('تعذر استخراج الإحداثيات من الرابط');
          }
        })
        .finally(() => !cancelled && setResolving(false));
    }, 600);
    return () => {
      cancelled = true;
      clearTimeout(timer);
    };
  }, [mapLink]);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (form.radius <= 0) {
      toast.error('يجب أن يكون نطاق البصمة أكبر من 0 متر');
      return;
    }
    setSaving(true);
    try {
      const payload = { name: form.name, latitude: form.lat, longitude: form.lng, radius_meters: form.radius, address: form.address };
      if (isEdit) {
        const { error } = await supabase.from('branches').update(payload).eq('id', draft.id);
        if (error) throw error;
      } else {
        const { error } = await supabase.from('branches').insert(payload);
        if (error) throw error;
      }
      confetti({ particleCount: 80, spread: 60, colors: ['#2DD4BF', '#818CF8'] });
      toast.success(isEdit ? 'تم تحديث بيانات الفرع' : 'تم إضافة الفرع ونطاق البصمة');
      onSaved(draft.id);
    } catch (err) {
      toast.error(errorMessage(err));
    } finally {
      setSaving(false);
    }
  };

  return (
    <Modal title={isEdit ? 'تعديل الفرع' : 'إضافة فرع جديد'} subtitle="حدد الموقع ونطاق البصمة المسموح" icon={isEdit ? Pencil : Plus} tone="brand" onClose={onClose}>
      <form onSubmit={submit} className="space-y-4">
        <Field label="اسم الفرع">
          <Input required value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} placeholder="مثال: فرع المنصور" />
        </Field>

        <Field
          label={
            <span className="flex items-center justify-between">
              <span>رابط Google Maps أو إحداثيات</span>
              {resolving ? (
                <span className="flex items-center gap-1 text-amber-300"><Loader2 className="w-3 h-3 animate-spin" /> جاري الاستخراج</span>
              ) : resolved ? (
                <span className="flex items-center gap-1 text-emerald-300"><CheckCircle2 className="w-3 h-3" /> تم التحديث</span>
              ) : null}
            </span>
          }
          hint="الصق رابط الموقع من خرائط Google وستُملأ الإحداثيات تلقائياً."
        >
          <div className="relative">
            <Link2 className="absolute right-3 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-500 pointer-events-none" />
            <Input value={mapLink} onChange={(e) => setMapLink(e.target.value)} placeholder="https://maps.app.goo.gl/... أو 33.3152, 44.3661" className="pr-9" dir="ltr" />
          </div>
        </Field>

        <div className="grid grid-cols-2 gap-3">
          <Field label="خط العرض (Latitude)">
            <Input type="number" step="any" required value={form.lat} onChange={(e) => setForm({ ...form, lat: Number(e.target.value) })} dir="ltr" className="text-left font-mono" />
          </Field>
          <Field label="خط الطول (Longitude)">
            <Input type="number" step="any" required value={form.lng} onChange={(e) => setForm({ ...form, lng: Number(e.target.value) })} dir="ltr" className="text-left font-mono" />
          </Field>
        </div>

        <Field label={`نطاق البصمة: ${form.radius} متر`}>
          <div className="flex items-center gap-3">
            <input
              type="range"
              min={20}
              max={1000}
              step={10}
              value={form.radius}
              onChange={(e) => setForm({ ...form, radius: Number(e.target.value) })}
              className="flex-1"
            />
            <Input type="number" min={1} required value={form.radius} onChange={(e) => setForm({ ...form, radius: Number(e.target.value) })} className="w-24 text-left font-mono" dir="ltr" />
          </div>
        </Field>

        <Field label="العنوان (اختياري)">
          <Textarea rows={2} value={form.address} onChange={(e) => setForm({ ...form, address: e.target.value })} placeholder="مثال: بغداد، شارع المنصور، قرب مول المنصور" />
        </Field>

        <ModalFooter onCancel={onClose} loading={saving} submitLabel={isEdit ? 'حفظ التعديلات' : 'إضافة الفرع'} submitIcon={isEdit ? Save : Plus} />
      </form>
    </Modal>
  );
}
