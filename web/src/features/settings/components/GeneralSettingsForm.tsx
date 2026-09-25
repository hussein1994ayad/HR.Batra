'use client';

import React, { useState } from 'react';
import type { CompanyInfo, GeneralSettings, SystemPolicies } from '../types';
import { ArchivePolicyCard } from './ArchivePolicyCard';
import { CompanyProfileCard } from './CompanyProfileCard';
import { LeavePolicyCard } from './LeavePolicyCard';
import { PayrollCycleCard } from './PayrollCycleCard';
import { Save, Loader2 } from 'lucide-react';

interface GeneralSettingsFormProps {
  initial: GeneralSettings;
  saving: boolean;
  onSave: (values: GeneralSettings) => void;
}

/** نموذج بيانات الشركة وسياسات النظام، يُحفظ بزر واحد. */
export function GeneralSettingsForm({ initial, saving, onSave }: GeneralSettingsFormProps) {
  const [company, setCompany] = useState<CompanyInfo>(initial.company);
  const [policies, setPolicies] = useState<SystemPolicies>(initial.policies);
  const updateCompany = (patch: Partial<CompanyInfo>) => setCompany(prev => ({ ...prev, ...patch }));
  const updatePolicies = (patch: Partial<SystemPolicies>) => setPolicies(prev => ({ ...prev, ...patch }));

  const handleSaveSettings = (e: React.FormEvent) => {
    e.preventDefault();
    onSave({ company, policies });
  };

  return (
    <form onSubmit={handleSaveSettings} className="grid grid-cols-1 lg:grid-cols-3 gap-8">
      <div className="lg:col-span-2 space-y-6">
        <CompanyProfileCard company={company} onChange={updateCompany} />
        <LeavePolicyCard
          defaultAnnual={policies.defaultAnnual}
          defaultSick={policies.defaultSick}
          leaveTypes={policies.leaveTypes}
          onChange={updatePolicies}
        />
      </div>

      <div className="space-y-6">
        <ArchivePolicyCard trackingDays={policies.trackingDays} onChange={updatePolicies} />
        <PayrollCycleCard cycleStartDay={policies.cycleStartDay} cycleEndDay={policies.cycleEndDay} onChange={updatePolicies} />

        <div className="bg-slate-900/40 backdrop-blur-xl border border-slate-800/80 rounded-3xl p-6 shadow-xl">
          <button
            type="submit"
            disabled={saving}
            className="w-full flex items-center justify-center gap-2 py-3.5 px-4 bg-gradient-to-l from-teal-650 to-teal-500 hover:from-teal-600 hover:to-teal-400 text-white rounded-xl text-xs font-bold transition-all shadow-md shadow-teal-500/10 active:scale-95 cursor-pointer"
          >
            {saving ? (
              <>
                <Loader2 className="w-4 h-4 animate-spin" />
                <span>جاري التحديث والحفظ...</span>
              </>
            ) : (
              <>
                <Save className="w-4 h-4" />
                <span>حفظ إعدادات النظام والشركة 💾</span>
              </>
            )}
          </button>
        </div>
      </div>
    </form>
  );
}
