'use client';

// صفحة الفروع والسياج الجغرافي: خريطة الفروع ونطاق البصمة، ومن بصم اليوم بكل فرع.
// البيانات في features/geofences/api، والحسابات في features/geofences/logic.

import React, { useMemo, useState } from 'react';
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
  Info,
  AlertTriangle,
} from 'lucide-react';
import { readCache, useQuery } from '@/lib/useQuery';
import { BAGHDAD_CENTER } from '@/lib/geo';
import { errorMessage, formatClock } from '@/lib/format';
import type { Branch } from '@/lib/db-types';
import { useConfirm } from '@/components/confirm';
import { GEOFENCES_CACHE_KEY, deleteBranch as removeBranch, fetchGeofences, type GeofencesData } from '@/features/geofences/api';
import { DEFAULT_RADIUS, attendeesForBranch, branchCircles, type BranchDraft } from '@/features/geofences/logic';
import { BranchFormModal } from '@/features/geofences/components/BranchFormModal';
import {
  Avatar,
  Badge,
  Button,
  Card,
  CardHeader,
  EmptyState,
  IconButton,
  InfoNote,
  PageHeader,
  PageSkeleton,
  StatTile,
  cn,
} from '@/components/ui';

const MapComponent = dynamic(() => import('@/components/MapComponent'), {
  ssr: false,
  loading: () => <div className="skeleton w-full h-full min-h-[420px] rounded-2xl" />,
});

export default function GeofencesPage() {
  const confirm = useConfirm();
  const [cached] = useState(() => {
    const c = readCache<GeofencesData>(GEOFENCES_CACHE_KEY);
    return c && Array.isArray(c.branches) ? c : undefined;
  });
  const query = useQuery('geofences', fetchGeofences, cached);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [draft, setDraft] = useState<BranchDraft | null>(null);
  const [deleting, setDeleting] = useState<string | null>(null);

  const branches = useMemo(() => query.data?.branches ?? [], [query.data]);
  const selected = branches.find((b) => b.id === selectedId) ?? null;

  const circles = useMemo(() => branchCircles(branches), [branches]);

  const attendees = useMemo(
    () => (!selected || !query.data ? [] : attendeesForBranch(selected, query.data.todayLogs)),
    [selected, query.data],
  );

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
      await removeBranch(b.id);
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
