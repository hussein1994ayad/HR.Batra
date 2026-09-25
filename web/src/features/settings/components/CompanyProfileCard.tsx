'use client';

import type { CompanyInfo } from '../types';
import { Building, Phone, Mail, Globe, CreditCard } from 'lucide-react';

interface CompanyProfileCardProps {
  company: CompanyInfo;
  onChange: (patch: Partial<CompanyInfo>) => void;
}

/** بيانات الشركة الرسمية (تظهر في الكشوف المطبوعة). */
export function CompanyProfileCard({ company, onChange }: CompanyProfileCardProps) {
  return (
    <div className="bg-slate-900/40 backdrop-blur-xl border border-slate-800/80 rounded-3xl p-6 shadow-xl space-y-6">
      <div className="flex items-center gap-2 text-teal-400 pb-3 border-b border-slate-850">
        <Building className="w-5 h-5" />
        <h4 className="text-sm font-extrabold text-white">بيانات الشركة الرسمية والترويجية</h4>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        <div>
          <label className="block text-xs text-slate-400 mb-1 flex items-center gap-1">
            <span>اسم الشركة / المؤسسة الرسمي</span>
          </label>
          <input
            type="text"
            required
            value={company.name}
            onChange={(e) => onChange({ name: e.target.value })}
            className="w-full bg-slate-950 border border-slate-800 focus:border-teal-500 rounded-xl p-3 text-xs text-white outline-none"
          />
        </div>

        <div>
          <label className="block text-xs text-slate-400 mb-1 flex items-center gap-1">
            <span>العنوان والفرع الرئيسي للشركة</span>
          </label>
          <input
            type="text"
            value={company.address}
            onChange={(e) => onChange({ address: e.target.value })}
            className="w-full bg-slate-950 border border-slate-800 focus:border-teal-500 rounded-xl p-3 text-xs text-white outline-none"
          />
        </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        <div>
          <label className="block text-xs text-slate-400 mb-1 flex items-center gap-1 font-mono">
            <Phone className="w-3.5 h-3.5" />
            <span>رقم الهاتف المعتمد</span>
          </label>
          <input
            type="tel"
            value={company.phone}
            onChange={(e) => onChange({ phone: e.target.value })}
            className="w-full bg-slate-950 border border-slate-800 focus:border-teal-500 rounded-xl p-3 text-xs text-white outline-none text-left"
            dir="ltr"
          />
        </div>

        <div>
          <label className="block text-xs text-slate-400 mb-1 flex items-center gap-1 font-mono">
            <Mail className="w-3.5 h-3.5" />
            <span>البريد الإلكتروني المعتمد للشركة</span>
          </label>
          <input
            type="email"
            value={company.email}
            onChange={(e) => onChange({ email: e.target.value })}
            className="w-full bg-slate-950 border border-slate-800 focus:border-teal-500 rounded-xl p-3 text-xs text-white outline-none text-left"
            dir="ltr"
          />
        </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        <div>
          <label className="block text-xs text-slate-400 mb-1 flex items-center gap-1 font-mono">
            <Globe className="w-3.5 h-3.5" />
            <span>الموقع الإلكتروني الرسمي (إن وجد)</span>
          </label>
          <input
            type="text"
            value={company.website}
            onChange={(e) => onChange({ website: e.target.value })}
            className="w-full bg-slate-950 border border-slate-800 focus:border-teal-500 rounded-xl p-3 text-xs text-white outline-none text-left"
            dir="ltr"
          />
        </div>

        <div>
          <label className="block text-xs text-slate-400 mb-1 flex items-center gap-1">
            <CreditCard className="w-3.5 h-3.5" />
            <span>الرقم أو الملف الضريبي (اختياري)</span>
          </label>
          <input
            type="text"
            value={company.tax_number}
            onChange={(e) => onChange({ tax_number: e.target.value })}
            className="w-full bg-slate-950 border border-slate-800 focus:border-teal-500 rounded-xl p-3 text-xs text-white outline-none text-left"
            dir="ltr"
          />
        </div>
      </div>

      <div>
        <label className="block text-xs text-slate-400 mb-1">شعار الشركة (رابط الصورة / Logo URL)</label>
        <input
          type="text"
          placeholder="https://example.com/logo.png"
          value={company.logo_url}
          onChange={(e) => onChange({ logo_url: e.target.value })}
          className="w-full bg-slate-950 border border-slate-800 focus:border-teal-500 rounded-xl p-3 text-xs text-white outline-none text-left font-mono"
          dir="ltr"
        />
      </div>
    </div>
  );
}
