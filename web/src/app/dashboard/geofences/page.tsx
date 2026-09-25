'use client';

import { useMemo, useState } from 'react';
import { Loader2 } from 'lucide-react';
import type { Branch } from '@/lib/db-types';
import type { BranchInput } from '@/features/geofences/api';
import { BAGHDAD, DEFAULT_RADIUS, branchAttendees, mapCircles } from '@/features/geofences/logic';
import { useGeofences } from '@/features/geofences/useGeofences';
import { BranchDetails } from '@/features/geofences/components/BranchDetails';
import { BranchFormModal } from '@/features/geofences/components/BranchFormModal';
import { BranchList } from '@/features/geofences/components/BranchList';
import { BranchMap } from '@/features/geofences/components/BranchMap';

type FormState = { mode: 'create'; initial: BranchInput } | { mode: 'edit'; branch: Branch };

const newBranch = (lat = BAGHDAD.lat, lng = BAGHDAD.lng): BranchInput => ({
  name: '', latitude: lat, longitude: lng, radius_meters: DEFAULT_RADIUS, address: '',
});

export default function GeofencesPage() {
  const g = useGeofences();
  const [form, setForm] = useState<FormState | null>(null);

  const circles = useMemo(() => mapCircles(g.branches), [g.branches]);
  const selectedBranch = g.branches.find(b => b.id === g.selectedBranchId) ?? null;
  const attendees = useMemo(
    () => (selectedBranch ? branchAttendees(selectedBranch, g.todayLogs) : []),
    [selectedBranch, g.todayLogs],
  );

  if (g.loading) {
    return (
      <div className="flex-grow flex items-center justify-center">
        <Loader2 className="w-10 h-10 text-teal-400 animate-spin" />
      </div>
    );
  }

  return (
    <div className="space-y-8 pb-12">
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
        <BranchList
          branches={g.branches}
          selectedBranchId={g.selectedBranchId}
          actionLoading={g.actionLoading}
          onAdd={() => setForm({ mode: 'create', initial: newBranch() })}
          onSelect={g.selectBranch}
          onEdit={(branch) => setForm({ mode: 'edit', branch })}
          onDelete={(id) => void g.removeBranch(id)}
        />
        <BranchMap
          mapCircles={circles}
          selectedBranchId={g.selectedBranchId}
          mapCenter={g.mapView.center}
          mapZoom={g.mapView.zoom}
          onSelect={g.selectBranch}
          onMapClick={(lat, lng) => setForm({ mode: 'create', initial: newBranch(lat, lng) })}
        />
      </div>

      {selectedBranch && <BranchDetails branch={selectedBranch} attendees={attendees} />}

      {form && (
        <BranchFormModal
          key={form.mode === 'edit' ? form.branch.id : 'new'}
          mode={form.mode}
          initial={form.mode === 'edit'
            ? { ...form.branch, radius_meters: form.branch.radius_meters || DEFAULT_RADIUS, address: form.branch.address || '' }
            : form.initial}
          saving={g.actionLoading === (form.mode === 'edit' ? 'update' : 'create')}
          onClose={() => setForm(null)}
          onSubmit={async (input) => {
            const ok = form.mode === 'edit' ? await g.editBranch(form.branch.id, input) : await g.addBranch(input);
            if (ok) setForm(null);
          }}
        />
      )}
    </div>
  );
}
